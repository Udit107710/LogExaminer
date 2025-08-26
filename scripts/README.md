# Docker Image Build and ECR Management Scripts

This directory contains scripts to build and manage Docker images for the LogExaminer data platform project.

## 📋 Overview

The project uses several custom Docker images that need to be built and pushed to AWS ECR:

1. **Hive Metastore** (`data-platform/hive-metastore:2.3.9-fixed`)
   - Custom Hive 2.3.9 metastore compatible with Spark 3.5.1
   - Built from `hive-metastore/Dockerfile`

2. **Spark Ingestion** (`log-ingest-spark:v14-spark351`)
   - Spark 3.5.1 with Iceberg and log ingestion capabilities
   - Built from `spark-ingest/Dockerfile`

3. **Spark Aggregation** (`spark-aggregate:v1`)
   - Spark 3.5.1 with log aggregation and analytics capabilities
   - Built from `spark-aggregate/Dockerfile`

## 🛠️ Scripts

### build-and-push-images.sh

Comprehensive script to build and push all custom Docker images to ECR.

#### Usage

```bash
# Build and push all images
./scripts/build-and-push-images.sh

# Build and push a specific image
./scripts/build-and-push-images.sh --image hive-metastore
./scripts/build-and-push-images.sh --image spark-ingest
./scripts/build-and-push-images.sh --image spark-aggregate

# Dry run (show what would be done)
./scripts/build-and-push-images.sh --dry-run

# Skip build (only push existing images)
./scripts/build-and-push-images.sh --skip-build

# Skip push (only build images)
./scripts/build-and-push-images.sh --skip-push

# Show help
./scripts/build-and-push-images.sh --help
```

#### Features

- ✅ **AWS Authentication Check**: Verifies AWS CLI credentials
- ✅ **ECR Login**: Automatically logs into ECR
- ✅ **Repository Creation**: Creates ECR repositories if they don't exist
- ✅ **Multi-platform Support**: Builds for linux/amd64 platform
- ✅ **Error Handling**: Comprehensive error checking and reporting
- ✅ **Progress Tracking**: Color-coded output with progress indicators
- ✅ **Dry Run Mode**: Preview operations without executing
- ✅ **Selective Building**: Build only specific images

### ecr-manager.sh

ECR repository management utility for listing, creating, and managing repositories.

#### Usage

```bash
# List all ECR repositories
./scripts/ecr-manager.sh list

# List images in a specific repository
./scripts/ecr-manager.sh images data-platform/hive-metastore

# Create a new ECR repository
./scripts/ecr-manager.sh create my-new-repo

# Delete an ECR repository (interactive)
./scripts/ecr-manager.sh delete my-old-repo

# Login to ECR
./scripts/ecr-manager.sh login

# Show help
./scripts/ecr-manager.sh help
```

#### Features

- ✅ **Repository Listing**: Show all repositories with image counts
- ✅ **Image Listing**: Show all tagged images in a repository
- ✅ **Repository Management**: Create and delete repositories
- ✅ **ECR Login**: Quick ECR authentication
- ✅ **Interactive Confirmation**: Safe deletion with user confirmation

## 🚀 Quick Start

1. **Prerequisites**
   ```bash
   # Ensure you have AWS CLI configured
   aws configure
   
   # Ensure Docker is running
   docker info
   
   # Make scripts executable (already done)
   chmod +x scripts/*.sh
   ```

2. **Build and Push All Images**
   ```bash
   # This will build and push all custom images
   ./scripts/build-and-push-images.sh
   ```

3. **Verify Images in ECR**
   ```bash
   # List all repositories
   ./scripts/ecr-manager.sh list
   
   # Check images in a specific repository
   ./scripts/ecr-manager.sh images data-platform/hive-metastore
   ```

## 📦 Image Details

### Hive Metastore Image
- **Base**: Custom Hive 2.3.9 with Hadoop 3.2.4
- **Architecture**: linux/amd64
- **Key Features**: Compatible with Spark 3.5.1, MySQL backend, S3A support
- **Build Context**: `hive-metastore/`

### Spark Ingestion Image  
- **Base**: Apache Spark 3.5.1 with Java 11
- **Architecture**: linux/amd64
- **Key Features**: Iceberg 1.6.1, S3A support, log ingestion scripts
- **Build Context**: `spark-ingest/`

### Spark Aggregation Image
- **Base**: Apache Spark 3.5.1 with Java 11  
- **Architecture**: linux/amd64
- **Key Features**: Iceberg 1.6.1, S3A support, analytics scripts
- **Build Context**: `spark-aggregate/`

## 🔧 Configuration

The scripts are configured for:
- **AWS Region**: us-east-1
- **AWS Account**: 503233514096
- **ECR Base URI**: 503233514096.dkr.ecr.us-east-1.amazonaws.com

To modify for a different environment, update the configuration variables at the top of each script:

```bash
AWS_REGION="your-region"
AWS_ACCOUNT_ID="your-account-id"
```

## 🔍 Troubleshooting

### Common Issues

1. **Docker not running**
   ```bash
   # Start Docker Desktop or Docker daemon
   # Then verify with:
   docker info
   ```

2. **AWS credentials not configured**
   ```bash
   # Configure AWS CLI
   aws configure
   
   # Or use environment variables
   export AWS_ACCESS_KEY_ID=your-key
   export AWS_SECRET_ACCESS_KEY=your-secret
   ```

3. **ECR permissions issues**
   ```bash
   # Ensure your AWS user/role has ECR permissions:
   # - ecr:GetAuthorizationToken
   # - ecr:BatchCheckLayerAvailability  
   # - ecr:GetDownloadUrlForLayer
   # - ecr:BatchGetImage
   # - ecr:InitiateLayerUpload
   # - ecr:UploadLayerPart
   # - ecr:CompleteLayerUpload
   # - ecr:PutImage
   ```

4. **Platform compatibility issues**
   ```bash
   # The scripts build for linux/amd64 by default
   # If you need different architectures, modify the platform parameter
   # in the build_and_push_image function calls
   ```

### Debug Mode

Enable debug output by adding `set -x` to the top of the scripts after `set -e`.

## 🔗 Integration with Terraform

After building and pushing images, update your Terraform configuration:

```hcl
# In terraform.tfvars or variables
hive_metastore_image = "503233514096.dkr.ecr.us-east-1.amazonaws.com/data-platform/hive-metastore:2.3.9-fixed"

# Spark job images are already configured in the Terraform files
# with the correct ECR URIs and tags
```

## 📝 Logs and Output

The scripts provide color-coded output:
- 🔵 **Blue**: Informational messages
- 🟡 **Yellow**: Warnings and in-progress operations  
- 🟢 **Green**: Success messages
- 🔴 **Red**: Error messages
- 🟣 **Purple**: Section headers
- 🔵 **Cyan**: Important URIs and references

## 🤝 Contributing

When adding new Docker images:

1. Create the Dockerfile in an appropriate directory
2. Add the image configuration to the `IMAGES` array in `build-and-push-images.sh`
3. Add the ECR repository to the Terraform configuration in `02-eks.tf`
4. Update this README with the new image details

## 📄 License

These scripts are part of the LogExaminer project and follow the same license terms.
