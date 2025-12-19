#!/bin/bash
# Pre-deployment verification script
# Checks that everything is configured correctly before running terraform apply

set -e

echo "========================================"
echo "Palworld Server - Pre-Deployment Check"
echo "========================================"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

# Check Terraform installed
echo -n "Checking Terraform installation... "
if command -v terraform &> /dev/null; then
    VERSION=$(terraform --version | head -n1)
    echo -e "${GREEN}✓${NC} $VERSION"
else
    echo -e "${RED}✗${NC} Terraform not installed"
    echo "  Install from: https://www.terraform.io/downloads"
    ERRORS=$((ERRORS + 1))
fi

# Check AWS CLI installed (optional)
echo -n "Checking AWS CLI installation... "
if command -v aws &> /dev/null; then
    VERSION=$(aws --version 2>&1 | cut -d' ' -f1)
    echo -e "${GREEN}✓${NC} $VERSION"
else
    echo -e "${YELLOW}⚠${NC} AWS CLI not installed (optional but recommended)"
    WARNINGS=$((WARNINGS + 1))
fi

# Check .env file exists
echo -n "Checking .env file exists... "
if [ -f ".env" ]; then
    echo -e "${GREEN}✓${NC} Found"

    # Check if credentials are loaded
    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        echo -e "${YELLOW}⚠${NC} AWS credentials not loaded. Run: source .env"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${RED}✗${NC} .env file not found"
    ERRORS=$((ERRORS + 1))
fi

# Check terraform.tfvars exists
echo -n "Checking terraform.tfvars exists... "
if [ -f "terraform.tfvars" ]; then
    echo -e "${GREEN}✓${NC} Found"

    # Check that passwords are not manually set (they should be auto-generated)
    if grep -q "palworld_server_password\s*=" terraform.tfvars; then
        echo -e "${YELLOW}⚠${NC} Manual password detected - passwords should be auto-generated"
        echo "  Remove password lines from terraform.tfvars - they're generated automatically!"
        WARNINGS=$((WARNINGS + 1))
    fi

    if grep -q "palworld_admin_password\s*=" terraform.tfvars; then
        echo -e "${YELLOW}⚠${NC} Manual admin password detected - passwords should be auto-generated"
        echo "  Remove password lines from terraform.tfvars - they're generated automatically!"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${RED}✗${NC} terraform.tfvars not found"
    echo "  Copy from terraform.tfvars.example"
    ERRORS=$((ERRORS + 1))
fi

# Check required files exist
echo -n "Checking Terraform files... "
REQUIRED_FILES=(
    "main.tf"
    "variables.tf"
    "outputs.tf"
    "compute.tf"
    "network.tf"
    "storage.tf"
    "iam.tf"
    "monitoring.tf"
    "user-data.sh"
    "lambda/volume_attachment.py"
    "lambda/spot_interruption.py"
)

MISSING=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}✗${NC} Missing: $file"
        MISSING=$((MISSING + 1))
    fi
done

if [ $MISSING -eq 0 ]; then
    echo -e "${GREEN}✓${NC} All files present"
else
    ERRORS=$((ERRORS + MISSING))
fi

# Validate Terraform syntax
echo -n "Validating Terraform configuration... "
if terraform validate &> /dev/null; then
    echo -e "${GREEN}✓${NC} Configuration valid"
else
    echo -e "${RED}✗${NC} Configuration has errors"
    echo "  Run: terraform validate"
    ERRORS=$((ERRORS + 1))
fi

# Check AWS credentials
if [ ! -z "$AWS_ACCESS_KEY_ID" ]; then
    echo -n "Checking AWS credentials... "
    if aws sts get-caller-identity &> /dev/null 2>&1; then
        ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        echo -e "${GREEN}✓${NC} Valid (Account: $ACCOUNT)"
    else
        echo -e "${RED}✗${NC} Invalid or expired credentials"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Estimate costs
echo ""
echo "========================================"
echo "Cost Estimate (us-west-1, 24/7 runtime)"
echo "========================================"
echo "EC2 Spot t3.xlarge:     ~\$40/month"
echo "EBS 50GB gp3:           ~\$4.80/month"
echo "S3 storage:             ~\$1/month"
echo "Elastic IP (attached):  \$0/month"
echo "----------------------------------------"
echo "TOTAL:                  ~\$46/month"
echo ""
echo "Your \$100 credits will last: ~2.2 months"
echo ""

# Summary
echo "========================================"
echo "Summary"
echo "========================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "Ready to deploy! Next steps:"
    echo "  1. source .env"
    echo "  2. terraform init"
    echo "  3. terraform plan"
    echo "  4. terraform apply"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
    echo ""
    echo "You can proceed, but review warnings above."
else
    echo -e "${RED}✗ $ERRORS error(s) found${NC}"
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
    fi
    echo ""
    echo "Fix errors before deploying!"
    exit 1
fi

echo "========================================"
