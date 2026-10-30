# Scratch bucket for Ansible's aws_ssm connection plugin. Files only pass
# through here on their way to an instance, so objects expire after a day.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "ssm_transfer" {
  # Scratch space: objects are short-lived copies of files already in the repo
  # or on the controller, and expire after a day.
  #checkov:skip=CKV_AWS_18:Access logs for a scratch bucket would outlive the data they describe.
  #checkov:skip=CKV_AWS_21:Versioning would keep transferred files around after they expire.
  #checkov:skip=CKV_AWS_144:Cross-region replication of transient transfers adds cost and copies of secrets.
  #checkov:skip=CKV_AWS_145:SSE-S3 encrypts at rest; the aws_ssm plugin needs extra setup for SSE-KMS.
  #checkov:skip=CKV2_AWS_62:Nothing consumes events from this bucket.
  bucket        = "${var.name_prefix}-ssm-${data.aws_caller_identity.current.account_id}-${var.region}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id

  rule {
    id     = "expire-transfers"
    status = "Enabled"

    filter {}

    expiration {
      days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Refuse anything that isn't TLS.
data "aws_iam_policy_document" "ssm_transfer_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.ssm_transfer.arn,
      "${aws_s3_bucket.ssm_transfer.arn}/*",
    ]

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

resource "aws_s3_bucket_policy" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id
  policy = data.aws_iam_policy_document.ssm_transfer_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.ssm_transfer]
}
