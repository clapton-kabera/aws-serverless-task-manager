#!/usr/bin/env bash

#----------------------------------------------------------------------------------------------------
# admin_setup.sh
# author: Kabera Clapton
#
# description: A script that creates an admin user in cognito
#----------------------------------------------------------------------------------------------------

# if an error happens, the whole script should fail without cascading failure
set -euo pipefail

readonly USER_POOL_ID=$(terraform -chdir=infra output -raw user_pool_id)
readonly USERNAME="admin@admin.test"
readonly GROUP_NAME="admin"

if aws cognito-idp admin-get-user --user-pool-id "$USER_POOL_ID" --username "$USERNAME" 2>/dev/null; then
    echo "admin user already exists already exists."
    exit 1
fi

read -rsp "Password for $USERNAME: " PASSWORD; echo

# create the admin user
echo "Creating the admin user..."
aws cognito-idp admin-create-user \
  --user-pool-id "$USER_POOL_ID" \
  --message-action "SUPPRESS" \
  --username "$USERNAME"

# set a permanent password for the admin
aws cognito-idp admin-set-user-password \
  --user-pool-id "$USER_POOL_ID" \
  --username "$USERNAME" \
  --password "$PASSWORD" \
  --permanent true

# add the admin user to to the admin group
aws cognito-idp admin-add-user-to-group \
  --user-pool-id "$USER_POOL_ID" \
  --username "$USERNAME"
  --group-name "$GROUP_NAME"

echo "Done..."
