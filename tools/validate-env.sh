#!/bin/bash
# ============================================================================
# validate-env.sh - Validate .env Configuration
# ============================================================================
# This script checks your .env file for common issues:
#   - Weak or placeholder passwords
#   - Empty required fields  
#   - Invalid values
#   - Security concerns
#
# Usage:
#   ./tools/validate-env.sh
#
# Exit codes:
#   0 = All checks passed
#   1 = Validation errors found
# ============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

echo "============================================================================"
echo "  WeekendStack - Configuration Validator"
echo "============================================================================"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${RED}✗ .env file not found!${NC}"
    echo "  Run: ./tools/env-template-gen.sh to create one"
    exit 1
fi

echo "📋 Checking .env configuration..."
echo ""

# ============================================================================
# Check for weak passwords
# ============================================================================
echo -e "${BLUE}🔐 Checking for weak passwords...${NC}"

WEAK_PATTERNS=(
    "CHANGEME"
    "changeme"
    "password"
    "Password"
    "12345"
    "admin123"
    "test"
    "demo"
    "example"
)

for pattern in "${WEAK_PATTERNS[@]}"; do
    # Only check actual variable assignments, not comments
    if grep -E "^[A-Z_]*(PASSWORD|PASS|SECRET).*$pattern" .env >/dev/null 2>&1; then
        echo -e "${RED}  ✗ Weak password detected: $pattern${NC}"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}  ✓ No weak passwords found${NC}"
fi
echo ""

# ============================================================================
# Check for empty required fields
# ============================================================================
echo -e "${BLUE}🔍 Checking for empty required fields...${NC}"

REQUIRED_VARS=(
    "HOST_IP"
    "DEFAULT_ADMIN_PASSWORD"
    "DEFAULT_DB_PASS"
    "DEFAULT_JWT_SECRET"
    "DEFAULT_TRAEFIK_AUTH_PASS"
)

EMPTY_REQUIRED=0
for var in "${REQUIRED_VARS[@]}"; do
    # Extract value and strip comments before processing
    VALUE=$(grep "^${var}=" .env | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ')
    if [ -z "$VALUE" ]; then
        echo -e "${RED}  ✗ Required field is empty: $var${NC}"
        EMPTY_REQUIRED=$((EMPTY_REQUIRED + 1))
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $EMPTY_REQUIRED -eq 0 ]; then
    echo -e "${GREEN}  ✓ All required fields are set${NC}"
fi
echo ""

# ============================================================================
# Check password strength (length)
# ============================================================================
echo -e "${BLUE}🔒 Checking password strength...${NC}"

SHORT_PASSWORDS=0
while IFS= read -r line; do
    if [[ $line =~ ^[A-Z_]+PASSWORD=(.+)$ ]] || \
       [[ $line =~ ^[A-Z_]+_PASS=(.+)$ ]] || \
       [[ $line =~ ^[A-Z_]+SECRET=(.+)$ ]]; then
        
        VALUE="${BASH_REMATCH[1]}"
        VALUE=$(echo "$VALUE" | sed 's/#.*//' | tr -d ' ')
        
        if [ -n "$VALUE" ] && [ ${#VALUE} -lt 16 ]; then
            VAR=$(echo "$line" | cut -d'=' -f1)
            echo -e "${YELLOW}  ⚠ Short password (< 16 chars): $VAR${NC}"
            SHORT_PASSWORDS=$((SHORT_PASSWORDS + 1))
            WARNINGS=$((WARNINGS + 1))
        fi
    fi
done < .env

if [ $SHORT_PASSWORDS -eq 0 ]; then
    echo -e "${GREEN}  ✓ All passwords meet minimum length${NC}"
fi
echo ""

# ============================================================================
# Check for placeholder values
# ============================================================================
echo -e "${BLUE}📝 Checking for placeholder values...${NC}"

PLACEHOLDERS=0
if grep -q "<GENERATE>" .env; then
    echo -e "${RED}  ✗ Found <GENERATE> placeholders - secrets not generated${NC}"
    echo "    Run: ./tools/env-template-gen.sh"
    PLACEHOLDERS=$((PLACEHOLDERS + 1))
    ERRORS=$((ERRORS + 1))
fi

if grep -q "example.com" .env && ! grep -q "#.*example.com" .env; then
    VALUE=$(grep "^DEFAULT_ADMIN_EMAIL=" .env | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    if [ "$VALUE" = "admin@example.com" ]; then
        echo -e "${YELLOW}  ⚠ DEFAULT_ADMIN_EMAIL still set to example.com${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

if [ $PLACEHOLDERS -eq 0 ]; then
    echo -e "${GREEN}  ✓ No placeholder values found${NC}"
fi
echo ""

# ============================================================================
# Check file paths
# ============================================================================
echo -e "${BLUE}📁 Checking file paths...${NC}"

FILES_BASE_DIR=$(grep "^FILES_BASE_DIR=" .env | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
if [ "$FILES_BASE_DIR" != "./files" ]; then
    echo -e "${YELLOW}  ⚠ FILES_BASE_DIR is set to: $FILES_BASE_DIR${NC}"
    echo "    Recommended: Start with ./files for initial testing"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "${GREEN}  ✓ FILES_BASE_DIR set to ./files (recommended for testing)${NC}"
fi
echo ""

# ============================================================================
# Check for common mistakes
# ============================================================================
echo -e "${BLUE}⚙️  Checking for common mistakes...${NC}"

# Check if NFS paths are active when FILES_BASE_DIR is local
if [ "$FILES_BASE_DIR" = "./files" ]; then
    if grep "^NFS_SERVER_IP=" .env | grep -v "^#" >/dev/null 2>&1; then
        echo -e "${YELLOW}  ⚠ NFS variables active but FILES_BASE_DIR is local${NC}"
        echo "    Comment out NFS variables if using local files"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# Check HOST_IP format
HOST_IP=$(grep "^HOST_IP=" .env | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
if ! [[ $HOST_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo -e "${RED}  ✗ HOST_IP format invalid: $HOST_IP${NC}"
    echo "    Expected: xxx.xxx.xxx.xxx"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}  ✓ HOST_IP format valid${NC}"
fi

# Check timezone format
TZ=$(grep "^TZ=" .env | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
if [ -z "$TZ" ]; then
    echo -e "${YELLOW}  ⚠ TZ (timezone) not set${NC}"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "${GREEN}  ✓ Timezone set: $TZ${NC}"
fi

echo ""

# ============================================================================
# Security recommendations
# ============================================================================
echo -e "${BLUE}🛡️  Security recommendations:${NC}"

# Check if default admin password is actually set
DEFAULT_ADMIN_PASS=$(grep "^DEFAULT_ADMIN_PASSWORD=" .env | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
if [ ${#DEFAULT_ADMIN_PASS} -lt 32 ]; then
    echo -e "${YELLOW}  ⚠ Consider using longer passwords (32+ chars)${NC}"
fi

# Check signups
if grep "SIGNUPS_ALLOWED=true" .env >/dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠ Some services have signups enabled${NC}"
    echo "    Disable after creating your accounts for better security"
fi

echo -e "${GREEN}  ✓ Review Section 15 in .env for first-time setup guide${NC}"
echo ""

# ============================================================================
# Summary
# ============================================================================
echo "============================================================================"
echo "  VALIDATION SUMMARY"
echo "============================================================================"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Configuration looks good.${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review Section 15 in .env for services requiring setup"
    echo "  2. Deploy: docker compose --profile all up -d"
    echo "  3. Complete first-time setup for each service"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Configuration has $WARNINGS warning(s)${NC}"
    echo ""
    echo "These are not critical, but should be reviewed."
    echo "You can proceed with deployment if desired."
    exit 0
else
    echo -e "${RED}✗ Configuration has $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo "Please fix the errors above before deploying."
    exit 1
fi
