#!/bin/bash

# OpenAPI Validation Script
# This script validates the OpenAPI specification using multiple tools

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OPENAPI_FILE="api/openapi.yaml"
REPORT_DIR="validation-reports"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

echo -e "${BLUE}📋 OpenAPI Validation Script${NC}"
echo "=============================="
echo "Timestamp: $(date)"
echo "OpenAPI File: $OPENAPI_FILE"
echo

# Create report directory
mkdir -p "$REPORT_DIR"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install validation tools
install_tools() {
    echo -e "${YELLOW}🔧 Installing validation tools...${NC}"
    
    if ! command_exists npm; then
        echo -e "${RED}❌ npm is required but not installed. Please install Node.js${NC}"
        exit 1
    fi
    
    if ! command_exists swagger-cli; then
        echo "Installing swagger-cli..."
        npm install -g @apidevtools/swagger-cli@4.0.4
    fi
    
    if ! command_exists spectral; then
        echo "Installing spectral..."
        npm install -g @stoplight/spectral-cli@6.11.0
    fi
    
    if ! command_exists openapi-generator-cli; then
        echo "Installing openapi-generator-cli..."
        npm install -g @openapitools/openapi-generator-cli@2.7.0
    fi
    
    echo -e "${GREEN}✅ Tools installed successfully${NC}"
    echo
}

# Function to validate OpenAPI syntax
validate_syntax() {
    echo -e "${YELLOW}🔍 Validating OpenAPI syntax...${NC}"
    
    if swagger-cli validate "$OPENAPI_FILE" > "$REPORT_DIR/syntax-validation_$TIMESTAMP.log" 2>&1; then
        echo -e "${GREEN}✅ OpenAPI syntax is valid${NC}"
        return 0
    else
        echo -e "${RED}❌ OpenAPI syntax validation failed${NC}"
        cat "$REPORT_DIR/syntax-validation_$TIMESTAMP.log"
        return 1
    fi
}

# Function to create Spectral ruleset if it doesn't exist
create_spectral_ruleset() {
    if [ ! -f ".spectral.yml" ]; then
        echo -e "${YELLOW}📝 Creating Spectral ruleset...${NC}"
        cat > .spectral.yml << 'EOF'
extends: ["spectral:oas"]
rules:
  # API Design Rules
  operation-success-response: error
  operation-operationId: error
  operation-description: warn
  operation-tags: warn
  info-contact: error
  info-description: warn
  info-license: warn
  no-$ref-siblings: error
  oas3-api-servers: error
  openapi-tags: warn
  operation-tag-defined: error
  
  # Security Rules
  oas3-schema: error
  oas3-valid-media-example: error
  oas3-valid-schema-example: error
  
  # Custom Rules
  no-trailing-slash:
    description: "Paths should not have trailing slashes"
    given: "$.paths[*]~"
    then:
      function: pattern
      functionOptions:
        notMatch: "/$"
    severity: warn
  
  require-api-version:
    description: "API must have a version"
    given: "$.info"
    then:
      field: version
      function: truthy
    severity: error
EOF
        echo -e "${GREEN}✅ Spectral ruleset created${NC}"
    fi
}

# Function to run linting
run_linting() {
    echo -e "${YELLOW}🧹 Running OpenAPI linting...${NC}"
    
    create_spectral_ruleset
    
    if spectral lint "$OPENAPI_FILE" --format json > "$REPORT_DIR/linting-results_$TIMESTAMP.json" 2>&1; then
        LINT_STATUS=0
    else
        LINT_STATUS=1
    fi
    
    # Also create human-readable report
    spectral lint "$OPENAPI_FILE" > "$REPORT_DIR/linting-results_$TIMESTAMP.txt" 2>&1 || true
    
    # Count issues
    ERROR_COUNT=$(jq -r '[.[] | select(.severity == 0)] | length' "$REPORT_DIR/linting-results_$TIMESTAMP.json" 2>/dev/null || echo "0")
    WARN_COUNT=$(jq -r '[.[] | select(.severity == 1)] | length' "$REPORT_DIR/linting-results_$TIMESTAMP.json" 2>/dev/null || echo "0")
    INFO_COUNT=$(jq -r '[.[] | select(.severity == 2)] | length' "$REPORT_DIR/linting-results_$TIMESTAMP.json" 2>/dev/null || echo "0")
    
    echo "Linting results:"
    echo "  Errors: $ERROR_COUNT"
    echo "  Warnings: $WARN_COUNT"
    echo "  Info: $INFO_COUNT"
    
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo -e "${RED}❌ Linting found $ERROR_COUNT error(s)${NC}"
        cat "$REPORT_DIR/linting-results_$TIMESTAMP.txt"
        return 1
    elif [ "$WARN_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Linting found $WARN_COUNT warning(s)${NC}"
    else
        echo -e "${GREEN}✅ No linting issues found${NC}"
    fi
    
    return 0
}

# Function to run security checks
run_security_checks() {
    echo -e "${YELLOW}🔒 Running security checks...${NC}"
    
    # Download OWASP ruleset if not exists
    OWASP_RULESET_URL="https://raw.githubusercontent.com/stoplightio/spectral-owasp-ruleset/main/ruleset.yml"
    
    if spectral lint "$OPENAPI_FILE" --ruleset "$OWASP_RULESET_URL" --format json > "$REPORT_DIR/security-check_$TIMESTAMP.json" 2>&1; then
        SECURITY_STATUS=0
    else
        SECURITY_STATUS=1
    fi
    
    # Also create human-readable report
    spectral lint "$OPENAPI_FILE" --ruleset "$OWASP_RULESET_URL" > "$REPORT_DIR/security-check_$TIMESTAMP.txt" 2>&1 || true
    
    # Count security issues
    SEC_ERROR_COUNT=$(jq -r '[.[] | select(.severity == 0)] | length' "$REPORT_DIR/security-check_$TIMESTAMP.json" 2>/dev/null || echo "0")
    SEC_WARN_COUNT=$(jq -r '[.[] | select(.severity == 1)] | length' "$REPORT_DIR/security-check_$TIMESTAMP.json" 2>/dev/null || echo "0")
    
    echo "Security check results:"
    echo "  Security Errors: $SEC_ERROR_COUNT"
    echo "  Security Warnings: $SEC_WARN_COUNT"
    
    if [ "$SEC_ERROR_COUNT" -gt 0 ]; then
        echo -e "${RED}❌ Security check found $SEC_ERROR_COUNT error(s)${NC}"
        return 1
    elif [ "$SEC_WARN_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Security check found $SEC_WARN_COUNT warning(s)${NC}"
    else
        echo -e "${GREEN}✅ No security issues found${NC}"
    fi
    
    return 0
}

# Function to validate examples
validate_examples() {
    echo -e "${YELLOW}📝 Validating examples...${NC}"
    
    if openapi-generator-cli validate -i "$OPENAPI_FILE" > "$REPORT_DIR/example-validation_$TIMESTAMP.log" 2>&1; then
        echo -e "${GREEN}✅ All examples are valid${NC}"
        return 0
    else
        echo -e "${RED}❌ Example validation failed${NC}"
        cat "$REPORT_DIR/example-validation_$TIMESTAMP.log"
        return 1
    fi
}

# Function to generate API statistics
generate_statistics() {
    echo -e "${YELLOW}📊 Generating API statistics...${NC}"
    
    # Count endpoints
    ENDPOINT_COUNT=$(yq eval '.paths | keys | length' "$OPENAPI_FILE" 2>/dev/null || echo "0")
    
    # Count operations
    OPERATION_COUNT=$(yq eval '[.paths[][] | select(type == "object")] | length' "$OPENAPI_FILE" 2>/dev/null || echo "0")
    
    # Count schemas
    SCHEMA_COUNT=$(yq eval '.components.schemas | keys | length' "$OPENAPI_FILE" 2>/dev/null || echo "0")
    
    # Count security schemes
    SECURITY_COUNT=$(yq eval '.components.securitySchemes | keys | length' "$OPENAPI_FILE" 2>/dev/null || echo "0")
    
    # Count tags
    TAG_COUNT=$(yq eval '.tags | length' "$OPENAPI_FILE" 2>/dev/null || echo "0")
    
    cat > "$REPORT_DIR/statistics_$TIMESTAMP.txt" << EOF
OpenAPI Statistics
==================
Generated: $(date)
File: $OPENAPI_FILE

API Overview:
- Title: $(yq eval '.info.title' "$OPENAPI_FILE")
- Version: $(yq eval '.info.version' "$OPENAPI_FILE")
- Description: $(yq eval '.info.description // "No description"' "$OPENAPI_FILE")

Statistics:
- Endpoints: $ENDPOINT_COUNT
- Operations: $OPERATION_COUNT
- Schemas: $SCHEMA_COUNT
- Security Schemes: $SECURITY_COUNT
- Tags: $TAG_COUNT

Servers:
$(yq eval '.servers[].url' "$OPENAPI_FILE" 2>/dev/null | sed 's/^/- /' || echo "- None defined")
EOF
    
    echo "Statistics generated:"
    echo "  Endpoints: $ENDPOINT_COUNT"
    echo "  Operations: $OPERATION_COUNT"
    echo "  Schemas: $SCHEMA_COUNT"
    echo
}

# Function to generate comprehensive report
generate_report() {
    echo -e "${YELLOW}📄 Generating validation report...${NC}"
    
    REPORT_FILE="$REPORT_DIR/validation-report_$TIMESTAMP.md"
    
    cat > "$REPORT_FILE" << EOF
# OpenAPI Validation Report

**Generated:** $(date)  
**OpenAPI File:** $OPENAPI_FILE  
**Validation Tools:** swagger-cli, spectral, openapi-generator-cli  

## Summary

EOF
    
    if [ -f "$REPORT_DIR/statistics_$TIMESTAMP.txt" ]; then
        echo "## API Statistics" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        cat "$REPORT_DIR/statistics_$TIMESTAMP.txt" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        echo >> "$REPORT_FILE"
    fi
    
    echo "## Validation Results" >> "$REPORT_FILE"
    echo >> "$REPORT_FILE"
    
    if [ -f "$REPORT_DIR/linting-results_$TIMESTAMP.txt" ]; then
        echo "### Linting Results" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        cat "$REPORT_DIR/linting-results_$TIMESTAMP.txt" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        echo >> "$REPORT_FILE"
    fi
    
    if [ -f "$REPORT_DIR/security-check_$TIMESTAMP.txt" ]; then
        echo "### Security Check Results" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        cat "$REPORT_DIR/security-check_$TIMESTAMP.txt" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        echo >> "$REPORT_FILE"
    fi
    
    echo -e "${GREEN}✅ Validation report generated: $REPORT_FILE${NC}"
}

# Main execution
main() {
    # Check if OpenAPI file exists
    if [ ! -f "$OPENAPI_FILE" ]; then
        echo -e "${RED}❌ OpenAPI file not found: $OPENAPI_FILE${NC}"
        exit 1
    fi
    
    # Install tools if needed
    install_tools
    
    # Initialize counters
    TOTAL_CHECKS=0
    PASSED_CHECKS=0
    
    # Run validations
    echo -e "${BLUE}🚀 Starting validation process...${NC}"
    echo
    
    # Syntax validation
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if validate_syntax; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
    echo
    
    # Linting
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if run_linting; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
    echo
    
    # Security checks
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if run_security_checks; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
    echo
    
    # Example validation
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if validate_examples; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
    echo
    
    # Generate statistics
    generate_statistics
    
    # Generate report
    generate_report
    
    # Summary
    echo -e "${BLUE}📋 Validation Summary${NC}"
    echo "===================="
    echo "Passed: $PASSED_CHECKS/$TOTAL_CHECKS checks"
    echo "Reports saved in: $REPORT_DIR/"
    echo
    
    if [ "$PASSED_CHECKS" -eq "$TOTAL_CHECKS" ]; then
        echo -e "${GREEN}🎉 All validations passed!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some validations failed${NC}"
        exit 1
    fi
}

# Run main function
main "$@"