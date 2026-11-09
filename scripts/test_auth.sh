#!/usr/bin/env bash

#----------------------------------------------------------------------------------------------------
# test_auth.sh
# author: Kabera Clapton
#
# description: Step 4 evidence. Checks that GET /hello rejects missing and tampered tokens (401) and
#              accepts a valid Cognito access token (200). Output is saved to docs/evidence/.
#              The token itself is never written to disk.
#
# usage:       ./scripts/test_auth.sh <email>
#----------------------------------------------------------------------------------------------------

set -euo pipefail

export AWS_REGION="${AWS_REGION:-eu-west-1}"

[[ $# -eq 1 ]] || { echo "Usage: $0 <email>" >&2; exit 2; }
readonly EMAIL="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly INFRA_DIR="$SCRIPT_DIR/../infra"
readonly EVIDENCE_DIR="$SCRIPT_DIR/../docs/evidence"
mkdir -p "$EVIDENCE_DIR"

API_URL="$(terraform -chdir="$INFRA_DIR" output -raw gateway_url)" # TODO(kabera): your output name
readonly API_URL
POOL_ID="$(terraform -chdir="$INFRA_DIR" output -raw user_pool_id)"
readonly POOL_ID
CLIENT_ID="$(terraform -chdir="$INFRA_DIR" output -raw user_pool_client_id)"
readonly CLIENT_ID

readonly OUT="$EVIDENCE_DIR/04-auth-tests.txt"
: >"$OUT" # start a fresh evidence file

log() { echo "$*" | tee -a "$OUT"; }

# Prints the HTTP status, then the body; both go to the terminal and the evidence file
request() {
  local label="$1"
  shift
  log ""
  log "=== $label ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="
  curl -s -w '\nHTTP %{http_code}\n' "$@" "${API_URL%/}/hello" | tee -a "$OUT"
}

request "1. No token: expect 401"

read -rsp "Password for $EMAIL: " PASSWORD
echo

TOKEN="$(aws cognito-idp admin-initiate-auth \
  --user-pool-id "$POOL_ID" \
  --client-id "$CLIENT_ID" \
  --auth-flow ADMIN_USER_PASSWORD_AUTH \
  --auth-parameters USERNAME="$EMAIL",PASSWORD="$PASSWORD" \
  --query 'AuthenticationResult.AccessToken' \
  --output text)"
unset PASSWORD

request "2. Valid access token for $EMAIL: expect 200" -H "Authorization: Bearer $TOKEN"

# Flip one character in the payload part (the middle of the token): the signature no longer matches
readonly MID=$((${#TOKEN} / 2))
if [[ "${TOKEN:$MID:1}" == "A" ]]; then swap="B"; else swap="A"; fi
TAMPERED="${TOKEN:0:$MID}${swap}${TOKEN:$((MID + 1))}"

request "3. Tampered token: expect 401" -H "Authorization: Bearer $TAMPERED"

log ""
log "Evidence written to $OUT"
