#!/usr/bin/env bash

#----------------------------------------------------------------------------------------------------
# clean_up.sh
# author: Kabera Clapton
#
# description: Cleans up all the resources created by the dynamo_s3_setup.sh
#----------------------------------------------------------------------------------------------------

# if an error happens, the whole script should fail without cascading failure
set -euo pipefail

readonly BUCKET_NAME="sandbox-remote-backend723354237"

# deletes every entry of one kind ("Versions" or "DeleteMarkers") from a versioned bucket,
# in batches of up to 1000 (the delete-objects limit)
delete_all_versions() 
{
    local bucket="$1"
    local field="$2"
    local batch
 
    while true; do
        batch=$(aws s3api list-object-versions --bucket "${bucket}" \
            --query "{Objects: ${field}[0:1000].{Key: Key, VersionId: VersionId}, Quiet: \`true\`}" \
            --output json)
 
        # Objects is null or empty once nothing of this kind is left
        if [ "$(echo "${batch}" | jq '.Objects | length')" -eq 0 ]; then
            break
        fi
 
        aws s3api delete-objects --bucket "${bucket}" --delete "${batch}" > /dev/null
    done
}

# empty the versioned bucket: "aws s3 rm" only adds delete markers on a versioned bucket,
# so every object version and every delete marker has to be removed explicitly
echo "Deleting all object versions in S3 bucket..."
delete_all_versions "${BUCKET_NAME}" "Versions"

echo "Deleting all delete markers in S3 bucket..."
delete_all_versions "${BUCKET_NAME}" "DeleteMarkers"

# delete the s3 bucket itself
echo "Deleting the S3 bucket..."
aws s3api delete-bucket --bucket "${BUCKET_NAME}"

echo "Done..."
