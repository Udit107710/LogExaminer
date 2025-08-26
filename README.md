# LogExaminer

A comprehensive AWS-based log analytics platform built with Terraform and Kubernetes, designed for scalable log ingestion, processing, and analytics using Apache Spark, Iceberg, and ClickHouse.

## 🏗️ Architecture Overview

LogExaminer is a production-ready log analytics platform that provisions:

- **Compute**: Amazon EKS cluster with managed node groups
- **Storage**: S3 buckets for raw logs and Iceberg data warehouse
- **Database**: RDS MySQL for Hive Metastore
- **Processing**: Apache Spark 3.5.1 with Iceberg 1.6.1 for log ingestion and aggregation
- **Analytics**: ClickHouse for high-performance log analytics
- **Container Registry**: ECR repositories for custom Spark and Hive images
- **Networking**: VPC with public/private subnets and VPC endpoints
- **Security**: IAM roles with IRSA (IAM Roles for Service Accounts)

### Key Components

#### Infrastructure Layer (Phase 1)
- **VPC & Networking**: Multi-AZ VPC with optional NAT gateway and VPC endpoints
- **EKS Cluster**: Kubernetes v1.33 cluster with two managed node groups:
  - Spot instances for Spark executors (cost-effective workloads)
  - On-demand instances for system components (reliability)
- **S3 Storage**: Separate buckets for raw log ingestion and Iceberg warehouse
- **RDS MySQL**: Managed database for Hive Metastore (compatible with Spark 3.5.1)
- **ECR Repositories**: Private container registries for custom images

#### Application Layer (Phase 2 - Deployed)
- **Apache Spark 3.5.1**: Distributed log processing with Iceberg integration
- **Hive Metastore 2.3.9**: Metadata catalog compatible with Spark 3.5.1
- **Spark Operator**: Kubernetes-native Spark job management
- **ClickHouse 23.8**: High-performance analytics database with S3 integration
- **External Secrets Operator**: AWS Secrets Manager integration

#### Log Processing Pipeline
- **Log Ingestion**: Spark jobs that read raw logs (JSON/Apache format) from S3
- **Data Transformation**: Parse and structure logs into Iceberg tables
- **Log Aggregation**: Spark jobs for analytics and reporting
- **Real-time Analytics**: ClickHouse for interactive log analysis

## 📋 Prerequisites

### Required Tools
- **Terraform**: >= 1.13.0
- **AWS CLI**: For authentication and resource management
- **kubectl**: Kubernetes command-line tool
- **Docker**: For building and pushing custom container images
- **jq**: JSON processor (required for image mirroring scripts)

### AWS Environment Setup
Ensure AWS credentials are configured in your environment:

```bash
# Option 1: AWS Profile
export AWS_PROFILE=your-profile-name

# Option 2: Environment Variables
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_REGION=us-east-1  # Default region
```

### Environment Variables
- `AWS_REGION`: AWS region (default: us-east-1)
- `PROJECT`: Project name (default: data-platform)

## 🚀 Quick Start Deployment

### 1. Initialize Terraform
```bash
make init
```

### 2. Plan Infrastructure Changes
```bash
make plan
```

### 3. Deploy Infrastructure (Phase 1)
```bash
make apply
```

### 4. Configure kubectl for EKS
```bash
make kubeconfig
```

### 5. Build and Push Custom Images
```bash
# Build and push all custom Docker images to ECR
make build-images

# Or build individual images as needed
make build-hive              # Hive Metastore
make build-spark-ingest      # Spark ingestion
make build-spark-aggregate   # Spark aggregation
```

### 6. Deploy Kubernetes Resources (Phase 2)
Kubernetes resources are already included in `06-kubernetes.tf`. After Phase 1, simply run:

```bash
make plan
make apply
```


## 🛠️ Available Commands

### Infrastructure Management
```bash
# Initialize Terraform workspace
make init

# Plan infrastructure changes
make plan

# Apply changes to AWS
make apply

# Destroy all resources
make destroy
```

### Kubernetes Operations
```bash
# Configure local kubeconfig for EKS cluster
make kubeconfig

# Port-forward Hive Metastore (Thrift:9083)
make hms-port
```

### Container Image Management
```bash
# Build and push all custom images (recommended)
make build-images

# Or build individual images
make build-hive              # Hive Metastore 2.3.9 (Spark 3.5.1 compatible)
make build-spark-ingest      # Spark ingestion with Iceberg 1.6.1
make build-spark-aggregate   # Spark aggregation for analytics

# ECR operations
make ecr-login              # Login to AWS ECR
make ecr-list               # List all ECR repositories
make ecr-images REPO=log-ingest-spark  # List images in specific repo

# Preview build operations (dry run)
make build-images-dry
```

## ⚙️ Configuration

### Key Terraform Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `project_name` | data-platform | Project identifier for resource naming |
| `aws_region` | us-east-1 | AWS deployment region |
| `eks_version` | 1.33 | EKS cluster version |
| `multi_az` | false | Enable multi-AZ deployment |
| `enable_nat_gateway` | false | Enable NAT gateway for private subnets |
| `create_vpc_endpoints` | true | Create VPC endpoints to reduce NAT costs |
| `node_size` | - | Instance type for executor nodes |
| `sys_node_size` | - | Instance type for system nodes |

### Application Configuration
- `spark_namespace`: Kubernetes namespace for Spark applications (default: "spark")
- `hive_namespace`: Kubernetes namespace for Hive Metastore (default: "hive")
- `clickhouse_namespace`: Kubernetes namespace for ClickHouse (default: "clickhouse")
- `deploy_spark_jobs`: Deploy production log ingestion/aggregation jobs
- `hive_metastore_image`: Custom Hive Metastore container image
- `hive_metastore_replicas`: Number of Hive Metastore replicas

### Storage Configuration
- `s3_raw_bucket_name`: S3 bucket for raw log ingestion
- `s3_iceberg_bucket_name`: S3 bucket for Iceberg warehouse
- Raw logs: Lifecycle transitions to IA after 30 days
- Iceberg data: Read-write access for Spark jobs and ClickHouse

### Database Configuration (Hive Metastore)
- `db_name`: Database name for Hive Metastore (default: "hive_metastore")
- `db_username`: Database username
- `db_instance_class`: RDS instance class
- `db_allocated_storage`: Storage size in GB

## 🔐 Security & IAM

### IRSA Roles
The platform creates several IAM roles for secure service-to-service authentication:

1. **External Secrets**: Manages Kubernetes secrets from AWS Secrets Manager
2. **Spark Applications**: S3 access for data processing workloads
3. **Cluster Autoscaler**: EKS node scaling permissions
4. **ClickHouse**: Read-only access to data buckets

### Network Security
- Private subnets for EKS nodes and RDS
- Security groups with least-privilege access
- VPC endpoints to minimize internet traffic
- Encrypted storage with AES-256

## 📊 Log Analytics Architecture

### Data Flow Pipeline
```
Log Files (JSON/Apache) → S3 Raw Bucket → Spark Ingestion → Iceberg Tables → ClickHouse Analytics
                                          ↓
                                    Hive Metastore
```

### Storage Layers
1. **Raw Log Layer**: JSON and Apache access logs stored in S3
2. **Curated Data Layer**: Structured logs in Iceberg format with partitioning
3. **Metadata Layer**: Hive Metastore for schema and catalog management
4. **Analytics Layer**: ClickHouse with direct S3 access for fast queries

### Log Processing Jobs

#### 1. Log Ingestion (`ingest-logs-spark351-prod`)
- **Purpose**: Parse and ingest raw log files into Iceberg tables
- **Input**: JSON logs and Apache access logs from S3
- **Output**: Structured Iceberg tables partitioned by date
- **Features**: 
  - Supports both JSON and Apache Common Log Format
  - Automatic schema inference and validation
  - Error handling for malformed log entries
  - Incremental processing

#### 2. Log Aggregation (`aggregate-logs-spark351-prod`)
- **Purpose**: Generate analytics and aggregated views
- **Input**: Iceberg log tables
- **Output**: Aggregated tables for dashboards and reporting
- **Features**:
  - Top-N analysis (errors, IPs, paths)
  - Time-based aggregations
  - Custom SQL-based transformations

### Sample Log Formats

#### JSON Application Logs
```json
{
  "timestamp": "2025-08-25T06:04:00.000Z",
  "level": "ERROR",
  "message": "Database connection failed",
  "logger": "com.webapp.DB",
  "thread": "db-pool-1",
  "source_file": "DatabaseManager.java",
  "line_number": 245,
  "exception_class": "SQLException",
  "exception_message": "Connection timeout after 30 seconds"
}
```

#### Apache Access Logs
```
192.168.1.100 - - [25/Aug/2025:06:04:00 +0000] "GET /api/users HTTP/1.1" 200 1234 "-" "Mozilla/5.0"
```

### ClickHouse Integration
```sql
-- Query Iceberg tables directly from ClickHouse
SELECT 
    level,
    COUNT(*) as log_count,
    COUNT(DISTINCT logger) as unique_loggers
FROM iceberg('s3://your-iceberg-bucket/warehouse/analytics/logs/*', 'AWS')
WHERE partition_date >= today() - 7
GROUP BY level
ORDER BY log_count DESC;
```

## 🐞 Troubleshooting

### Common Issues

#### ECR Authentication
```bash
# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com
```

#### EKS Access Issues
```bash
# Update kubeconfig
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Verify access
kubectl get nodes
```

#### Port Forwarding
```bash
# Manual ClickHouse port forward
kubectl port-forward -n clickhouse svc/clickhouse 8123:8123 9000:9000

# Manual Hive Metastore port forward
kubectl port-forward -n hive svc/hive-metastore 9083:9083
```

## 🗂️ Project Structure

```
.
├── 00-providers.tf      # Terraform providers and variables
├── 01-vpc.tf           # VPC and networking
├── 02-eks.tf           # EKS cluster and ECR repositories
├── 03-rds.tf           # RDS MySQL for Hive Metastore
├── 04-s3.tf            # S3 buckets for data storage
├── 05-iam.tf           # IAM roles and IRSA configuration
├── 06-kubernetes.tf    # Kubernetes/Helm resources with Spark jobs
├── 07-clickhouse.tf    # ClickHouse installation and configuration
├── 08-production-workloads.tf # Additional ECR repos and production configs
├── 99-outputs.tf       # Terraform outputs
├── Makefile           # Automation commands
├── WARP.md            # Project guidance for AI assistants
├── docs/
│   ├── architecture-diagram.md  # Mermaid architecture diagram
│   ├── architecture-diagram.mmd # Source diagram file
│   └── architecture-diagram.png # Rendered diagram
├── spark-ingest/       # Spark log ingestion jobs
│   ├── Dockerfile      # Custom Spark image with Iceberg support
│   ├── jobs/          # Python Spark jobs for log ingestion
│   │   ├── ingest_logs_to_iceberg.py
│   │   ├── simple_iceberg_ingest.py
│   │   └── create_schema.py
│   └── logs_ingestion_prod.py
├── spark-aggregate/    # Spark log aggregation jobs
│   ├── Dockerfile     # Custom Spark image for aggregation
│   └── jobs/
│       └── logs_aggregation_prod.py
├── hive-metastore/    # Custom Hive Metastore image
│   ├── Dockerfile     # Hive 2.3.9 with MySQL and S3 support
│   ├── conf/         # Hive configuration files
│   └── init-schema.sh # Database initialization script
├── mock_logs/         # Sample log data for testing
│   ├── app_logs_20250825.json
│   └── service_logs_20250825.json
└── scripts/           # Helper scripts
    ├── build-and-push-images.sh      # Build and push custom Docker images
    ├── ecr-manager.sh               # ECR repository management
    ├── README.md                    # Scripts documentation
    ├── mirror_to_ecr.sh             # ECR image mirroring
    ├── generate_tfvars_from_ecr.sh  # Generate tfvars from ECR
    └── ch_port_forward.sh           # ClickHouse port forwarding
```

## 📈 Scaling & Optimization

### Cost Optimization
- Spot instances for non-critical workloads
- VPC endpoints to reduce NAT gateway costs
- S3 lifecycle policies for data archival
- Optional NAT gateway (disabled by default)

### Performance Tuning
- Separate node groups for different workload types
- EBS CSI driver for persistent storage
- Multi-AZ deployment option for high availability
- Cluster autoscaler for dynamic scaling

## 🔍 Log Analytics Use Cases

### Real-time Monitoring
- **Error Detection**: Identify application errors and exceptions
- **Performance Monitoring**: Track response times and system metrics
- **Security Analysis**: Monitor access patterns and suspicious activity
- **Capacity Planning**: Analyze usage trends and resource consumption

### Batch Analytics
- **Daily Reports**: Generate daily summaries of application activity
- **Trend Analysis**: Identify patterns over time periods
- **User Behavior**: Analyze user interaction patterns
- **System Health**: Monitor system stability and performance metrics

### Sample Analytics Queries

#### Top Error Sources
```sql
SELECT 
    logger,
    COUNT(*) as error_count,
    COUNT(DISTINCT exception_class) as unique_exceptions
FROM iceberg.analytics.logs 
WHERE level = 'ERROR' 
  AND partition_date >= current_date - 7
GROUP BY logger 
ORDER BY error_count DESC 
LIMIT 10;
```

#### HTTP Traffic Analysis
```sql
SELECT 
    http_status,
    http_method,
    COUNT(*) as request_count,
    AVG(response_size) as avg_response_size
FROM iceberg.analytics.logs 
WHERE http_method IS NOT NULL
  AND partition_date = current_date
GROUP BY http_status, http_method
ORDER BY request_count DESC;
```

## 🚀 Getting Started with Sample Data

1. **Upload Sample Logs**:
   ```bash
   aws s3 cp mock_logs/ s3://your-raw-bucket/logs/ --recursive
   ```

2. **Trigger Log Ingestion**:
   ```bash
   kubectl create job --from=sparkapplication/ingest-logs-spark351-prod manual-ingest-$(date +%s) -n spark
   ```

3. **Run Analytics**:
   ```bash
   kubectl port-forward svc/clickhouse-external 8123:8123 -n clickhouse
   # Then connect to http://localhost:8123
   ```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `terraform plan`
5. Submit a pull request

## 📄 License

[Add your license information here]

## 🆘 Support

For issues and questions:
- Review the troubleshooting section above
- Check the `docs/architecture-diagram.md` for detailed architecture
- Consult Terraform and AWS documentation
- Open an issue in this repository

---

**Note**: This platform includes both infrastructure provisioning (Phase 1) and application deployment (Phase 2) in a single Terraform configuration. The system is production-ready with custom Docker images for Spark log processing and Hive Metastore integration.
