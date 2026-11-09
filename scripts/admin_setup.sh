#!/usr/bin/env bash

#----------------------------------------------------------------------------------------------------
# admin_setup.sh
# author: Kabera Clapton
#
# description: Idempotently creates a Cognito user (email sign-in, verified email, permanent
#              password), adds them to the admin or member group, and subscribes their email to the
#              task notification topic with a filter policy so they only get THEIR notifications.
#              Safe to re-run: an existing user is not recreated, but the password and group are
#              (re)applied, so a half-finished earlier run can be completed.
#              The person must click the confirmation link SNS emails them before mail arrives.
#
# usage:       ./scripts/admin_setup.sh <email> <admin|member>
#----------------------------------------------------------------------------------------------------

# -e: exit when a command fails, -u: unset variables are errors,
# -o pipefail: a pipeline fails if any command in it fails
set -euo pipefail

export AWS_REGION="${AWS_REGION:-eu-west-1}"

usage() {
  echo "Usage: $0 <email> <admin|member>" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage
readonly EMAIL="$1"
readonly GROUP_NAME="$2"
[[ "$GROUP_NAME" == "admin" || "$GROUP_NAME" == "member" ]] || usage

# Resolve paths from the script's own location, so it works from any working directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Assign first, then mark readonly: "readonly X=$(cmd)" would hide a failure of cmd from set -e
USER_POOL_ID="$(terraform -chdir="$SCRIPT_DIR/../infra" output -raw user_pool_id)"
readonly USER_POOL_ID
TOPIC_ARN="$(terraform -chdir="$SCRIPT_DIR/../infra" output -raw topic_arn)"
readonly TOPIC_ARN
if [[ -z "$USER_POOL_ID" || -z "$TOPIC_ARN" ]]; then
  echo "Could not read user_pool_id / topic_arn from the Terraform outputs" >&2
  exit 1
fi

# Capture only stderr (2>&1 first, then discard stdout), so we can tell
# "user not found" apart from real errors like expired credentials
if err="$(aws cognito-idp admin-get-user \
  --user-pool-id "$USER_POOL_ID" \
  --username "$EMAIL" 2>&1 >/dev/null)"; then
  echo "User $EMAIL already exists, skipping creation."
elif [[ "$err" == *UserNotFoundException* ]]; then
  echo "Creating user $EMAIL..."
  aws cognito-idp admin-create-user \
    --user-pool-id "$USER_POOL_ID" \
    --username "$EMAIL" \
    --user-attributes Name=email,Value="$EMAIL" Name=email_verified,Value=true \
    --message-action SUPPRESS >/dev/null
else
  echo "Could not check whether $EMAIL exists:" >&2
  echo "$err" >&2
  exit 1
fi

# Prompt without echoing, so the password never appears in shell history.
# (It is still briefly visible in the process list as an aws CLI argument; accepted for a lab.)
read -rsp "Password for $EMAIL: " PASSWORD
echo
if [[ -z "$PASSWORD" ]]; then
  echo "Password cannot be empty" >&2
  exit 1
fi

echo "Setting permanent password..."
aws cognito-idp admin-set-user-password \
  --user-pool-id "$USER_POOL_ID" \
  --username "$EMAIL" \
  --password "$PASSWORD" \
  --permanent

echo "Adding $EMAIL to group '$GROUP_NAME'..."
aws cognito-idp admin-add-user-to-group \
  --user-pool-id "$USER_POOL_ID" \
  --username "$EMAIL" \
  --group-name "$GROUP_NAME"

# ---- notifications: one email subscription per person, filtered to what they should receive ----
USER_SUB="$(aws cognito-idp admin-get-user \
  --user-pool-id "$USER_POOL_ID" \
  --username "$EMAIL" \
  --query "UserAttributes[?Name=='sub'].Value | [0]" \
  --output text)"
readonly USER_SUB

if [[ "$GROUP_NAME" == "admin" ]]; then
  FILTER_POLICY='{"audience": ["admin"]}'
else
  FILTER_POLICY="{\"assigneeId\": [\"$USER_SUB\"]}"
fi
readonly FILTER_POLICY

EXISTING="$(aws sns list-subscriptions-by-topic \
  --topic-arn "$TOPIC_ARN" \
  --query "length(Subscriptions[?Endpoint=='$EMAIL'])" \
  --output text)"

if [[ "$EXISTING" != "0" ]]; then
  echo "$EMAIL is already subscribed to notifications (or has a pending confirmation)."
else
  echo "Subscribing $EMAIL to notifications with filter policy $FILTER_POLICY..."
  # --attributes takes a JSON map whose FilterPolicy value is itself a JSON string;
  # python builds it so the nested quoting is always correct.
  ATTRIBUTES="$(python3 -c 'import json,sys; print(json.dumps({"FilterPolicy": sys.argv[1]}))' "$FILTER_POLICY")"
  aws sns subscribe \
    --topic-arn "$TOPIC_ARN" \
    --protocol email \
    --notification-endpoint "$EMAIL" \
    --attributes "$ATTRIBUTES" >/dev/null
  echo "ACTION NEEDED: $EMAIL must click the confirmation link in the email from AWS Notifications."
fi

echo "Done: $EMAIL is ready and in group '$GROUP_NAME'."
