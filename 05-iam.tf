############################################
# Secrets Manager + IAM Roles for IRSA
############################################

resource "aws_secretsmanager_secret" "hive" {
  name                    = "${local.name_prefix}/hive-metastore"
  description             = "HMS MySQL credentials and connection info"
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "hive" {
  secret_id = aws_secretsmanager_secret.hive.id
  secret_string = jsonencode({
    username = var.db_username,
    password = random_password.db_password.result,
    dbname   = var.db_name,
    host     = aws_db_instance.hive.address,
    port     = 3306,
    jdbc_url = "jdbc:mysql://${aws_db_instance.hive.address}:3306/${var.db_name}?useSSL=true&requireSSL=true&useUnicode=true&characterEncoding=UTF-8"
  })
  depends_on = [aws_db_instance.hive]
}

############################################
# External Secrets IRSA Role
############################################
data "aws_iam_policy_document" "eso_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.eso_namespace}:external-secrets"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${local.name_prefix}-eso-irsa"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "eso_secrets" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds"
    ]
    resources = [aws_secretsmanager_secret.hive.arn]
  }
}

resource "aws_iam_policy" "eso_read" {
  name   = "${local.name_prefix}-eso-secrets-read"
  policy = data.aws_iam_policy_document.eso_secrets.json
  tags   = local.tags
}

resource "aws_iam_role_policy_attachment" "eso_attach" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.eso_read.arn
}

############################################
# Spark Apps IRSA Role
############################################
locals {
  raw_object_arns     = [for p in var.raw_ro_prefixes : "${aws_s3_bucket.raw.arn}/${p}"]
  raw_rw_object_arns  = [for p in var.raw_rw_prefixes : "${aws_s3_bucket.raw.arn}/${p}"]
  iceberg_object_arns = [for p in var.iceberg_rw_prefixes : "${aws_s3_bucket.iceberg.arn}/${p}"]
}

data "aws_iam_policy_document" "spark_apps_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = [
        "system:serviceaccount:${var.spark_namespace}:spark-apps",
        "system:serviceaccount:${var.hive_namespace}:hive-metastore"
      ]
    }
  }
}

data "aws_iam_policy_document" "spark_s3" {
  statement {
    sid       = "RawListRO"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.raw.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = var.raw_ro_prefixes
    }
  }

  statement {
    sid       = "RawRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = local.raw_object_arns
  }

  # Spark Event Logs - List permission
  statement {
    sid       = "RawListRW"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.raw.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = var.raw_rw_prefixes
    }
  }

  # Spark Event Logs - Read/Write permission
  statement {
    sid       = "RawReadWrite"
    effect    = "Allow"
    actions   = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
      "s3:GetObjectVersion"
    ]
    resources = local.raw_rw_object_arns
  }

  # Iceberg bucket operations - allow full bucket access for Hive Metastore
  statement {
    sid       = "IcebergBucketOps"
    effect    = "Allow"
    actions   = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [aws_s3_bucket.iceberg.arn]
  }

  statement {
    sid       = "IceRW"
    effect    = "Allow"
    actions   = [
      "s3:GetObject",
      "s3:PutObject", 
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
      "s3:GetObjectVersion"
    ]
    resources = ["${aws_s3_bucket.iceberg.arn}/*"]
  }
}

resource "aws_iam_role" "spark_apps" {
  name               = "${local.name_prefix}-spark-apps-irsa"
  assume_role_policy = data.aws_iam_policy_document.spark_apps_assume.json
  tags               = local.tags
}

resource "aws_iam_policy" "spark_s3_access" {
  name   = "${local.name_prefix}-spark-s3-prefix"
  policy = data.aws_iam_policy_document.spark_s3.json
}

resource "aws_iam_role_policy_attachment" "spark_attach" {
  role       = aws_iam_role.spark_apps.name
  policy_arn = aws_iam_policy.spark_s3_access.arn
}

############################################
# Cluster Autoscaler IRSA Role
############################################
data "aws_iam_policy_document" "ca_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${local.name_prefix}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.ca_assume.json
  tags               = local.tags
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name = "${local.name_prefix}-ca"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "ec2:DescribeLaunchTemplateVersions",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "eks:DescribeNodegroup"
      ],
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ca_attach" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

############################################
# ClickHouse IRSA Role
############################################
data "aws_iam_policy_document" "clickhouse_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.clickhouse_namespace}:clickhouse"]
    }
  }
}

data "aws_iam_policy_document" "clickhouse_s3" {
  statement {
    sid       = "RawList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.raw.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = var.raw_ro_prefixes
    }
  }

  statement {
    sid       = "RawRO"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [for p in var.raw_ro_prefixes : "${aws_s3_bucket.raw.arn}/${p}"]
  }

  # Allow ClickHouse full access to the entire Iceberg bucket
  statement {
    sid       = "IcebergFullAccess"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.iceberg.arn]
  }

  statement {
    sid       = "IcebergObjectAccess"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.iceberg.arn}/*"]
  }
}

resource "aws_iam_role" "clickhouse" {
  name               = "${local.name_prefix}-clickhouse-irsa"
  assume_role_policy = data.aws_iam_policy_document.clickhouse_assume.json
  tags               = local.tags
}

resource "aws_iam_policy" "clickhouse_s3_access" {
  name   = "${local.name_prefix}-clickhouse-s3-access"
  policy = data.aws_iam_policy_document.clickhouse_s3.json
}

resource "aws_iam_role_policy_attachment" "clickhouse_attach" {
  role       = aws_iam_role.clickhouse.name
  policy_arn = aws_iam_policy.clickhouse_s3_access.arn
}
