# A single S3 bucket with the settings a bucket should have before anything is
# put in it: a unique name, versioning, encryption, public access blocked, and a
# lifecycle rule so old versions do not accumulate forever.

# S3 bucket names are globally unique, so a fixed name in shared example code
# will collide. Four random bytes is enough to avoid that.
resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "demo" {
  bucket = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
}

# Keep every version of an object. Note that a delete then writes a delete
# marker rather than removing data, so this must be paired with the lifecycle
# rule below.
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Encryption at rest. SSE-S3 needs no key management; SSE-KMS would give a
# CloudTrail record of every decrypt, at extra cost.
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access at the bucket level. This overrides any ACL or bucket
# policy that would otherwise expose the contents.
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disable ACLs entirely. AWS now recommends this over the legacy ACL mechanism.
resource "aws_s3_bucket_ownership_controls" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Expire superseded versions and clean up abandoned multipart uploads. Both are
# invisible on the console and both cost money.
resource "aws_s3_bucket_lifecycle_configuration" "demo" {
  bucket     = aws_s3_bucket.demo.id
  depends_on = [aws_s3_bucket_versioning.demo]

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Refuse any request that is not over TLS.
resource "aws_s3_bucket_policy" "demo" {
  bucket     = aws_s3_bucket.demo.id
  depends_on = [aws_s3_bucket_public_access_block.demo]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.demo.arn,
          "${aws_s3_bucket.demo.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
