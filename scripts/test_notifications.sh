#!/usr/bin/env bash

#----------------------------------------------------------------------------------------------------
# test_notifications.sh
# author: Kabera Clapton
#
# description: Batch 3 evidence. Shows the SNS subscriptions, creates a task due in 2 hours (which
#              should email the member via the stream notifier), runs the deadline reminder twice
#              (first run sends, second run sends nothing), sends a manual nudge, and checks the
#              dead-letter queue is empty. Output goes to docs/evidence/06-notifications.txt.
#              Then screenshot the received emails into docs/evidence/ yourself.
#
# usage:       ./scripts/test_notifications.sh <admin-email> <member-email>
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
readonly OUT="$EVIDENCE_DIR/06-notifications.txt"
: >"$OUT"

tf_output() { terraform -chdir="$INFRA_DIR" output -raw "$1"; }

API_URL="$(tf_output gateway_url)"
API_URL="${API_URL%/}"
readonly API_URL
POOL_ID="$(tf_output user_pool_id)"
readonly POOL_ID
CLIENT_ID="$(tf_output user_pool_client_id)"
readonly CLIENT_ID
TOPIC_ARN="$(tf_output topic_arn)"
readonly TOPIC_ARN
DLQ_URL="$(tf_output notifier_dlq_url)"
readonly DLQ_URL

function_name() {
  terraform -chdir="$INFRA_DIR" output -json function_names |
    python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}
REMINDER_FN="$(function_name deadline_reminder)"
readonly REMINDER_FN
NOTIFIER_FN="$(function_name task_notifier)"
readonly NOTIFIER_FN

WORK_DIR="$(mktemp -d)"
readonly WORK_DIR
trap 'rm -rf "$WORK_DIR"' EXIT
readonly BODY_FILE="$WORK_DIR/body.json"

FAILURES=0
log() { echo "$*" | tee -a "$OUT"; }
check() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    log "[PASS] $label ($actual)"
  else
    log "[FAIL] $label: got '$actual', expected '$expected'"
    FAILURES=$((FAILURES + 1))
  fi
}

log "Notification test run $(date -u +%Y-%m-%dT%H:%M:%SZ)"

log ""
log "=== SNS subscriptions (PendingConfirmation = link not clicked yet; no mail until it is)"
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
  --query 'Subscriptions[].[Endpoint, SubscriptionArn]' --output table | tee -a "$OUT"

read -rsp "Password for $ADMIN_EMAIL: " PASSWORD
echo
TOKEN="$(aws cognito-idp admin-initiate-auth \
  --user-pool-id "$POOL_ID" --client-id "$CLIENT_ID" \
  --auth-flow ADMIN_USER_PASSWORD_AUTH \
  --auth-parameters USERNAME="$ADMIN_EMAIL",PASSWORD="$PASSWORD" \
  --query 'AuthenticationResult.AccessToken' --output text)"
unset PASSWORD

curl -s -o "$BODY_FILE" -H "Authorization: Bearer $TOKEN" "$API_URL/users"
MEMBER_SUB="$(python3 -c '
import json, sys
print(next(u["id"] for u in json.load(open(sys.argv[1]))["items"] if u["email"] == sys.argv[2]))' \
  "$BODY_FILE" "$MEMBER_EMAIL")"

DEADLINE="$(python3 -c 'from datetime import datetime,timedelta,timezone as t; print((datetime.now(t.utc)+timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"

log ""
log "=== Create a task due in 2 hours (expect a 'New task assigned' email to $MEMBER_EMAIL)"
STATUS="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$API_URL/tasks" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data "{\"title\":\"Notification test: check generator\",\"deadline\":\"$DEADLINE\",\"assigneeId\":\"$MEMBER_SUB\"}")"
check "create task" "$STATUS" "201"
TASK_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["taskId"])' "$BODY_FILE")"
log "task: $TASK_ID"

log ""
log "=== Waiting 20s for the stream notifier, then its recent logs"
sleep 20
aws logs tail "/aws/lambda/$NOTIFIER_FN" --since 5m | tail -n 20 | tee -a "$OUT"

invoke_reminder() {
  aws lambda invoke --function-name "$REMINDER_FN" --cli-binary-format raw-in-base64-out \
    --payload '{"source":"manual-test"}' "$WORK_DIR/reminder.json" >/dev/null
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("remindersSent"))' "$WORK_DIR/reminder.json"
}

log ""
log "=== Deadline reminder, first run (expect at least 1 sent)"
FIRST="$(invoke_reminder)"
log "remindersSent: $FIRST"
if [[ "$FIRST" =~ ^[0-9]+$ ]] && ((FIRST >= 1)); then log "[PASS] first run sent reminders"; else
  log "[FAIL] first run sent no reminders"
  FAILURES=$((FAILURES + 1))
fi

log ""
log "=== Deadline reminder, second run (expect 0: each task is reminded once)"
check "second run sends nothing" "$(invoke_reminder)" "0"

log ""
log "=== Manual nudge (expect a 'Reminder:' email)"
STATUS="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$API_URL/tasks/$TASK_ID/notify" \
  -H "Authorization: Bearer $TOKEN")"
check "POST /tasks/{id}/notify" "$STATUS" "200"
log "response: $(cat "$BODY_FILE")"

log ""
log "=== Dead-letter queue (expect 0 failed notifications)"
DEPTH="$(aws sqs get-queue-attributes --queue-url "$DLQ_URL" \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' --output text)"
check "DLQ is empty" "$DEPTH" "0"

log ""
if [[ "$FAILURES" -eq 0 ]]; then
  log "ALL CHECKS PASSED. Now screenshot the 3 emails ($MEMBER_EMAIL inbox) into docs/evidence/."
else
  log "$FAILURES CHECK(S) FAILED. See $OUT"
  exit 1
fi
