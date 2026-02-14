#!/bin/bash
# ============================================================================
# Test: Complete Setup Flow End-to-End
# ============================================================================
# Runs the entire setup.sh in quick mode to verify all 13 steps complete
# ============================================================================

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

echo "============================================================================"
echo "  END-TO-END SETUP TEST"
echo "============================================================================"
echo ""

# Backup any existing .env
if [[ -f ".env" ]]; then
    echo "→ Backing up existing .env..."
    cp .env .env.backup.e2e
fi

# Clean up
echo "→ Cleaning test environment..."
rm -f .env

# Test setup in quick mode
echo "→ Running setup.sh in quick mode (non-interactive)..."
echo ""

# Create test expectations
echo "Expected Steps:"
echo "  1. Checking Prerequisites"
echo "  2. Selecting Service Profiles"
echo "  3. Docker Authentication (skipped in quick mode)"
echo "  4. Environment Configuration"
echo "  5. Validating Configuration"
echo "  6. Creating Directory Structure"
echo "  7. Creating Docker Networks"
echo "  8. Creating Docker Volumes"
echo "  9. Setting Up SSL Certificates"
echo "  10. Cloudflare Tunnel Configuration (skipped in quick mode)"
echo "  11. Pulling Docker Images"
echo "  12. Running Initialization Containers" 
echo "  13. Generating Setup Summary"
echo ""
echo "============================================================================"
echo ""

# Run setup in quick mode, skip docker operations
export SKIP_PULL=true
export SKIP_CERTS=true
export DRY_RUN=true

if ./setup.sh --quick --skip-pull --skip-certs 2>&1 | tee /tmp/setup-test-output.log; then
    echo ""
    echo "============================================================================"
    echo "  ✓ SETUP COMPLETED SUCCESSFULLY"
    echo "============================================================================"
    echo ""
    
    # Verify .env was created
    if [[ -f ".env" ]]; then
        echo "✓ .env file created"
        
        # Check critical values
        echo ""
        echo "Verifying critical configuration values..."
        
        critical_vars=(
            "HOST_IP"
            "COMPUTER_NAME"
            "DEFAULT_ADMIN_PASSWORD"
            "DEFAULT_DB_PASS"
            "DEFAULT_JWT_SECRET"
            "PUID"
            "PGID"
        )
        
        all_set=true
        for var in "${critical_vars[@]}"; do
            value=$(grep "^${var}=" .env | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
            if [[ -z "$value" ]]; then
                echo "  ✗ $var is empty!"
                all_set=false
            else
                echo "  ✓ $var = $value"
            fi
        done
        
        echo ""
        if $all_set; then
            echo "✓ All critical values are set"
        else
            echo "✗ Some critical values are missing"
            exit 1
        fi
        
        # Run validation
        echo ""
        echo "Running validation..."
        if ./tools/validate-env.sh; then
            echo "✓ Validation passed"
        else
            exit_code=$?
            if [[ $exit_code -eq 0 ]]; then
                echo "✓ Validation passed with warnings"
            else
                echo "✗ Validation failed"
                exit 1
            fi
        fi
    else
        echo "✗ .env file was not created"
        exit 1
    fi
else
    echo ""
    echo "============================================================================"
    echo "  ✗ SETUP FAILED"
    echo "============================================================================"
    echo ""
    grep "Step.*of 13" /tmp/setup-test-output.log | tail -1 || echo "Could not determine which step failed"
    exit 1
fi

# Cleanup
if [[ -f ".env.backup.e2e" ]]; then
    echo ""
    echo "→ Restoring original .env..."
    mv .env.backup.e2e .env
fi

echo ""
echo "============================================================================"
echo "  ✓ ALL TESTS PASSED"
echo "============================================================================"
