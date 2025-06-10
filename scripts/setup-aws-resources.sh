#!/bin/bash

# AWS Resources Setup Script
# This script sets up prerequisite AWS resources for the Book Library API

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
REGION="us-east-1"
ENVIRONMENT="dev"
PROJECT_NAME="book-library-api"

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --region REGION      AWS region [default: us-east-1]"
    echo "  -e, --environment ENV    Environment (dev, staging, production) [default: dev]"
    echo "  -p, --project PROJECT    Project name [default: book-library-api]"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "This script creates:"
    echo "  - S3 bucket for SAM deployments"
    echo "  - S3 bucket for documentation"
    echo "  - S3 bucket for backups (production only)"
    echo "  - IAM roles and policies"
    echo "  - SSM parameters for configuration"
    echo "  - CloudWatch log groups"
    echo ""
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
    
    # Get account ID and current user
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    CURRENT_USER=$(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)
    
    log_success "Prerequisites met"
    log "Account ID: $ACCOUNT_ID"
    log "Current user: $CURRENT_USER"
}

# Function to create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    # SAM deployment bucket
    SAM_BUCKET="sam-deployment-$ACCOUNT_ID-$REGION"
    create_bucket "$SAM_BUCKET" "SAM deployment artifacts"
    
    # Documentation bucket
    DOCS_BUCKET="$PROJECT_NAME-docs-$ACCOUNT_ID-$ENVIRONMENT"
    create_bucket "$DOCS_BUCKET" "API documentation"
    
    # Backup bucket (production only)
    if [ "$ENVIRONMENT" = "production" ]; then
        BACKUP_BUCKET="$PROJECT_NAME-backups-$ACCOUNT_ID"
        create_bucket "$BACKUP_BUCKET" "Production backups"
        
        # Enable versioning on backup bucket
        aws s3api put-bucket-versioning \
            --bucket "$BACKUP_BUCKET" \
            --versioning-configuration Status=Enabled
        
        log_success "Versioning enabled on backup bucket"
    fi
}

# Function to create a single S3 bucket
create_bucket() {
    local bucket_name=$1
    local description=$2
    
    if aws s3 ls "s3://$bucket_name" &> /dev/null; then
        log_warning "Bucket already exists: $bucket_name"
    else
        log "Creating S3 bucket: $bucket_name ($description)"
        
        if [ "$REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "$bucket_name"
        else
            aws s3api create-bucket \
                --bucket "$bucket_name" \
                --region "$REGION" \
                --create-bucket-configuration LocationConstraint="$REGION"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$bucket_name" \
            --versioning-configuration Status=Enabled
        
        # Enable server-side encryption
        aws s3api put-bucket-encryption \
            --bucket "$bucket_name" \
            --server-side-encryption-configuration '{
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }
                ]
            }'
        
        # Block public access
        aws s3api put-public-access-block \
            --bucket "$bucket_name" \
            --public-access-block-configuration \
                BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
        
        # Add lifecycle policy to delete old versions
        aws s3api put-bucket-lifecycle-configuration \
            --bucket "$bucket_name" \
            --lifecycle-configuration '{
                "Rules": [
                    {
                        "ID": "DeleteOldVersions",
                        "Status": "Enabled",
                        "Filter": {},
                        "NoncurrentVersionExpiration": {
                            "NoncurrentDays": 30
                        }
                    }
                ]
            }'
        
        log_success "Created S3 bucket: $bucket_name"
    fi
}

# Function to create IAM roles and policies
create_iam_resources() {
    log "Creating IAM resources..."
    
    # Deployment role for GitHub Actions
    create_deployment_role
    
    # Lambda execution role (will be created by SAM, but we can create custom policies)
    create_lambda_policies
}

# Function to create deployment role for GitHub Actions
create_deployment_role() {
    local role_name="$PROJECT_NAME-deployment-role-$ENVIRONMENT"
    
    log "Creating deployment role: $role_name"
    
    # Trust policy for GitHub Actions OIDC
    local trust_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Federated": "arn:aws:iam::'$ACCOUNT_ID':oidc-provider/token.actions.githubusercontent.com"
                },
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Condition": {
                    "StringEquals": {
                        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                    }
                }
            },
            {
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::'$ACCOUNT_ID':root"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'
    
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_warning "Role already exists: $role_name"
    else
        aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document "$trust_policy" \
            --description "Role for deploying $PROJECT_NAME to $ENVIRONMENT"
        
        # Attach necessary policies
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/CloudFormationFullAccess"
        
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/IAMFullAccess"
        
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
        
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
        
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess"
        
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator"
        
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/CloudWatchFullAccess"
        
        log_success "Created deployment role: $role_name"
    fi
}

# Function to create Lambda policies
create_lambda_policies() {
    log "Creating Lambda policies..."
    
    # DynamoDB access policy
    local dynamodb_policy_name="$PROJECT_NAME-dynamodb-policy-$ENVIRONMENT"
    local dynamodb_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "dynamodb:Query",
                    "dynamodb:Scan",
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:BatchGetItem",
                    "dynamodb:BatchWriteItem"
                ],
                "Resource": [
                    "arn:aws:dynamodb:'$REGION':'$ACCOUNT_ID':table/'$PROJECT_NAME'-*-users",
                    "arn:aws:dynamodb:'$REGION':'$ACCOUNT_ID':table/'$PROJECT_NAME'-*-books",
                    "arn:aws:dynamodb:'$REGION':'$ACCOUNT_ID':table/'$PROJECT_NAME'-*-borrowing",
                    "arn:aws:dynamodb:'$REGION':'$ACCOUNT_ID':table/'$PROJECT_NAME'-*-users/index/*",
                    "arn:aws:dynamodb:'$REGION':'$ACCOUNT_ID':table/'$PROJECT_NAME'-*-books/index/*",
                    "arn:aws:dynamodb:'$REGION':'$ACCOUNT_ID':table/'$PROJECT_NAME'-*-borrowing/index/*"
                ]
            }
        ]
    }'
    
    if aws iam get-policy --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/$dynamodb_policy_name" &> /dev/null; then
        log_warning "Policy already exists: $dynamodb_policy_name"
    else
        aws iam create-policy \
            --policy-name "$dynamodb_policy_name" \
            --policy-document "$dynamodb_policy" \
            --description "DynamoDB access for $PROJECT_NAME Lambda functions"
        
        log_success "Created DynamoDB policy: $dynamodb_policy_name"
    fi
}

# Function to create SSM parameters
create_ssm_parameters() {
    log "Creating SSM parameters..."
    
    # API Key parameter
    local api_key_param="/$PROJECT_NAME-$ENVIRONMENT/api-key"
    
    if aws ssm get-parameter --name "$api_key_param" &> /dev/null; then
        log_warning "Parameter already exists: $api_key_param"
    else
        # Generate a random API key
        local api_key=$(openssl rand -base64 32)
        
        aws ssm put-parameter \
            --name "$api_key_param" \
            --value "$api_key" \
            --type "SecureString" \
            --description "API Key for $PROJECT_NAME $ENVIRONMENT environment"
        
        log_success "Created API key parameter: $api_key_param"
        log_warning "API Key: $api_key (store this securely!)"
    fi
    
    # Environment configuration parameters
    local config_params=(
        "rate-limit:100"
        "cors-origins:*"
        "log-level:INFO"
    )
    
    if [ "$ENVIRONMENT" = "production" ]; then
        config_params=(
            "rate-limit:1000"
            "cors-origins:https://booklibrary.com,https://www.booklibrary.com"
            "log-level:ERROR"
        )
    elif [ "$ENVIRONMENT" = "staging" ]; then
        config_params=(
            "rate-limit:200"
            "cors-origins:https://*.staging.booklibrary.com"
            "log-level:WARN"
        )
    fi
    
    for param_def in "${config_params[@]}"; do
        local param_name=$(echo "$param_def" | cut -d':' -f1)
        local param_value=$(echo "$param_def" | cut -d':' -f2)
        local full_param_name="/$PROJECT_NAME-$ENVIRONMENT/$param_name"
        
        if aws ssm get-parameter --name "$full_param_name" &> /dev/null; then
            log_warning "Parameter already exists: $full_param_name"
        else
            aws ssm put-parameter \
                --name "$full_param_name" \
                --value "$param_value" \
                --type "String" \
                --description "$param_name configuration for $PROJECT_NAME $ENVIRONMENT"
            
            log_success "Created parameter: $full_param_name = $param_value"
        fi
    done
}

# Function to create CloudWatch log groups
create_log_groups() {
    log "Creating CloudWatch log groups..."
    
    local log_groups=(
        "/aws/lambda/$PROJECT_NAME-$ENVIRONMENT-list-users"
        "/aws/lambda/$PROJECT_NAME-$ENVIRONMENT-create-user"
        "/aws/lambda/$PROJECT_NAME-$ENVIRONMENT-get-user"
        "/aws/lambda/$PROJECT_NAME-$ENVIRONMENT-list-books"
        "/aws/lambda/$PROJECT_NAME-$ENVIRONMENT-create-book"
        "/aws/lambda/$PROJECT_NAME-$ENVIRONMENT-borrow-book"
        "/aws/lambda/$PROJECT_NAME-$ENVIRONMENT-return-book"
        "/aws/apigateway/$PROJECT_NAME-$ENVIRONMENT"
    )
    
    for log_group in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[?logGroupName==`'$log_group'`]' --output text | grep -q "$log_group"; then
            log_warning "Log group already exists: $log_group"
        else
            aws logs create-log-group --log-group-name "$log_group"
            
            # Set retention policy
            local retention_days=7
            if [ "$ENVIRONMENT" = "production" ]; then
                retention_days=30
            elif [ "$ENVIRONMENT" = "staging" ]; then
                retention_days=14
            fi
            
            aws logs put-retention-policy \
                --log-group-name "$log_group" \
                --retention-in-days $retention_days
            
            log_success "Created log group: $log_group (retention: ${retention_days} days)"
        fi
    done
}

# Function to create GitHub OIDC provider (if not exists)
create_github_oidc_provider() {
    log "Checking GitHub OIDC provider..."
    
    local provider_url="token.actions.githubusercontent.com"
    local thumbprint="6938fd4d98bab03faadb97b34396831e3780aea1"
    
    if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::$ACCOUNT_ID:oidc-provider/$provider_url" &> /dev/null; then
        log_warning "GitHub OIDC provider already exists"
    else
        log "Creating GitHub OIDC provider..."
        
        aws iam create-open-id-connect-provider \
            --url "https://$provider_url" \
            --thumbprint-list "$thumbprint" \
            --client-id-list "sts.amazonaws.com"
        
        log_success "Created GitHub OIDC provider"
    fi
}

# Function to output setup summary
output_summary() {
    log "Setup summary:"
    
    cat << EOF

🎉 AWS Resources Setup Complete!
================================

Environment: $ENVIRONMENT
Region: $REGION
Account ID: $ACCOUNT_ID

📦 S3 Buckets Created:
- SAM Deployment: sam-deployment-$ACCOUNT_ID-$REGION
- Documentation: $PROJECT_NAME-docs-$ACCOUNT_ID-$ENVIRONMENT
$([ "$ENVIRONMENT" = "production" ] && echo "- Backups: $PROJECT_NAME-backups-$ACCOUNT_ID")

🔐 IAM Resources:
- Deployment Role: $PROJECT_NAME-deployment-role-$ENVIRONMENT
- DynamoDB Policy: $PROJECT_NAME-dynamodb-policy-$ENVIRONMENT
- GitHub OIDC Provider: token.actions.githubusercontent.com

📊 SSM Parameters:
- API Key: /$PROJECT_NAME-$ENVIRONMENT/api-key
- Rate Limit: /$PROJECT_NAME-$ENVIRONMENT/rate-limit
- CORS Origins: /$PROJECT_NAME-$ENVIRONMENT/cors-origins
- Log Level: /$PROJECT_NAME-$ENVIRONMENT/log-level

📝 CloudWatch Log Groups:
- Lambda function logs
- API Gateway logs

Next Steps:
-----------
1. Store the API key securely in your CI/CD system
2. Configure GitHub secrets for deployment
3. Run the deployment script: ./scripts/deploy-resources.sh -e $ENVIRONMENT
4. Set up monitoring and alerting

GitHub Secrets to Configure:
----------------------------
- AWS_ACCESS_KEY_ID (or use OIDC role)
- AWS_SECRET_ACCESS_KEY (or use OIDC role)  
- SAM_DEPLOYMENT_BUCKET: sam-deployment-$ACCOUNT_ID-$REGION
- ${ENVIRONMENT^^}_API_KEY: (retrieve from SSM parameter)

EOF

    # Get API key for output
    local api_key=$(aws ssm get-parameter --name "/$PROJECT_NAME-$ENVIRONMENT/api-key" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || echo "Not found")
    if [ "$api_key" != "Not found" ]; then
        echo "⚠️  API Key for $ENVIRONMENT: $api_key"
        echo "   Store this securely in your GitHub secrets as ${ENVIRONMENT^^}_API_KEY"
        echo
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT_NAME="$2"
            shift 2
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
    echo -e "${BLUE}🛠️  AWS Resources Setup Script${NC}"
    echo "=================================="
    echo "Environment: $ENVIRONMENT"
    echo "Region: $REGION"
    echo "Project: $PROJECT_NAME"
    echo "Timestamp: $(date)"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Create resources
    create_s3_buckets
    create_github_oidc_provider
    create_iam_resources
    create_ssm_parameters
    create_log_groups
    
    # Output summary
    output_summary
    
    log_success "AWS resources setup completed successfully! 🎉"
}

# Run main function
main "$@"