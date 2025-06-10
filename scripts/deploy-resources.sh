#!/bin/bash

# AWS Resources Deployment Script
# This script deploys the Book Library API using AWS SAM

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="dev"
REGION="us-east-1"
STACK_NAME=""
CONFIG_FILE="infrastructure/parameters.json"
TEMPLATE_FILE="infrastructure/template.yaml"
BUILD_DIR=".aws-sam"

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV    Deployment environment (dev, staging, production) [default: dev]"
    echo "  -r, --region REGION      AWS region [default: us-east-1]"
    echo "  -s, --stack-name NAME    CloudFormation stack name [default: book-library-api-ENV]"
    echo "  -c, --config-file FILE   Parameters configuration file [default: infrastructure/parameters.json]"
    echo "  -t, --template FILE      SAM template file [default: infrastructure/template.yaml]"
    echo "  -b, --build-only         Only build, don't deploy"
    echo "  -d, --deploy-only        Only deploy (skip build)"
    echo "  -v, --validate-only      Only validate template"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_PROFILE              AWS profile to use"
    echo "  SAM_DEPLOYMENT_BUCKET    S3 bucket for SAM artifacts"
    echo "  API_KEY_VALUE           API key for the application"
    echo ""
    echo "Examples:"
    echo "  $0 -e dev                Deploy to development"
    echo "  $0 -e staging -r us-west-2  Deploy to staging in us-west-2"
    echo "  $0 -e production --build-only  Only build for production"
}

# Function to log messages
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    # Check if SAM CLI is installed
    if ! command -v sam &> /dev/null; then
        log_error "AWS SAM CLI is required but not installed"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured properly"
        exit 1
    fi
    
    # Check if template file exists
    if [ ! -f "$TEMPLATE_FILE" ]; then
        log_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi
    
    # Check if config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to load environment parameters
load_parameters() {
    log "Loading parameters for environment: $ENVIRONMENT"
    
    # Check if environment exists in config
    if ! jq -e ".$ENVIRONMENT" "$CONFIG_FILE" &> /dev/null; then
        log_error "Environment '$ENVIRONMENT' not found in $CONFIG_FILE"
        exit 1
    fi
    
    # Extract parameters for the environment
    PARAMS=$(jq -r ".$ENVIRONMENT | to_entries | map(\"\\(.key)=\\(.value)\") | .[]" "$CONFIG_FILE")
    
    # Set stack name if not provided
    if [ -z "$STACK_NAME" ]; then
        STACK_NAME="book-library-api-$ENVIRONMENT"
    fi
    
    log "Stack name: $STACK_NAME"
    log "Region: $REGION"
}

# Function to validate SAM template
validate_template() {
    log "Validating SAM template..."
    
    if sam validate --template "$TEMPLATE_FILE" --region "$REGION"; then
        log_success "Template validation passed"
    else
        log_error "Template validation failed"
        exit 1
    fi
}

# Function to install Lambda dependencies
install_dependencies() {
    log "Installing Lambda dependencies..."
    
    # Install dependencies for Lambda layer
    if [ -f "src/layers/nodejs/package.json" ]; then
        cd src/layers/nodejs
        npm ci --production
        cd ../../..
        log_success "Lambda layer dependencies installed"
    fi
    
    # Install any other dependencies if needed
    log_success "Dependencies installation completed"
}

# Function to build SAM application
build_application() {
    log "Building SAM application..."
    
    # Prepare parameter overrides
    PARAMETER_OVERRIDES=""
    while IFS= read -r param; do
        PARAMETER_OVERRIDES="$PARAMETER_OVERRIDES $param"
    done <<< "$PARAMS"
    
    # Add API key if provided
    if [ -n "$API_KEY_VALUE" ]; then
        PARAMETER_OVERRIDES="$PARAMETER_OVERRIDES ApiKeyValue=$API_KEY_VALUE"
    fi
    
    # Build the application
    sam build \
        --template-file "$TEMPLATE_FILE" \
        --build-dir "$BUILD_DIR" \
        --parameter-overrides $PARAMETER_OVERRIDES \
        --region "$REGION"
    
    if [ $? -eq 0 ]; then
        log_success "SAM application built successfully"
    else
        log_error "SAM build failed"
        exit 1
    fi
}

# Function to deploy application
deploy_application() {
    log "Deploying SAM application..."
    
    # Prepare parameter overrides
    PARAMETER_OVERRIDES=""
    while IFS= read -r param; do
        PARAMETER_OVERRIDES="$PARAMETER_OVERRIDES $param"
    done <<< "$PARAMS"
    
    # Add API key if provided
    if [ -n "$API_KEY_VALUE" ]; then
        PARAMETER_OVERRIDES="$PARAMETER_OVERRIDES ApiKeyValue=$API_KEY_VALUE"
    fi
    
    # Determine S3 bucket for deployment
    if [ -z "$SAM_DEPLOYMENT_BUCKET" ]; then
        # Try to get from SSM parameter or create a default name
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        SAM_DEPLOYMENT_BUCKET="sam-deployment-$ACCOUNT_ID-$REGION"
        log_warning "SAM_DEPLOYMENT_BUCKET not set, using: $SAM_DEPLOYMENT_BUCKET"
    fi
    
    # Check if bucket exists, create if it doesn't
    if ! aws s3 ls "s3://$SAM_DEPLOYMENT_BUCKET" &> /dev/null; then
        log "Creating S3 bucket: $SAM_DEPLOYMENT_BUCKET"
        aws s3 mb "s3://$SAM_DEPLOYMENT_BUCKET" --region "$REGION"
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$SAM_DEPLOYMENT_BUCKET" \
            --versioning-configuration Status=Enabled
    fi
    
    # Deploy the application
    sam deploy \
        --template-file "$BUILD_DIR/template.yaml" \
        --stack-name "$STACK_NAME" \
        --s3-bucket "$SAM_DEPLOYMENT_BUCKET" \
        --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
        --region "$REGION" \
        --parameter-overrides $PARAMETER_OVERRIDES \
        --no-confirm-changeset \
        --no-fail-on-empty-changeset \
        --tags \
            Environment="$ENVIRONMENT" \
            Project="BookLibraryAPI" \
            ManagedBy="SAM" \
            DeployedBy="$(whoami)" \
            DeployedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    if [ $? -eq 0 ]; then
        log_success "Deployment completed successfully"
    else
        log_error "Deployment failed"
        exit 1
    fi
}

# Function to get stack outputs
get_outputs() {
    log "Retrieving stack outputs..."
    
    # Get stack outputs
    OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs' \
        --output json)
    
    if [ "$OUTPUTS" != "null" ] && [ "$OUTPUTS" != "[]" ]; then
        echo -e "${BLUE}📋 Stack Outputs:${NC}"
        echo "$OUTPUTS" | jq -r '.[] | "  \(.OutputKey): \(.OutputValue)"'
        
        # Extract API endpoint
        API_ENDPOINT=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="ApiEndpoint") | .OutputValue')
        if [ -n "$API_ENDPOINT" ] && [ "$API_ENDPOINT" != "null" ]; then
            echo
            echo -e "${GREEN}🚀 API Endpoint: $API_ENDPOINT${NC}"
        fi
        
        # Extract custom domain if available
        CUSTOM_DOMAIN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="CustomDomainUrl") | .OutputValue')
        if [ -n "$CUSTOM_DOMAIN" ] && [ "$CUSTOM_DOMAIN" != "null" ]; then
            echo -e "${GREEN}🌐 Custom Domain: $CUSTOM_DOMAIN${NC}"
        fi
    else
        log_warning "No stack outputs found"
    fi
}

# Function to run post-deployment tests
run_tests() {
    log "Running post-deployment tests..."
    
    # Get API endpoint
    API_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
        --output text)
    
    if [ -n "$API_ENDPOINT" ] && [ "$API_ENDPOINT" != "None" ]; then
        # Test API health (if health endpoint exists)
        if [ -n "$API_KEY_VALUE" ]; then
            log "Testing API endpoint..."
            
            # Test users endpoint
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                -X GET "$API_ENDPOINT/users?limit=1" \
                -H "X-API-Key: $API_KEY_VALUE" \
                -H "Accept: application/json")
            
            if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
                log_success "API endpoint is responding"
            else
                log_warning "API endpoint returned HTTP $HTTP_CODE"
            fi
        else
            log_warning "API_KEY_VALUE not set, skipping API tests"
        fi
    else
        log_warning "API endpoint not found in stack outputs"
    fi
}

# Function to create deployment summary
create_summary() {
    log "Creating deployment summary..."
    
    SUMMARY_FILE="deployment-summary-$(date +%Y%m%d-%H%M%S).json"
    
    cat > "$SUMMARY_FILE" << EOF
{
  "deployment": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "environment": "$ENVIRONMENT",
    "region": "$REGION",
    "stackName": "$STACK_NAME",
    "deployedBy": "$(whoami)",
    "gitCommit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')",
    "gitBranch": "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
  },
  "outputs": $(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].Outputs' --output json 2>/dev/null || echo 'null')
}
EOF
    
    log_success "Deployment summary saved to: $SUMMARY_FILE"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -c|--config-file)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -t|--template)
            TEMPLATE_FILE="$2"
            shift 2
            ;;
        -b|--build-only)
            BUILD_ONLY=true
            shift
            ;;
        -d|--deploy-only)
            DEPLOY_ONLY=true
            shift
            ;;
        -v|--validate-only)
            VALIDATE_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
    log_error "Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, production"
    exit 1
fi

# Main execution
main() {
    echo -e "${BLUE}🚀 AWS SAM Deployment Script${NC}"
    echo "==============================="
    echo "Environment: $ENVIRONMENT"
    echo "Region: $REGION"
    echo "Template: $TEMPLATE_FILE"
    echo "Config: $CONFIG_FILE"
    echo "Timestamp: $(date)"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Load parameters
    load_parameters
    
    # Validate template
    if [ "$VALIDATE_ONLY" = true ]; then
        validate_template
        log_success "Validation completed"
        exit 0
    fi
    
    validate_template
    
    # Install dependencies
    install_dependencies
    
    # Build application
    if [ "$DEPLOY_ONLY" != true ]; then
        build_application
    fi
    
    if [ "$BUILD_ONLY" = true ]; then
        log_success "Build completed"
        exit 0
    fi
    
    # Deploy application
    deploy_application
    
    # Get outputs
    get_outputs
    
    # Run tests
    run_tests
    
    # Create summary
    create_summary
    
    echo
    log_success "Deployment process completed successfully! 🎉"
}

# Run main function
main "$@"