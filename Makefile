SHELL := /usr/bin/env bash
AWS_REGION ?= us-east-1
PROJECT ?= data-platform

export AWS_REGION PROJECT

.PHONY: init plan apply destroy kubeconfig hms-port build-images build-hive build-spark-ingest build-spark-aggregate ecr-login ecr-list help

init:
	terraform -chdir=./ init

plan:
	terraform -chdir=./ plan -out "tfplan"

apply:
	terraform -chdir=./ apply -auto-approve "tfplan"

destroy:
	terraform -chdir=./ destroy -auto-approve

kubeconfig:
	aws eks update-kubeconfig --region $(AWS_REGION) --name $(PROJECT)-eks

hms-port:
	kubectl -n hive port-forward svc/hive-metastore 9083:9083

####################
# Docker Image Management
####################

# Build and push all custom Docker images to ECR
build-images:
	@echo "🐳 Building and pushing all custom Docker images..."
	./scripts/build-and-push-images.sh

# Build and push only Hive Metastore image
build-hive:
	@echo "🐳 Building and pushing Hive Metastore image..."
	./scripts/build-and-push-images.sh --image hive-metastore

# Build and push only Spark ingestion image
build-spark-ingest:
	@echo "🐳 Building and pushing Spark ingestion image..."
	./scripts/build-and-push-images.sh --image spark-ingest

# Build and push only Spark aggregation image
build-spark-aggregate:
	@echo "🐳 Building and pushing Spark aggregation image..."
	./scripts/build-and-push-images.sh --image spark-aggregate

# Dry run - show what would be built without actually building
build-images-dry:
	@echo "🔍 Dry run - showing what images would be built..."
	./scripts/build-and-push-images.sh --dry-run

####################
# ECR Management
####################

# Login to ECR
ecr-login:
	@echo "🔐 Logging into AWS ECR..."
	./scripts/ecr-manager.sh login

# List all ECR repositories
ecr-list:
	@echo "📦 Listing ECR repositories..."
	./scripts/ecr-manager.sh list

# Show ECR images in a specific repository (usage: make ecr-images REPO=data-platform/hive-metastore)
ecr-images:
	@if [ -z "$(REPO)" ]; then \
		echo "❌ Please specify REPO=repository-name"; \
		echo "Example: make ecr-images REPO=data-platform/hive-metastore"; \
	else \
		echo "🐳 Listing images in $(REPO)..."; \
		./scripts/ecr-manager.sh images $(REPO); \
	fi

####################
# Help
####################

# Show available commands
help:
	@echo "LogExaminer - Available Make Commands"
	@echo "===================================="
	@echo ""
	@echo "🏗️  Infrastructure:"
	@echo "  init              Initialize Terraform workspace"
	@echo "  plan              Plan infrastructure changes"
	@echo "  apply             Apply changes to AWS"
	@echo "  destroy           Destroy all resources"
	@echo ""
	@echo "☸️   Kubernetes:"
	@echo "  kubeconfig        Configure kubectl for EKS cluster"
	@echo "  hms-port          Port-forward Hive Metastore (9083:9083)"
	@echo ""
	@echo "🐳 Docker Images:"
	@echo "  build-images      Build and push all custom Docker images"
	@echo "  build-hive        Build and push Hive Metastore image"
	@echo "  build-spark-ingest   Build and push Spark ingestion image"
	@echo "  build-spark-aggregate Build and push Spark aggregation image"
	@echo "  build-images-dry  Show what would be built (dry run)"
	@echo ""
	@echo "📦 ECR Management:"
	@echo "  ecr-login         Login to AWS ECR"
	@echo "  ecr-list          List all ECR repositories"
	@echo "  ecr-images REPO=name  List images in specific repository"
	@echo ""
	@echo "💡 Examples:"
	@echo "  make build-images                    # Build all custom images"
	@echo "  make ecr-images REPO=log-ingest-spark  # Show images in repository"
	@echo "  make build-images-dry               # Preview build operations"
	@echo ""
	@echo "📚 For more details, see: scripts/README.md"
