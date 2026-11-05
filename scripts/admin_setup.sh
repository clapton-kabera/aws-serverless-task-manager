#!/usr/bin/env bash

#----------------------------------------------------------------------------------------------------
# admin_setup.sh
# author: Kabera Clapton
#
# description: A script that creates an admin user in cognito
#----------------------------------------------------------------------------------------------------

# if an error happens, the whole script should fail without cascading failure
# -e: exit when a command fails, 
# -u: unset variables are errors,
# -o pipefail: a pipeline fails if any command in it fails
set -euo pipefail

export AWS_REGION="${AWS_REGION:-eu-west-1}"

usage() {
  echo "Usage: $0 <email> <admin|member>" >&2
  exit 2
}

# if the first condition is true then the condition after the || is never run
[[ $# -eq 2 ]] || usage

readonly EMAIL="$1"
readonly GROUP_NAME="$2"

# if the GROUP_NAME is not admin or member then print the usage message
[[ "$GROUP_NAME" == "admin" || "$GROUP_NAME" == "member" ]] || usage

# fetch the absolute path of this script to use it when getting output vars from tf
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

USER_POOL_ID=$(terraform -chdir="$SCRIPT_DIR"/../infra output -raw user_pool_id)
readonly USER_POOL_ID

if [[ -z "$USER_POOL_ID" ]]; then
  echo "Could not read user_pool_id from the Terraform outputs" >&2
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

read -rsp "Password for $EMAIL: " PASSWORD

echo

if [[ -z "$PASSWORD" ]]; then
  echo "Password cannot be empty" >&2
  exit 1
fi

# set a permanent password for the admin
echo "Setting the passwrd..."
aws cognito-idp admin-set-user-password \
  --user-pool-id "$USER_POOL_ID" \
  --username "$EMAIL" \
  --password "$PASSWORD" \
  --permanent

# add the admin user to to the admin group
echo "Adding user to group..."
aws cognito-idp admin-add-user-to-group \
  --user-pool-id "$USER_POOL_ID" \
  --username "$EMAIL" \
  --group-name "$GROUP_NAME"

echo "Done..."
