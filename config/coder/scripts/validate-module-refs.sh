#!/bin/bash
# =============================================================================
# VALIDATE MODULE REFERENCES
# =============================================================================
# Validates that all module references use correct paths and ref patterns.
# Run this before pushing templates to ensure consistency.
#
# Usage:
#   ./validate-module-refs.sh
#
# Exit codes:
#   0 - All validations passed
#   1 - Validation errors found
# =============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

ERRORS=0
WARNINGS=0

echo ""
info "🔍 Validating module references in template system..."
echo ""

# =============================================================================
# Check 1: Old path references (templates/git-modules)
# =============================================================================
info "Check 1: Looking for old path 'templates/git-modules'..."

if grep -r "templates/git-modules" templates/ template-modules/ --include="*.tf" --include="*.md" 2>/dev/null | grep -v "_trash" | grep -v ".git"; then
    error "Found old path 'templates/git-modules' - should be 'template-modules/modules'"
    ERRORS=$((ERRORS + 1))
else
    log "No old path references found"
fi

# =============================================================================
# Check 2: Hardcoded version refs in active templates
# =============================================================================
info "Check 2: Looking for hardcoded ?ref=v0.x.x (should be PLACEHOLDER)..."

HARDCODED=$(grep -r "?ref=v0\\.1\\.[0-9]" templates/ template-modules/params/ --include="*.tf" 2>/dev/null | grep -v debug-template | grep -v "_trash" || true)

if [[ -n "$HARDCODED" ]]; then
    warn "Found hardcoded version refs (consider using ?ref=PLACEHOLDER):"
    echo "$HARDCODED"
    WARNINGS=$((WARNINGS + 1))
else
    log "No hardcoded version refs found (outside debug-template)"
fi

# =============================================================================
# Check 3: Mixed placeholder patterns
# =============================================================================
info "Check 3: Looking for inconsistent placeholder patterns..."

if grep -r "?ref={{GIT_REF}}" templates/ template-modules/ --include="*.tf" 2>/dev/null; then
    warn "Found {{GIT_REF}} pattern - push script uses PLACEHOLDER"
    WARNINGS=$((WARNINGS + 1))
else
    log "No inconsistent placeholder patterns found"
fi

# =============================================================================
# Check 4: Module path consistency
# =============================================================================
info "Check 4: Verifying module paths use template-modules/modules..."

WRONG_PATHS=$(grep -r "source.*weekendstack.git//" templates/ template-modules/params/ --include="*.tf" 2>/dev/null | \
    grep -v "template-modules/modules" | \
    grep -v "_trash" | \
    grep -v ".git" || true)

if [[ -n "$WRONG_PATHS" ]]; then
    error "Found module references not using template-modules/modules:"
    echo "$WRONG_PATHS"
    ERRORS=$((ERRORS + 1))
else
    log "All module paths use template-modules/modules"
fi

# =============================================================================
# Check 5: README examples consistency
# =============================================================================
info "Check 5: Checking module README examples..."

README_ISSUES=0
for readme in $(find template-modules/modules -name "README.md" -type f); do
    if grep -q "templates/git-modules" "$readme"; then
        error "Old path in README: $readme"
        README_ISSUES=$((README_ISSUES + 1))
    fi
    if grep -q "?ref=v0\\.1\\.[0-9]" "$readme"; then
        warn "Hardcoded version in README: $readme (should use PLACEHOLDER)"
        README_ISSUES=$((README_ISSUES + 1))
    fi
done

if [[ $README_ISSUES -eq 0 ]]; then
    log "All module READMEs use correct paths and patterns"
else
    ERRORS=$((ERRORS + README_ISSUES))
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    log "✅ All validations passed!"
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    warn "⚠️  Validation complete with $WARNINGS warning(s)"
    warn "Warnings are non-critical but should be reviewed"
    exit 0
else
    error "❌ Validation failed with $ERRORS error(s) and $WARNINGS warning(s)"
    error "Please fix errors before pushing templates"
    exit 1
fi
