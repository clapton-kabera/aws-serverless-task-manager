#!/usr/bin/env bash

#----------------------------------------------------------------------------------------------------
# admin_setup.sh
# author: Kabera Clapton
#
# description: A script that creates an s3 bucket for remote backend
#----------------------------------------------------------------------------------------------------

# if an error happens, the whole script should fail without cascading failure
set -euo pipefail

readonly BUCKET_NAME="sandbox-remote-backend723354237"
readonly REGION="eu-west-1"

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "S3 bucket '$BUCKET_NAME' already exists."
    exit 1
fi

# create the bucket. Since the region is not us-east-1, we have to add options for our specific region
echo "Creating the bucket..."
aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"

# enable versioning on the s3 bucket in question
echo "Enabling versioning..."
aws s3api put-bucket-versioning --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

# block public access to the s3 bucket
echo "Blocking public access..."
aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"



echo "Done..."
