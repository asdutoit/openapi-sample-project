# Book Library Management API

[![API Validation](https://github.com/your-org/book-library-api/workflows/Validate%20OpenAPI%20Specification/badge.svg)](https://github.com/your-org/book-library-api/actions)
[![Deploy to Dev](https://github.com/your-org/book-library-api/workflows/Deploy%20to%20Development/badge.svg)](https://github.com/your-org/book-library-api/actions)

A comprehensive OpenAPI-first Book Library Management API built with AWS Lambda, DynamoDB, and API Gateway. This project demonstrates modern API development practices including automated validation, multi-environment deployment, and comprehensive CI/CD pipelines.

## 🚀 Features

- **OpenAPI 3.0.3 Specification**: Complete API documentation with examples
- **AWS Serverless Architecture**: Lambda functions with DynamoDB storage
- **Multi-Environment Deployment**: Development, staging, and production environments
- **Automated CI/CD**: GitHub Actions workflows for validation and deployment
- **Comprehensive Validation**: OpenAPI syntax, linting, and security checks
- **Rate Limiting & Security**: AWS WAF, API keys, and CORS configuration
- **Monitoring & Logging**: CloudWatch integration with alarms

## 📋 Table of Contents

- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [API Documentation](#api-documentation)
- [Development Setup](#development-setup)
- [Deployment](#deployment)
- [Testing](#testing)
- [Monitoring](#monitoring)
- [Contributing](#contributing)

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   API Gateway   │────│   Lambda Functions │────│    DynamoDB     │
│                 │    │                  │    │                 │
│ • Rate Limiting │    │ • User Management│    │ • Users Table   │
│ • Authentication│    │ • Book Management│    │ • Books Table   │
│ • CORS          │    │ • Borrowing Logic│    │ • Borrowing Tbl │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────────┐
                    │    Monitoring       │
                    │                     │
                    │ • CloudWatch Logs   │
                    │ • CloudWatch Alarms │
                    │ • X-Ray Tracing     │
                    └─────────────────────┘
```

### Components

- **API Gateway**: RESTful API endpoints with authentication and rate limiting
- **Lambda Functions**: Serverless business logic for each API operation
- **DynamoDB**: NoSQL database for storing users, books, and borrowing records
- **CloudWatch**: Logging, monitoring, and alerting
- **AWS WAF**: Web application firewall for additional security
- **S3**: Documentation hosting and deployment artifacts

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- AWS SAM CLI installed
- Node.js 18.x or later
- Docker (for local testing)

### 1. Clone and Setup

```bash
git clone https://github.com/your-org/book-library-api.git
cd book-library-api

# Copy environment template
cp .env.example .env

# Edit .env with your configuration
nano .env
```

### 2. Install Dependencies

```bash
# Install Lambda layer dependencies
cd src/layers/nodejs
npm install
cd ../../..

# Make scripts executable
chmod +x scripts/*.sh
```

### 3. Setup AWS Resources

```bash
# Setup prerequisite AWS resources
./scripts/setup-aws-resources.sh -e dev -r us-east-1

# This creates:
# - S3 buckets for deployment and documentation
# - IAM roles and policies
# - SSM parameters for configuration
# - CloudWatch log groups
```

### 4. Deploy to Development

```bash
# Validate and deploy
./scripts/validate-openapi.sh
./scripts/deploy-resources.sh -e dev
```

### 5. Test the API

```bash
# Get API endpoint from deployment output
API_ENDPOINT="https://your-api-id.execute-api.us-east-1.amazonaws.com/dev"
API_KEY="your-api-key-from-ssm"

# Test users endpoint
curl -X GET "$API_ENDPOINT/users?limit=5" \
  -H "X-API-Key: $API_KEY" \
  -H "Accept: application/json"
```

## 📚 API Documentation

The API provides endpoints for managing a book library system:

### Base URLs

- **Development**: `https://api-dev.booklibrary.com`
- **Staging**: `https://api-staging.booklibrary.com`
- **Production**: `https://api.booklibrary.com`

### Main Endpoints

| Endpoint             | Method | Description                |
| -------------------- | ------ | -------------------------- |
| `/users`             | GET    | List users with pagination |
| `/users`             | POST   | Create a new user          |
| `/users/{id}`        | GET    | Get user details           |
| `/books`             | GET    | List books with filtering  |
| `/books`             | POST   | Add a new book             |
| `/books/{id}/borrow` | POST   | Borrow a book              |
| `/books/{id}/return` | POST   | Return a book              |

For complete API documentation, see [docs/README.md](docs/README.md) or visit the live documentation at your deployed endpoint.

## 🛠️ Development Setup

### Local Development

```bash
# Start local API Gateway
sam local start-api --env-vars env.json

# The API will be available at http://localhost:3000
```

### Environment Configuration

Create `env.json` for local development:

```json
{
  "Parameters": {
    "ENVIRONMENT": "local",
    "USERS_TABLE": "book-library-local-users",
    "BOOKS_TABLE": "book-library-local-books",
    "BORROWING_TABLE": "book-library-local-borrowing",
    "API_KEY_VALUE": "local-test-key"
  }
}
```

### Code Structure

```
├── api/                    # OpenAPI specification
│   └── openapi.yaml
├── src/                    # Lambda function source code
│   ├── handlers/           # Lambda function handlers
│   │   ├── users.js
│   │   ├── books.js
│   │   └── common/
│   └── layers/             # Lambda layers
├── infrastructure/         # AWS infrastructure as code
│   ├── template.yaml       # SAM template
│   └── parameters.json     # Environment parameters
├── .github/workflows/      # CI/CD pipelines
├── scripts/                # Deployment and utility scripts
└── docs/                   # Documentation
```

## 🚀 Deployment

### Environments

The project supports three environments:

1. **Development** (`dev`):

   - Automatic deployment on merge to `main`
   - Basic monitoring
   - Pay-per-request DynamoDB

2. **Staging** (`staging`):

   - Manual deployment for testing
   - WAF enabled
   - Enhanced monitoring
   - Provisioned DynamoDB

3. **Production** (`production`):
   - Manual deployment with approval
   - Custom domain
   - Full monitoring and alerting
   - Backup strategies

### Manual Deployment

```bash
# Deploy to specific environment
./scripts/deploy-resources.sh -e staging -r us-east-1

# Build only (for testing)
./scripts/deploy-resources.sh -e production --build-only

# Validate only
./scripts/deploy-resources.sh --validate-only
```

### GitHub Actions

The project includes automated workflows:

1. **validate-api.yml**: Validates OpenAPI spec on PRs
2. **deploy-dev.yml**: Deploys to development on main branch
3. **deploy-staging.yml**: Manual deployment to staging
4. **deploy-prod.yml**: Manual deployment to production with approvals

#### Required GitHub Secrets

```bash
# AWS Credentials
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY

# Environment-specific API Keys
DEV_API_KEY
STAGING_API_KEY
PROD_API_KEY

# S3 Buckets
SAM_DEPLOYMENT_BUCKET
STAGING_SAM_DEPLOYMENT_BUCKET
PROD_SAM_DEPLOYMENT_BUCKET

# SSL Certificates (for custom domains)
STAGING_CERTIFICATE_ARN
PROD_CERTIFICATE_ARN

# Notifications
SLACK_WEBHOOK_URL
```

## 🧪 Testing

### API Validation

```bash
# Validate OpenAPI specification
./scripts/validate-openapi.sh

# This runs:
# - Syntax validation
# - Linting with Spectral
# - Security checks
# - Example validation
```

### Integration Testing

```bash
# Test against deployed environment
API_ENDPOINT="https://your-api.execute-api.us-east-1.amazonaws.com/dev"
API_KEY="your-api-key"

# Run integration tests
npm test -- --env=dev --endpoint=$API_ENDPOINT --key=$API_KEY
```

### Load Testing

```bash
# Basic load test with Apache Bench
ab -n 100 -c 10 -H "X-API-Key: $API_KEY" "$API_ENDPOINT/users"
```

## 📊 Monitoring

### CloudWatch Dashboards

The deployment creates dashboards for:

- API Gateway metrics (latency, errors, requests)
- Lambda function performance
- DynamoDB metrics
- Custom business metrics

### Alarms

Automatic alarms are configured for:

- High error rates (4XX/5XX)
- Increased latency
- Lambda failures
- DynamoDB throttling

### Logging

Structured logging is implemented across all components:

- API Gateway access logs
- Lambda function logs with correlation IDs
- DynamoDB operation logs

## 🔧 Configuration

### Environment Variables

Key configuration options:

| Variable      | Development | Staging                | Production   |
| ------------- | ----------- | ---------------------- | ------------ |
| Rate Limit    | 100/min     | 200/min                | 1000/min     |
| CORS Origins  | `*`         | `*.staging.domain.com` | `domain.com` |
| WAF Enabled   | No          | Yes                    | Yes          |
| Custom Domain | No          | Optional               | Yes          |
| X-Ray Tracing | No          | Yes                    | Yes          |

### Feature Flags

Configure features per environment:

- `EnableWAF`: Web Application Firewall
- `EnableCustomDomain`: Custom domain and SSL
- `EnableXRay`: Request tracing
- `ReservedConcurrency`: Lambda concurrency limits

## 🤝 Contributing

### Development Workflow

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Make changes and test locally
4. Validate OpenAPI spec: `./scripts/validate-openapi.sh`
5. Commit changes with descriptive messages
6. Push to your fork and submit a Pull Request

### Code Standards

- Follow existing code structure and naming conventions
- Add comprehensive error handling
- Include examples in OpenAPI specification
- Write descriptive commit messages
- Update documentation for new features

### Pull Request Process

1. Ensure all tests pass
2. Update documentation if needed
3. Add examples for new endpoints
4. Ensure OpenAPI validation passes
5. Get approval from maintainers

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation**: [docs/README.md](docs/README.md)
- **Issues**: GitHub Issues
- **Email**: api-support@booklibrary.com

## 📈 Roadmap

- [ ] WebSocket support for real-time notifications
- [ ] GraphQL endpoint
- [ ] Mobile SDK
- [ ] Advanced search with Elasticsearch
- [ ] Multi-language support
- [ ] Book recommendation engine

---

**Built with ❤️ by Stephan Du Toit using AWS SAM, OpenAPI, and modern DevOps practices**
