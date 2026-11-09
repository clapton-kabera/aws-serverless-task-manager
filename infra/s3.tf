#----------------------------------------------------------------------------------------------------
# s3.tf
# author: Kabera Clapton
#
# description: Private bucket for task attachments. Nothing here is public: browsers upload and
#              download only through short-lived presigned URLs created by the Lambdas.
#----------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "attachments" {
  # Bucket names are global across all AWS accounts; the account ID makes collisions practically impossible.
  bucket = "${local.name_prefix}-attachments-${data.aws_caller_identity.current.account_id}"

  # false: `terraform destroy` refuses to delete a bucket that still has files, so attachments are
  # never wiped by accident. The teardown script empties it explicitly first.
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "attachments" {
  bucket                  = aws_s3_bucket.attachments.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs disabled: the bucket owner owns every object and access is controlled only by IAM/policies.
resource "aws_s3_bucket_ownership_controls" "attachments" {
  bucket = aws_s3_bucket.attachments.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "attachments" {
  bucket = aws_s3_bucket.attachments.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Refuse any request that is not over HTTPS.
data "aws_iam_policy_document" "attachments_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.attachments.arn, "${aws_s3_bucket.attachments.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "attachments" {
  bucket = aws_s3_bucket.attachments.id
  policy = data.aws_iam_policy_document.attachments_tls_only.json

  # The public access block must exist first, or AWS may evaluate the policy before it applies.
  depends_on = [aws_s3_bucket_public_access_block.attachments]
}

/*
  CORS: the browser uploads (POST) and downloads (GET) directly from the bucket, from the front end's
  origin. Without this, the upload works with curl but fails in the browser.
*/
resource "aws_s3_bucket_cors_configuration" "attachments" {
  bucket = aws_s3_bucket.attachments.id

  cors_rule {
    allowed_methods = ["POST", "GET"]
    allowed_origins = local.frontend_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}
