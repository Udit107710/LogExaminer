############################################
# RDS for Hive Metastore
############################################

resource "random_password" "db_password" {
  length  = 24
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS SG for Hive Metastore"
  vpc_id      = module.vpc.vpc_id
  tags        = local.tags
}

resource "aws_security_group_rule" "rds_inbound_mysql_from_nodes" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = module.eks.node_security_group_id
  security_group_id        = aws_security_group.rds.id
}

resource "aws_security_group_rule" "rds_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-rds-subnets"
  subnet_ids = var.multi_az ? module.vpc.private_subnets : [module.vpc.private_subnets[0], module.vpc.private_subnets[1]]
  tags       = local.tags
}

resource "aws_db_instance" "hive" {
  identifier                 = "${local.name_prefix}-hive-metastore"
  engine                     = "mysql"
  engine_version             = var.db_engine_version
  instance_class             = var.db_instance_class
  db_name                    = var.db_name
  username                   = var.db_username
  password                   = random_password.db_password.result
  allocated_storage          = var.db_allocated_storage
  max_allocated_storage      = 100
  storage_encrypted          = true
  skip_final_snapshot        = true
  backup_retention_period    = 7
  deletion_protection        = false
  db_subnet_group_name       = aws_db_subnet_group.this.name
  vpc_security_group_ids     = [aws_security_group.rds.id]
  publicly_accessible        = false
  auto_minor_version_upgrade = true
  multi_az                   = var.multi_az
  availability_zone          = var.multi_az ? null : var.preferred_az
  # Allow connections from all nodes in VPC private subnets
  parameter_group_name       = aws_db_parameter_group.hive.name
  tags                       = local.tags
}

# Custom parameter group to configure MySQL for Hive access
resource "aws_db_parameter_group" "hive" {
  name   = "${local.name_prefix}-hive-pg"
  family = "mysql8.0"
  
  # Enable general logging for debugging
  parameter {
    name  = "general_log"
    value = "1"
  }
  
  parameter {
    name  = "slow_query_log"
    value = "1"
  }
  
  parameter {
    name  = "long_query_time"
    value = "1"
  }
  
  # Set SQL mode for Hive compatibility
  parameter {
    name  = "sql_mode"
    value = "STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION"
  }
  
  # Set default character set
  parameter {
    name  = "character_set_server"
    value = "latin1"
  }
  
  parameter {
    name  = "collation_server"
    value = "latin1_bin"
  }
  
  tags = local.tags
}
