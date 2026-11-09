#!/usr/bin/env bash

#----------------------------------------------------------------------------------------------------
# test_attachments.sh
# author: Kabera Clapton
#
# description: Batch 4 evidence. As the member, takes their first task, asks for a presigned upload,
#              uploads a small file straight to S3, proves S3 itself rejects a file that is too large
#              or of a different type, then lists and downloads the file and compares it byte for byte.
#              Output goes to docs/evidence/07-attachments.txt. Needs at least one task assigned to
#              the member (run test_tasks.sh first).
#
# usage:       ./scripts/test_attachments.sh <member-email>
#----------------------------------------------------------------------------------------------------

set -euo pipefail

export AWS_REGION="${AWS_REGION:-eu-west-1}"

[[ $# -eq 1 ]] || { echo "Usage: $0 <member-email>" >&2; exit 2; }
readonly MEMBER_EMAIL="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly INFRA_DIR="$SCRIPT_DIR/../infra"
readonly EVIDENCE_DIR="$SCRIPT_DIR/../docs/evidence"
mkdir -p "$EVIDENCE_DIR"
readonly OUT="$EVIDENCE_DIR/07-attachments.txt"
: >"$OUT"

API_URL="$(terraform -chdir="$INFRA_DIR" output -raw gateway_url)"
API_URL="${API_URL%/}"
readonly API_URL
POOL_ID="$(terraform -chdir="$INFRA_DIR" output -raw user_pool_id)"
readonly POOL_ID
CLIENT_ID="$(terraform -chdir="$INFRA_DIR" output -raw user_pool_client_id)"
readonly CLIENT_ID

WORK_DIR="$(mktemp -d)"
readonly WORK_DIR
trap 'rm -rf "$WORK_DIR"' EXIT
readonly BODY="$WORK_DIR/body.json"

FAILURES=0
log() { echo "$*" | tee -a "$OUT"; }
check() {
  if [[ "$2" == "$3" ]]; then log "[PASS] $1 (HTTP $2)"; else
    log "[FAIL] $1: got $2, expected $3"
    FAILURES=$((FAILURES + 1))
  fi
}
# Read a value from the last response: field items 0 taskId  ->  body["items"][0]["taskId"]
field() {
  python3 -c '
import json, sys
value = json.load(open(sys.argv[1]))
for part in sys.argv[2:]:
    value = value[int(part)] if part.isdigit() else value[part]
print(value)' "$BODY" "$@"
}

# Ask the API for a presigned POST; leaves the response in $BODY
request_upload() {
  local name="$1" type="$2" size="$3"
  curl -s -o "$BODY" -w '%{http_code}' -X POST "$API_URL/tasks/$TASK_ID/attachments" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    --data "{\"fileName\":\"$name\",\"contentType\":\"$type\",\"size\":$size}"
}

# POST a file to S3 using the fields from $BODY. The file part must come LAST.
# --form-string sends values literally (a value starting with @ or < is not read as a file).
upload_to_s3() {
  local file="$1" type="$2"
  local args=()
  while IFS=$'\t' read -r key value; do
    args+=(--form-string "$key=$value")
  done < <(python3 -c '
import json, sys
for k, v in json.load(open(sys.argv[1]))["upload"]["fields"].items():
    print(f"{k}\t{v}")' "$BODY")
  local url
  url="$(field upload url)"
  curl -s -o "$WORK_DIR/s3.xml" -w '%{http_code}' "${args[@]}" -F "file=@$file;type=$type" "$url"
}

log "Attachment test run $(date -u +%Y-%m-%dT%H:%M:%SZ)"

read -rsp "Password for $MEMBER_EMAIL: " PASSWORD
echo
TOKEN="$(aws cognito-idp admin-initiate-auth \
  --user-pool-id "$POOL_ID" --client-id "$CLIENT_ID" \
  --auth-flow ADMIN_USER_PASSWORD_AUTH \
  --auth-parameters USERNAME="$MEMBER_EMAIL",PASSWORD="$PASSWORD" \
  --query 'AuthenticationResult.AccessToken' --output text)"
unset PASSWORD

curl -s -o "$BODY" -H "Authorization: Bearer $TOKEN" "$API_URL/tasks"
TASK_ID="$(field items 0 taskId)"
log "Using task $TASK_ID"

# 1. Normal upload
printf 'Pump station 4 readings\npressure: 3.2 bar\n' >"$WORK_DIR/readings.txt"
SIZE="$(wc -c <"$WORK_DIR/readings.txt" | tr -d ' ')"
check "Request upload for readings.txt" "$(request_upload readings.txt text/plain "$SIZE")" 201
check "Upload directly to S3" "$(upload_to_s3 "$WORK_DIR/readings.txt" text/plain)" 204

# 2. S3 enforces the signed policy, not just the API
head -c $((11 * 1024 * 1024)) /dev/zero >"$WORK_DIR/big.txt"
request_upload big.txt text/plain 100 >/dev/null # claim a small file...
check "S3 rejects a file over 10 MB (signed size limit)" \
  "$(upload_to_s3 "$WORK_DIR/big.txt" text/plain)" 400 # ...then send a big one
log "S3 said: $(grep -o '<Code>[^<]*</Code>' "$WORK_DIR/s3.xml" || true)"

request_upload readings.txt text/plain "$SIZE" >/dev/null
check "S3 rejects a different content type (signed policy)" \
  "$(upload_to_s3 "$WORK_DIR/readings.txt" text/html)" 403
log "S3 said: $(grep -o '<Code>[^<]*</Code>' "$WORK_DIR/s3.xml" || true)"

check "API rejects a disallowed type" "$(request_upload page.html text/html 10)" 400

# 3. List and download
check "List attachments" "$(curl -s -o "$BODY" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" "$API_URL/tasks/$TASK_ID/attachments")" 200
log "listing: $(python3 -c '
import json, sys
for i in json.load(open(sys.argv[1]))["items"]:
    print(i["fileName"], i["size"], i["uploadedAt"])' "$BODY")"

DOWNLOAD_URL="$(python3 -c '
import json, sys
items = [i for i in json.load(open(sys.argv[1]))["items"] if i["fileName"] == "readings.txt"]
print(items[-1]["downloadUrl"])' "$BODY")"
check "Download with the presigned URL" \
  "$(curl -s -o "$WORK_DIR/downloaded.txt" -w '%{http_code}' "$DOWNLOAD_URL")" 200
if cmp -s "$WORK_DIR/readings.txt" "$WORK_DIR/downloaded.txt"; then
  log "[PASS] Downloaded file matches the upload byte for byte"
else
  log "[FAIL] Downloaded file differs from the upload"
  FAILURES=$((FAILURES + 1))
fi

check "Bucket is not public (direct URL without signature)" \
  "$(curl -s -o /dev/null -w '%{http_code}' "${DOWNLOAD_URL%%\?*}")" 403

log ""
if [[ "$FAILURES" -eq 0 ]]; then log "ALL CHECKS PASSED. Evidence: $OUT"; else
  log "$FAILURES CHECK(S) FAILED. See $OUT"
  exit 1
fi
