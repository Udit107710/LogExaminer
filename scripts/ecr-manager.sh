#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="503233514096"
ECR_BASE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN} ECR Repository Management Script${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "${BLUE}ECR Region: ${AWS_REGION}${NC}"
echo -e "${BLUE}Account ID: ${AWS_ACCOUNT_ID}${NC}"
echo ""

# Function to print section headers
print_section() {
    echo -e "${PURPLE}----------------------------------------${NC}"
    echo -e "${PURPLE} $1${NC}"
    echo -e "${PURPLE}----------------------------------------${NC}"
}

# Function to check if AWS CLI is configured
check_aws_auth() {
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        echo -e "${RED}❌ AWS credentials not configured properly${NC}"
        echo -e "${YELLOW}💡 Please run: aws configure${NC}"
        exit 1
    fi
}

# Function to list ECR repositories
list_repositories() {
    print_section "📦 ECR Repositories"
    
    echo -e "${YELLOW}Fetching repositories...${NC}"
    
    if ! aws ecr describe-repositories --region ${AWS_REGION} > /dev/null 2>&1; then
        echo -e "${RED}❌ Failed to list repositories${NC}"
        return 1
    fi
    
    # Get repositories with image counts
    repos=$(aws ecr describe-repositories --region ${AWS_REGION} --query 'repositories[].repositoryName' --output text)
    
    if [ -z "$repos" ]; then
        echo -e "${YELLOW}ℹ️  No ECR repositories found${NC}"
        return 0
    fi
    
    echo -e "${GREEN}Found repositories:${NC}"
    echo ""
    
    for repo in $repos; do
        # Get image count
        image_count=$(aws ecr list-images --repository-name "$repo" --region ${AWS_REGION} --query 'length(imageIds)' --output text 2>/dev/null || echo "0")
        
        # Get repository URI
        repo_uri="${ECR_BASE_URI}/${repo}"
        
        echo -e "${BLUE}📦 ${repo}${NC}"
        echo -e "   ${CYAN}URI: ${repo_uri}${NC}"
        echo -e "   ${GREEN}Images: ${image_count}${NC}"
        echo ""
    done
}

# Function to list images in a specific repository
list_images() {
    local repo_name=$1
    
    if [ -z "$repo_name" ]; then
        echo -e "${RED}❌ Repository name required${NC}"
        return 1
    fi
    
    print_section "🐳 Images in ${repo_name}"
    
    if ! aws ecr describe-repositories --repository-names "$repo_name" --region ${AWS_REGION} > /dev/null 2>&1; then
        echo -e "${RED}❌ Repository '${repo_name}' not found${NC}"
        return 1
    fi
    
    images=$(aws ecr list-images --repository-name "$repo_name" --region ${AWS_REGION} --query 'imageIds[?imageTag!=null].[imageTag,imagePushedAt,imageDigest]' --output text 2>/dev/null)
    
    if [ -z "$images" ]; then
        echo -e "${YELLOW}ℹ️  No tagged images found in ${repo_name}${NC}"
        return 0
    fi
    
    echo -e "${GREEN}Tagged images:${NC}"
    echo ""
    
    while IFS=$'\t' read -r tag pushed_at digest; do
        if [ ! -z "$tag" ]; then
            echo -e "${BLUE}🏷️  ${tag}${NC}"
            echo -e "   ${CYAN}Pushed: ${pushed_at}${NC}"
            echo -e "   ${GREEN}Digest: ${digest:0:20}...${NC}"
            echo ""
        fi
    done <<< "$images"
}

# Function to create a repository
create_repository() {
    local repo_name=$1
    
    if [ -z "$repo_name" ]; then
        echo -e "${RED}❌ Repository name required${NC}"
        return 1
    fi
    
    print_section "🏗️  Creating Repository: ${repo_name}"
    
    if aws ecr describe-repositories --repository-names "$repo_name" --region ${AWS_REGION} > /dev/null 2>&1; then
        echo -e "${YELLOW}ℹ️  Repository '${repo_name}' already exists${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Creating repository...${NC}"
    
    aws ecr create-repository \
        --repository-name "$repo_name" \
        --region ${AWS_REGION} \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Repository created: ${repo_name}${NC}"
        echo -e "${CYAN}📍 URI: ${ECR_BASE_URI}/${repo_name}${NC}"
    else
        echo -e "${RED}❌ Failed to create repository: ${repo_name}${NC}"
        return 1
    fi
}

# Function to delete a repository
delete_repository() {
    local repo_name=$1
    local force=${2:-false}
    
    if [ -z "$repo_name" ]; then
        echo -e "${RED}❌ Repository name required${NC}"
        return 1
    fi
    
    print_section "🗑️  Deleting Repository: ${repo_name}"
    
    if ! aws ecr describe-repositories --repository-names "$repo_name" --region ${AWS_REGION} > /dev/null 2>&1; then
        echo -e "${YELLOW}ℹ️  Repository '${repo_name}' does not exist${NC}"
        return 0
    fi
    
    if [ "$force" != "true" ]; then
        echo -e "${YELLOW}⚠️  This will permanently delete the repository and all its images!${NC}"
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}ℹ️  Operation cancelled${NC}"
            return 0
        fi
    fi
    
    echo -e "${YELLOW}Deleting repository...${NC}"
    
    aws ecr delete-repository \
        --repository-name "$repo_name" \
        --region ${AWS_REGION} \
        --force
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Repository deleted: ${repo_name}${NC}"
    else
        echo -e "${RED}❌ Failed to delete repository: ${repo_name}${NC}"
        return 1
    fi
}

# Function to get ECR login command
get_login() {
    print_section "🔓 ECR Login Command"
    
    echo -e "${YELLOW}Getting ECR login token...${NC}"
    
    aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_BASE_URI}
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Successfully logged into ECR${NC}"
        echo -e "${CYAN}📍 You can now push/pull images from: ${ECR_BASE_URI}${NC}"
    else
        echo -e "${RED}❌ ECR login failed${NC}"
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  list                    List all ECR repositories"
    echo "  images <repo-name>      List images in a repository"
    echo "  create <repo-name>      Create a new ECR repository"
    echo "  delete <repo-name>      Delete an ECR repository (interactive)"
    echo "  login                   Login to ECR"
    echo "  help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 images data-platform/hive-metastore"
    echo "  $0 create my-app"
    echo "  $0 delete my-app"
    echo "  $0 login"
    echo ""
}

# Main execution
main() {
    check_aws_auth
    
    local command=$1
    
    case $command in
        list)
            list_repositories
            ;;
        images)
            list_images "$2"
            ;;
        create)
            create_repository "$2"
            ;;
        delete)
            delete_repository "$2" "$3"
            ;;
        login)
            get_login
            ;;
        help|--help|-h)
            show_usage
            ;;
        "")
            echo -e "${RED}❌ No command specified${NC}"
            echo ""
            show_usage
            exit 1
            ;;
        *)
            echo -e "${RED}❌ Unknown command: $command${NC}"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
