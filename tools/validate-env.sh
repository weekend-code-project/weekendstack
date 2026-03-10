#!/bin/bash
# ============================================================================
# validate-env.sh - Validate .env Configuration
# ============================================================================
# This script checks your .env file for common issues:
#   - Weak or placeholder passwords
#   - Empty required fields
#   - Invalid values
#   - Security concerns
#   - Profile-aware validation (only validates enabled services)
#
# Usage:
#   ./tools/validate-env.sh [--strict]
#
# Options:
#   --strict    Validate all variables (ignore profile selection)
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
STRICT_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --strict)
            STRICT_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: ./tools/validate-env.sh [--strict]"
            exit 1
            ;;
    esac
done

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

# Get selected profiles
SELECTED_PROFILES=$(grep "^SELECTED_PROFILES=" .env | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')

if [ "$STRICT_MODE" = true ]; then
    echo -e "${YELLOW}⚙️  Mode: STRICT (validating all variables)${NC}"
elif [ -n "$SELECTED_PROFILES" ]; then
    echo -e "${BLUE}📦 Selected Profiles: $SELECTED_PROFILES${NC}"
    echo -e "${GREEN}⚙️  Mode: Profile-aware (validating only enabled services)${NC}"
else
    echo -e "${YELLOW}⚠ No SELECTED_PROFILES found - validating all variables${NC}"
    STRICT_MODE=true
fi
echo ""

# ============================================================================
# Check for placeholder/weak passwords and empty required fields
# ============================================================================
echo -e "${BLUE}🔐 Checking passwords and required fields...${NC}"

WEAK_PATTERNS=(
    "CHANGEME"
    "changeme"
    "password"
    "Password"
    "12345"
    "admin123"
)

for pattern in "${WEAK_PATTERNS[@]}"; do
    if grep -E "^[A-Z_]*(PASSWORD|PASS|SECRET).*$pattern" .env >/dev/null 2>&1; then
        echo -e "${RED}  ✗ Placeholder/weak password detected: $pattern${NC}"
        ERRORS=$((ERRORS + 1))
    fi
done

REQUIRED_VARS=(
    "HOST_IP"
    "DEFAULT_ADMIN_PASSWORD"
    "DEFAULT_DB_PASS"
    "DEFAULT_JWT_SECRET"
    "DEFAULT_TRAEFIK_AUTH_PASS"
)

for var in "${REQUIRED_VARS[@]}"; do
    VALUE=$(grep "^${var}=" .env | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ')
    if [ -z "$VALUE" ]; then
        echo -e "${RED}  ✗ Required field is empty: $var${NC}"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}  ✓ No placeholder passwords or missing required fields${NC}"
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
if [ -z "$FILES_BASE_DIR" ]; then
    echo -e "${YELLOW}  ⚠ FILES_BASE_DIR is not set${NC}"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "${GREEN}  ✓ FILES_BASE_DIR: $FILES_BASE_DIR${NC}"
fi
echo ""

# ============================================================================
# Check for common mistakes
# ============================================================================
echo -e "${BLUE}⚙️  Checking for common mistakes...${NC}"

# Check if NFS paths are active when FILES_BASE_DIR is local
if [[ "$FILES_BASE_DIR" == "./files" ]]; then
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

# Check password lengths (informational only)
while IFS= read -r line; do
    if [[ $line =~ ^[A-Z_]+PASSWORD=(.+)$ ]] || \
       [[ $line =~ ^[A-Z_]+_PASS=(.+)$ ]] || \
       [[ $line =~ ^[A-Z_]+SECRET=(.+)$ ]]; then
        VALUE="${BASH_REMATCH[1]}"
        VALUE=$(echo "$VALUE" | sed 's/#.*//' | tr -d ' ')
        if [ -n "$VALUE" ] && [ ${#VALUE} -lt 16 ]; then
            VAR=$(echo "$line" | cut -d'=' -f1)
            echo -e "${YELLOW}  ⚠ Short password (< 16 chars): $VAR${NC}"
        fi
    fi
done < .env

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
# Check Cloudflare Tunnel Configuration
# ============================================================================
echo -e "${BLUE}🌐 Checking Cloudflare Tunnel configuration...${NC}"

CF_ENABLED=$(grep "^CLOUDFLARE_TUNNEL_ENABLED=" .env | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
CF_TUNNEL_ID=$(grep "^CLOUDFLARE_TUNNEL_ID=" .env | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
CF_API_TOKEN=$(grep "^CLOUDFLARE_API_TOKEN=" .env | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
CF_CONFIG_FILE=$(grep "^CLOUDFLARE_CONFIG_FILE=" .env | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')

if [[ "$CF_ENABLED" == "true" ]]; then
    # Check tunnel ID is set
    if [[ -z "$CF_TUNNEL_ID" ]]; then
        echo -e "${RED}  ✗ CLOUDFLARE_TUNNEL_ENABLED is true but CLOUDFLARE_TUNNEL_ID is empty${NC}"
        ERRORS=$((ERRORS + 1))
    fi

    # Check config file exists
    if [[ -n "$CF_CONFIG_FILE" ]] && [[ ! -f "$CF_CONFIG_FILE" ]]; then
        echo -e "${YELLOW}  ⚠ Cloudflare config file not found: $CF_CONFIG_FILE${NC}"
        echo "    Run setup to create tunnel configuration"
        WARNINGS=$((WARNINGS + 1))
    fi

    # Check credentials file exists (if tunnel ID is set)
    if [[ -n "$CF_TUNNEL_ID" ]]; then
        CF_CREDS_DIR=$(grep "^CLOUDFLARE_CREDENTIALS_DIR=" .env | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
        if [[ -n "$CF_CREDS_DIR" ]] && [[ ! -f "$CF_CREDS_DIR/$CF_TUNNEL_ID.json" ]]; then
            echo -e "${YELLOW}  ⚠ Cloudflare credentials file not found: $CF_CREDS_DIR/$CF_TUNNEL_ID.json${NC}"
            echo "    Run setup to configure tunnel credentials"
            WARNINGS=$((WARNINGS + 1))
        elif [[ -n "$CF_CREDS_DIR" ]] && [[ -f "$CF_CREDS_DIR/$CF_TUNNEL_ID.json" ]]; then
            echo -e "${GREEN}  ✓ Cloudflare credentials file found${NC}"
        fi
    fi

    echo -e "${GREEN}  ✓ Cloudflare Tunnel configuration validated${NC}"
elif [[ -n "$CF_API_TOKEN" ]]; then
    # API token is set — test actual connectivity to Cloudflare
    # Account-scoped tokens fail the user endpoint; fall back to accounts endpoint.
    echo -e "${BLUE}  ℹ Testing Cloudflare API connectivity...${NC}"
    _cf_token_ok=false
    CF_VERIFY_RESPONSE=$(curl -s --max-time 5 \
        "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CF_API_TOKEN" 2>/dev/null)
    if echo "$CF_VERIFY_RESPONSE" | grep -q '"success":true'; then
        _cf_token_ok=true
    else
        # Try accounts endpoint (account-scoped tokens only validate here)
        CF_ACCT_RESPONSE=$(curl -s --max-time 5 \
            "https://api.cloudflare.com/client/v4/accounts" \
            -H "Authorization: Bearer $CF_API_TOKEN" 2>/dev/null)
        if echo "$CF_ACCT_RESPONSE" | grep -q '"success":true'; then
            _cf_token_ok=true
        fi
    fi
    if $_cf_token_ok; then
        echo -e "${GREEN}  ✓ Cloudflare API token valid — run setup to configure tunnel${NC}"
    else
        echo -e "${RED}  ✗ Cloudflare API token invalid or unreachable${NC}"
        echo "    Check your token at: https://dash.cloudflare.com/profile/api-tokens"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${BLUE}  ℹ Cloudflare Tunnel not enabled (services will be local-only)${NC}"
fi
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
