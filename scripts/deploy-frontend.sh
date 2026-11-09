#!/usr/bin/env bash

#----------------------------------------------------------------------------------------------------
# deploy-frontend.sh
# author: Kabera Clapton
#
# description: Builds the React front end with the values from `terraform output`, uploads it to the
#              private frontend bucket, refreshes CloudFront, and checks the live site responds with
#              HTTPS and security headers. Output goes to docs/evidence/08-frontend-deploy.txt.
#              Caching: hashed files in assets/ are cached for a year (their names change on every
#              build); index.html and other files must be re-checked on every visit.
#
# usage:       ./scripts/deploy-frontend.sh
#----------------------------------------------------------------------------------------------------

set -euo pipefail

export AWS_REGION="${AWS_REGION:-eu-west-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly INFRA_DIR="$SCRIPT_DIR/../infra"
readonly FRONTEND_DIR="$SCRIPT_DIR/../frontend"
readonly EVIDENCE_DIR="$SCRIPT_DIR/../docs/evidence"
mkdir -p "$EVIDENCE_DIR"
readonly OUT="$EVIDENCE_DIR/08-frontend-deploy.txt"
: >"$OUT"

log() { echo "$*" | tee -a "$OUT"; }
tf_output() { terraform -chdir="$INFRA_DIR" output -raw "$1"; }

BUCKET="$(tf_output frontend_bucket)"
readonly BUCKET
DISTRIBUTION_ID="$(tf_output cloudfront_distribution_id)"
readonly DISTRIBUTION_ID
FRONTEND_URL="$(tf_output frontend_url)"
readonly FRONTEND_URL

log "Front-end deploy $(date -u +%Y-%m-%dT%H:%M:%SZ) to s3://$BUCKET"

# Build-time configuration. None of these are secrets: they end up in the public JavaScript bundle.
cat >"$FRONTEND_DIR/.env.production.local" <<ENV
VITE_REGION=$AWS_REGION
VITE_API_URL=$(tf_output gateway_url)
VITE_USER_POOL_ID=$(tf_output user_pool_id)
VITE_USER_POOL_CLIENT_ID=$(tf_output user_pool_client_id)
ENV

(
  cd "$FRONTEND_DIR"
  npm ci --no-audit --no-fund # exact versions from package-lock.json
  npm run build
) 2>&1 | tee -a "$OUT"

log ""
log "=== Uploading"
# 1. Hashed assets first, so a new index.html never points at files that are not there yet.
aws s3 sync "$FRONTEND_DIR/dist/assets" "s3://$BUCKET/assets" \
  --cache-control "public, max-age=31536000, immutable" --only-show-errors
# 2. Everything else (index.html, favicon): always revalidated. --delete removes files from old
#    builds, except assets/ (excluded), which older cached pages may still reference.
aws s3 sync "$FRONTEND_DIR/dist" "s3://$BUCKET" --exclude "assets/*" --delete \
  --cache-control "no-cache" --only-show-errors
log "uploaded: $(aws s3 ls "s3://$BUCKET" --recursive | wc -l | tr -d ' ') objects"

log ""
log "=== Invalidating CloudFront's copy of index.html"
INVALIDATION_ID="$(aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
  --paths "/" "/index.html" --query 'Invalidation.Id' --output text)"
aws cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"
log "invalidation $INVALIDATION_ID completed"

log ""
log "=== Live site check: $FRONTEND_URL"
curl -sI "$FRONTEND_URL" | grep -iE '^(HTTP|content-type|strict-transport-security|x-content-type-options|x-frame-options|x-cache)' | tee -a "$OUT"

log ""
log "=== HTTP is redirected to HTTPS"
curl -sI "http://${FRONTEND_URL#https://}" | grep -iE '^(HTTP|location)' | tee -a "$OUT"

log ""
log "=== The bucket itself is not public (expect 403)"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' "https://$BUCKET.s3.$AWS_REGION.amazonaws.com/index.html" | tee -a "$OUT"

log ""
log "Live application: $FRONTEND_URL"
