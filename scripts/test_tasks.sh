#!/usr/bin/env bash

#----------------------------------------------------------------------------------------------------
# test_tasks.sh
# author: Kabera Clapton
#
# description: Batch 2 evidence. Runs the task API end to end against the deployed stack as an admin
#              and a member, checks every expected status code, and saves everything to
#              docs/evidence/05-task-api.txt. Exits non-zero if any check fails.
#              Tokens are never written to disk.
#
# usage:       ./scripts/test_tasks.sh <admin-email> <member-email>
#----------------------------------------------------------------------------------------------------

set -euo pipefail

export AWS_REGION="${AWS_REGION:-eu-west-1}"

[[ $# -eq 2 ]] || { echo "Usage: $0 <admin-email> <member-email>" >&2; exit 2; }
readonly ADMIN_EMAIL="$1"
readonly MEMBER_EMAIL="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly INFRA_DIR="$SCRIPT_DIR/../infra"
readonly EVIDENCE_DIR="$SCRIPT_DIR/../docs/evidence"
mkdir -p "$EVIDENCE_DIR"
readonly OUT="$EVIDENCE_DIR/05-task-api.txt"
: >"$OUT"

API_URL="$(terraform -chdir="$INFRA_DIR" output -raw gateway_url)" # TODO(kabera): your output name
API_URL="${API_URL%/}"
readonly API_URL
POOL_ID="$(terraform -chdir="$INFRA_DIR" output -raw user_pool_id)"
readonly POOL_ID
CLIENT_ID="$(terraform -chdir="$INFRA_DIR" output -raw user_pool_client_id)"
readonly CLIENT_ID

BODY_FILE="$(mktemp)"
readonly BODY_FILE
trap 'rm -f "$BODY_FILE"' EXIT

FAILURES=0
STATUS=""

log() { echo "$*" | tee -a "$OUT"; }

# Read one field from the last response body, e.g. json_field taskId
json_field() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$BODY_FILE" "$1"
}

get_token() {
  local email="$1" password
  read -rsp "Password for $email: " password
  echo >&2
  aws cognito-idp admin-initiate-auth \
    --user-pool-id "$POOL_ID" --client-id "$CLIENT_ID" \
    --auth-flow ADMIN_USER_PASSWORD_AUTH \
    --auth-parameters USERNAME="$email",PASSWORD="$password" \
    --query 'AuthenticationResult.AccessToken' --output text
}

# call <label> <expected-status> <method> <path> <token|-> [json-body]
call() {
  local label="$1" expected="$2" method="$3" path="$4" token="$5" body="${6:-}"
  local args=(-s -o "$BODY_FILE" -w '%{http_code}' -X "$method")
  [[ "$token" != "-" ]] && args+=(-H "Authorization: Bearer $token")
  [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" --data "$body")

  STATUS="$(curl "${args[@]}" "$API_URL$path")"

  local verdict="PASS"
  if [[ "$STATUS" != "$expected" ]]; then
    verdict="FAIL"
    FAILURES=$((FAILURES + 1))
  fi
  log ""
  log "=== [$verdict] $label: $method $path -> HTTP $STATUS (expected $expected)"
  [[ -n "$body" ]] && log "request:  $body"
  log "response: $(cat "$BODY_FILE")"
}

log "Task API test run $(date -u +%Y-%m-%dT%H:%M:%SZ) against $API_URL"

ADMIN_TOKEN="$(get_token "$ADMIN_EMAIL")"
MEMBER_TOKEN="$(get_token "$MEMBER_EMAIL")"

DEADLINE="$(python3 -c 'from datetime import datetime,timedelta,timezone as t; print((datetime.now(t.utc)+timedelta(days=3)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"

call "No token is rejected by the authorizer" 401 GET /tasks -

call "Admin lists members" 200 GET /users "$ADMIN_TOKEN"
MEMBER_SUB="$(python3 -c '
import json, sys
users = json.load(open(sys.argv[1]))["items"]
print(next(u["id"] for u in users if u["email"] == sys.argv[2]))' "$BODY_FILE" "$MEMBER_EMAIL")"
log "member sub: $MEMBER_SUB"

TASK_BODY="{\"title\":\"Inspect pump station 4\",\"description\":\"Check pressure and log readings\",\"deadline\":\"$DEADLINE\",\"assigneeId\":\"$MEMBER_SUB\"}"

call "Member cannot create tasks" 403 POST /tasks "$MEMBER_TOKEN" "$TASK_BODY"
call "Admin creates and assigns a task" 201 POST /tasks "$ADMIN_TOKEN" "$TASK_BODY"
TASK_ID="$(json_field taskId)"

call "Member sees the task in their list" 200 GET /tasks "$MEMBER_TOKEN"
call "Member cannot change the title" 403 PUT "/tasks/$TASK_ID" "$MEMBER_TOKEN" '{"title":"x","version":1}'
call "Member moves task to IN_PROGRESS" 200 PUT "/tasks/$TASK_ID" "$MEMBER_TOKEN" '{"status":"IN_PROGRESS","version":1}'
call "Admin with a stale version gets a conflict" 409 PUT "/tasks/$TASK_ID" "$ADMIN_TOKEN" '{"title":"Renamed","version":1}'
call "Admin sees the task with its history" 200 GET "/tasks/$TASK_ID" "$ADMIN_TOKEN"
call "Unknown task returns 404" 404 GET "/tasks/00000000-0000-4000-8000-000000000000" "$ADMIN_TOKEN"

log ""
if [[ "$FAILURES" -eq 0 ]]; then
  log "ALL CHECKS PASSED. Evidence: $OUT"
else
  log "$FAILURES CHECK(S) FAILED. See $OUT"
  exit 1
fi
