############################################
# S3 buckets (raw, iceberg)
############################################

resource "random_id" "bn" {
  byte_length = 3
}

locals {
  raw_bucket_name     = coalesce(var.s3_raw_bucket_name, "${local.name_prefix}-raw-${random_id.bn.hex}")
  iceberg_bucket_name = coalesce(var.s3_iceberg_bucket_name, "${local.name_prefix}-iceberg-${random_id.bn.hex}")
}

resource "aws_s3_bucket" "raw" {
  bucket = local.raw_bucket_name
  tags   = merge(local.tags, { Purpose = "raw-readonly" })
}

resource "aws_s3_bucket" "iceberg" {
  bucket = local.iceberg_bucket_name
  tags   = merge(local.tags, { Purpose = "iceberg-warehouse" })
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "iceberg" {
  bucket = aws_s3_bucket.iceberg.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "iceberg" {
  bucket = aws_s3_bucket.iceberg.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket = aws_s3_bucket.raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "iceberg" {
  bucket = aws_s3_bucket.iceberg.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "raw_tls" {
  bucket = aws_s3_bucket.raw.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "DenyInsecureTransport",
      Effect    = "Deny",
      Principal = "*",
      Action    = "s3:*",
      Resource  = [aws_s3_bucket.raw.arn, "${aws_s3_bucket.raw.arn}/*"],
      Condition = { Bool = { "aws:SecureTransport" = false } }
    }]
  })
}

resource "aws_s3_bucket_policy" "iceberg_tls" {
  bucket = aws_s3_bucket.iceberg.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "DenyInsecureTransport",
      Effect    = "Deny",
      Principal = "*",
      Action    = "s3:*",
      Resource  = [aws_s3_bucket.iceberg.arn, "${aws_s3_bucket.iceberg.arn}/*"],
      Condition = { Bool = { "aws:SecureTransport" = false } }
    }]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "iceberg" {
  bucket = aws_s3_bucket.iceberg.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
