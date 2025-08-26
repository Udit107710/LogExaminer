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
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN} Docker Images Build and Push Script${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "${BLUE}Project Root: ${PROJECT_ROOT}${NC}"
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
    print_section "🔐 Checking AWS Authentication"
    
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        echo -e "${RED}❌ AWS credentials not configured properly${NC}"
        echo -e "${YELLOW}💡 Please run: aws configure${NC}"
        exit 1
    fi
    
    CALLER_IDENTITY=$(aws sts get-caller-identity)
    echo -e "${GREEN}✅ AWS Authentication OK${NC}"
    echo -e "${BLUE}Account: $(echo $CALLER_IDENTITY | jq -r '.Account')${NC}"
    echo -e "${BLUE}User/Role: $(echo $CALLER_IDENTITY | jq -r '.Arn')${NC}"
    echo ""
}

# Function to login to ECR
ecr_login() {
    print_section "🔓 ECR Login"
    
    echo "Logging into ECR..."
    aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_BASE_URI}
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ ECR Login successful${NC}"
    else
        echo -e "${RED}❌ ECR Login failed${NC}"
        exit 1
    fi
    echo ""
}

# Function to build and push an image
build_and_push_image() {
    local image_name=$1
    local dockerfile_path=$2
    local context_path=$3
    local tag=${4:-latest}
    local platform=${5:-linux/amd64}
    
    local ecr_repo="${ECR_BASE_URI}/${image_name}"
    local full_tag="${ecr_repo}:${tag}"
    
    print_section "🐳 Building ${image_name}:${tag}"
    
    echo -e "${BLUE}Context: ${context_path}${NC}"
    echo -e "${BLUE}Dockerfile: ${dockerfile_path}${NC}"
    echo -e "${BLUE}Platform: ${platform}${NC}"
    echo -e "${BLUE}Target: ${full_tag}${NC}"
    echo ""
    
    # Change to the context directory
    cd "${context_path}"
    
    # Build the image
    echo -e "${YELLOW}🔨 Building image...${NC}"
    if [ -f "${dockerfile_path}" ]; then
        docker build --platform ${platform} -f "${dockerfile_path}" -t "${full_tag}" .
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Build successful for ${image_name}:${tag}${NC}"
        else
            echo -e "${RED}❌ Build failed for ${image_name}:${tag}${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ Dockerfile not found: ${dockerfile_path}${NC}"
        return 1
    fi
    
    # Push the image
    echo -e "${YELLOW}📤 Pushing image...${NC}"
    docker push "${full_tag}"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Push successful for ${image_name}:${tag}${NC}"
        echo -e "${CYAN}📍 Image URI: ${full_tag}${NC}"
    else
        echo -e "${RED}❌ Push failed for ${image_name}:${tag}${NC}"
        return 1
    fi
    
    echo ""
    return 0
}

# Function to create ECR repository if it doesn't exist
create_ecr_repo_if_needed() {
    local repo_name=$1
    
    echo -e "${YELLOW}🏗️  Checking ECR repository: ${repo_name}${NC}"
    
    if ! aws ecr describe-repositories --repository-names "${repo_name}" --region ${AWS_REGION} > /dev/null 2>&1; then
        echo -e "${YELLOW}📦 Creating ECR repository: ${repo_name}${NC}"
        aws ecr create-repository \
            --repository-name "${repo_name}" \
            --region ${AWS_REGION} \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ ECR repository created: ${repo_name}${NC}"
        else
            echo -e "${RED}❌ Failed to create ECR repository: ${repo_name}${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}✅ ECR repository exists: ${repo_name}${NC}"
    fi
    echo ""
}

# Parse command line arguments
SKIP_BUILD=false
SKIP_PUSH=false
SPECIFIC_IMAGE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --skip-push)
            SKIP_PUSH=true
            shift
            ;;
        --image)
            SPECIFIC_IMAGE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --skip-build     Skip building images (only push existing)"
            echo "  --skip-push      Skip pushing images (only build)"
            echo "  --image <name>   Build/push only specific image"
            echo "  --dry-run        Show what would be done without executing"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "Available images:"
            echo "  - hive-metastore"
            echo "  - spark-ingest" 
            echo "  - spark-aggregate"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown parameter: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}🔍 DRY RUN MODE - No actual build/push operations will be performed${NC}"
    echo ""
fi

# Main execution starts here
main() {
    # Check prerequisites
    if [ "$DRY_RUN" = false ]; then
        check_aws_auth
        ecr_login
    else
        print_section "🔍 DRY RUN - Skipping AWS auth and ECR login"
    fi
    
    # Define image configurations
    # Format: "repo_name|dockerfile_path|context_path|tag|platform"
    declare -a IMAGES=(
        "data-platform/hive-metastore|Dockerfile|${PROJECT_ROOT}/hive-metastore|2.3.9-fixed|linux/amd64"
        "log-ingest-spark|Dockerfile|${PROJECT_ROOT}/spark-ingest|v14-spark351|linux/amd64"
        "spark-aggregate|Dockerfile|${PROJECT_ROOT}/spark-aggregate|v1|linux/amd64"
    )
    
    # Filter images if specific image requested
    if [ ! -z "$SPECIFIC_IMAGE" ]; then
        case $SPECIFIC_IMAGE in
            hive-metastore|hive)
                IMAGES=("${IMAGES[0]}")
                ;;
            spark-ingest|ingest)
                IMAGES=("${IMAGES[1]}")
                ;;
            spark-aggregate|aggregate)
                IMAGES=("${IMAGES[2]}")
                ;;
            *)
                echo -e "${RED}❌ Unknown image: $SPECIFIC_IMAGE${NC}"
                echo "Available images: hive-metastore, spark-ingest, spark-aggregate"
                exit 1
                ;;
        esac
        echo -e "${CYAN}🎯 Building only: $SPECIFIC_IMAGE${NC}"
        echo ""
    fi
    
    # Build and push each image
    SUCCESS_COUNT=0
    FAILED_IMAGES=()
    
    for image_config in "${IMAGES[@]}"; do
        IFS='|' read -r repo_name dockerfile_path context_path tag platform <<< "$image_config"
        
        if [ "$DRY_RUN" = true ]; then
            echo -e "${CYAN}[DRY RUN] Would process:${NC}"
            echo -e "${BLUE}  Repository: ${repo_name}${NC}"
            echo -e "${BLUE}  Dockerfile: ${dockerfile_path}${NC}"
            echo -e "${BLUE}  Context: ${context_path}${NC}"
            echo -e "${BLUE}  Tag: ${tag}${NC}"
            echo -e "${BLUE}  Platform: ${platform}${NC}"
            echo ""
            continue
        fi
        
        # Create ECR repository if needed
        create_ecr_repo_if_needed "${repo_name}"
        
        # Build and push the image
        if build_and_push_image "${repo_name}" "${dockerfile_path}" "${context_path}" "${tag}" "${platform}"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAILED_IMAGES+=("${repo_name}:${tag}")
        fi
    done
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${CYAN}🔍 DRY RUN completed - no actual operations performed${NC}"
        exit 0
    fi
    
    # Summary
    print_section "📊 Build Summary"
    echo -e "${GREEN}✅ Successfully processed: ${SUCCESS_COUNT} images${NC}"
    
    if [ ${#FAILED_IMAGES[@]} -gt 0 ]; then
        echo -e "${RED}❌ Failed images: ${#FAILED_IMAGES[@]}${NC}"
        for failed_image in "${FAILED_IMAGES[@]}"; do
            echo -e "${RED}  - ${failed_image}${NC}"
        done
        echo ""
        echo -e "${YELLOW}💡 Check the logs above for error details${NC}"
        exit 1
    else
        echo -e "${GREEN}🎉 All images built and pushed successfully!${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}📍 All images are now available in ECR:${NC}"
    echo -e "${BLUE}  Base URI: ${ECR_BASE_URI}${NC}"
    echo -e "${BLUE}  Region: ${AWS_REGION}${NC}"
    
    # Show Terraform variables that might need updating
    echo ""
    print_section "🔧 Terraform Variables"
    echo -e "${YELLOW}💡 Update these in your terraform.tfvars or variables:${NC}"
    echo ""
    echo "hive_metastore_image = \"${ECR_BASE_URI}/data-platform/hive-metastore:2.3.9-fixed\""
    echo ""
    echo -e "${YELLOW}💡 Spark job images are already configured in Terraform${NC}"
    
    echo ""
    echo -e "${GREEN}🚀 Ready for deployment!${NC}"
}

# Check if Docker is running
if [ "$DRY_RUN" = false ]; then
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}❌ Docker is not running. Please start Docker and try again.${NC}"
        exit 1
    fi
fi

# Run main function
main "$@"
