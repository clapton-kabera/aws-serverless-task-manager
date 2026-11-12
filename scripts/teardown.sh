#!/usr/bin/env bash

#----------------------------------------------------------------------------------------------------
# teardown.sh
# author: Kabera Clapton
#
# description: Deletes everything this project created, after an explicit confirmation:
#              empties the attachments bucket (Terraform refuses to delete it while it holds files,
#              because force_destroy = false), then runs `terraform destroy`.
#              The Terraform STATE bucket is deliberately kept; see the README's Cleanup section.
#              Output goes to docs/evidence/09-teardown.txt.
#
# usage:       ./scripts/teardown.sh
#----------------------------------------------------------------------------------------------------

set -euo pipefail

export AWS_REGION="${AWS_REGION:-eu-west-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly INFRA_DIR="$SCRIPT_DIR/../infra"
readonly EVIDENCE_DIR="$SCRIPT_DIR/../docs/evidence"
mkdir -p "$EVIDENCE_DIR"
readonly OUT="$EVIDENCE_DIR/09-teardown.txt"

log() { echo "$*" | tee -a "$OUT"; }

ATTACHMENTS_BUCKET="$(terraform -chdir="$INFRA_DIR" output -raw attachments_bucket)"
readonly ATTACHMENTS_BUCKET
FRONTEND_URL="$(terraform -chdir="$INFRA_DIR" output -raw frontend_url)"
readonly FRONTEND_URL

echo "This permanently deletes the task manager: all users, tasks, attachments and the live site"
echo "($FRONTEND_URL)."
read -rp "Type 'destroy' to continue: " ANSWER
if [[ "$ANSWER" != "destroy" ]]; then
  echo "Cancelled. Nothing was deleted."
  exit 1
fi

: >"$OUT"
log "Teardown started $(date -u +%Y-%m-%dT%H:%M:%SZ)"

log ""
log "=== Emptying s3://$ATTACHMENTS_BUCKET"
aws s3 rm "s3://$ATTACHMENTS_BUCKET" --recursive --only-show-errors
log "remaining objects: $(aws s3 ls "s3://$ATTACHMENTS_BUCKET" --recursive | wc -l | tr -d ' ')"

log ""
log "=== terraform destroy (CloudFront takes several minutes to disable and delete)"
terraform -chdir="$INFRA_DIR" destroy -auto-approve -input=false 2>&1 | tail -n 3 | tee -a "$OUT"

log ""
log "=== What Terraform still tracks (expect nothing)"
REMAINING="$(terraform -chdir="$INFRA_DIR" state list 2>/dev/null | wc -l | tr -d ' ')"
log "resources in state: $REMAINING"

log ""
log "Done. The state bucket is kept on purpose. To remove it too, see the README (Cleanup)."
