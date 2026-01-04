#!/bin/bash
# =============================================================================
# DEBUG TEMPLATE PHASE TESTING SCRIPT
# =============================================================================
# This script helps you test each phase of the debug template incrementally
# to identify which module/pattern causes the flickering bug.
#
# Usage:
#   ./test-debug-phases.sh <phase-number>
#   
# Example:
#   ./test-debug-phases.sh 0    # Test Phase 0 (baseline)
#   ./test-debug-phases.sh 1    # Test Phase 1 (static modules)
#
# After pushing, manually:
# 1. Create/update a workspace from debug-template
# 2. Go to Settings → Parameters
# 3. Watch for flickering (checkboxes toggling, fields changing)
# 4. Document results in templates/debug-template/README.md
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates/debug-template"
PUSH_SCRIPT="$SCRIPT_DIR/push-template-versioned.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[DEBUG]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

PHASE="${1:-}"

if [[ -z "$PHASE" ]]; then
    error "Usage: $0 <phase-number>"
    info "Available phases:"
    info "  0 - Baseline (zero parameters, minimal agent)"
    info "  1 - Static modules (metadata, docker boolean)"
    info "  2 - SSH module (HIGH RISK - conditional count)"
    info "  3 - Setup Server module (HIGH RISK - styling.disabled)"
    info "  4 - Git modules (conditional count)"
    info "  5 - Advanced modules (node, preview-link)"
    exit 1
fi

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "🧪 Testing Debug Template - Phase $PHASE"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

case "$PHASE" in
    0)
        info "Phase 0: Baseline - Zero Parameters"
        info "Expected: NO flickering"
        info "Files: main.tf, variables.tf only"
        info ""
        info "This phase has:"
        info "  ✓ Basic container and agent"
        info "  ✓ Code-server module (zero params)"
        info "  ✓ Static metadata blocks"
        info "  ✗ NO user parameters"
        info "  ✗ NO conditional modules"
        ;;
    1)
        info "Phase 1: Static Modules"
        info "Expected: NO flickering"
        info "Files: + agent-params.tf, metadata-params.tf, docker-params.tf"
        warn ""
        warn "⚠️  Make sure you've added Phase 1 param files before running!"
        warn "    Required files:"
        warn "    - debug-template/agent-params.tf"
        warn "    - debug-template/metadata-params.tf"
        warn "    - debug-template/docker-params.tf"
        ;;
    2)
        info "Phase 2: SSH Module (HIGH RISK)"
        info "Expected: Flickering LIKELY starts here"
        info "Files: + ssh-params.tf (with count conditional)"
        warn ""
        warn "⚠️  CRITICAL TEST - SSH module uses:"
        warn "    module \"ssh\" {"
        warn "      count = data.coder_parameter.ssh_enable.value ? 1 : 0"
        warn "    }"
        warn "    This pattern may cause Terraform to re-evaluate on every render!"
        warn ""
        warn "    Make sure you've added:"
        warn "    - debug-template/ssh-params.tf (copy from template-modules/params/)"
        ;;
    3)
        info "Phase 3: Setup Server Module (HIGH RISK)"
        info "Expected: Flickering LIKELY starts here if not in Phase 2"
        info "Files: + setup-server-params.tf (with styling.disabled)"
        warn ""
        warn "⚠️  CRITICAL TEST - Setup Server uses:"
        warn "    data \"coder_parameter\" \"startup_command\" {"
        warn "      styling = jsonencode({"
        warn "        disabled = !data.coder_parameter.use_custom_command.value"
        warn "      })"
        warn "    }"
        warn "    This pattern may cause re-renders!"
        warn ""
        warn "    Make sure you've added:"
        warn "    - debug-template/setup-server-params.tf"
        ;;
    4)
        info "Phase 4: Git Modules"
        info "Expected: May contribute to flickering"
        info "Files: + git-params.tf"
        ;;
    5)
        info "Phase 5: Advanced Modules"
        info "Expected: Additional flickering possible"
        info "Files: + node-params.tf, node-modules-persistence-params.tf, preview-params.tf"
        ;;
    *)
        error "Unknown phase: $PHASE"
        exit 1
        ;;
esac

log ""
log "Pushing debug-template..."
"$PUSH_SCRIPT" debug-template

log ""
log "✅ Template pushed successfully!"
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "📋 MANUAL TESTING STEPS:"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "1. Go to Coder UI"
log "2. Create a new workspace from 'debug-template' (or update existing)"
log "3. After workspace starts, click Settings (gear icon)"
log "4. Go to Parameters tab"
log "5. WATCH CAREFULLY for:"
log "   - Checkboxes toggling on/off rapidly"
log "   - Text fields changing values"
log "   - Any visual flickering or re-rendering"
log ""
log "6. Document results in:"
log "   templates/debug-template/README.md"
log "   (Look for 'Phase $PHASE Test Results' section)"
log ""
if [[ "$PHASE" -eq 2 ]]; then
    warn "7. Pay special attention to:"
    warn "   ⚠️  SSH Enable checkbox - does it toggle?"
    warn "   ⚠️  SSH Password field - does it appear/disappear?"
fi
if [[ "$PHASE" -eq 3 ]]; then
    warn "7. Pay special attention to:"
    warn "   ⚠️  Use Custom Command toggle - does it flicker?"
    warn "   ⚠️  Startup Command field - does text change?"
fi
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
