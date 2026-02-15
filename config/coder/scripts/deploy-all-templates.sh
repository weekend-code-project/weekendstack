#!/bin/bash
# Auto-deploy all Coder templates on first-time setup
# Discovers templates in config/coder/templates/ and pushes them using push-template-versioned.sh

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory and workspace root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEMPLATES_DIR="$WORKSPACE_ROOT/config/coder/templates"
MARKER_FILE="$WORKSPACE_ROOT/config/coder/.template_deployment_complete"
PUSH_SCRIPT="$SCRIPT_DIR/push-template-versioned.sh"

# Check if this is a forced redeployment
FORCE_REDEPLOY="${1:-false}"

log_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if already deployed (unless forced)
if [[ -f "$MARKER_FILE" && "$FORCE_REDEPLOY" != "force" ]]; then
    log_info "Templates have already been deployed (marker file exists)"
    log_info "To force redeployment, delete: $MARKER_FILE"
    log_info "Or run: make redeploy-coder-templates"
    exit 0
fi

# Remove marker if forcing redeployment
if [[ "$FORCE_REDEPLOY" == "force" && -f "$MARKER_FILE" ]]; then
    log_info "Forcing redeployment - removing marker file"
    rm -f "$MARKER_FILE"
fi

echo ""
log_info "🚀 Starting Coder template deployment..."
echo ""

# Check if Coder container exists
if ! docker ps -a --format '{{.Names}}' | grep -q '^coder$'; then
    log_error "Coder container not found. Start dev services first with: docker compose -f compose/docker-compose.dev.yml up -d"
    exit 1
fi

# Check if Coder container is running
if ! docker ps --format '{{.Names}}' | grep -q '^coder$'; then
    log_error "Coder container is not running. Start it with: docker compose -f compose/docker-compose.dev.yml up -d"
    exit 1
fi

# Wait for Coder to be healthy
log_info "Waiting for Coder to be healthy (max 120s)..."
timeout=120
elapsed=0
while ! docker exec coder curl -f -s http://localhost:7080/healthz >/dev/null 2>&1; do
    if [ $elapsed -ge $timeout ]; then
        log_error "Timeout waiting for Coder to become healthy"
        log_error "Check Coder logs with: docker logs coder"
        exit 1
    fi
    echo -n "."
    sleep 5
    elapsed=$((elapsed + 5))
done
echo ""
log_success "Coder is healthy and ready"
echo ""

# Discover templates
if [[ ! -d "$TEMPLATES_DIR" ]]; then
    log_error "Templates directory not found: $TEMPLATES_DIR"
    exit 1
fi

# Find all template directories (directories with main.tf files)
templates=()
while IFS= read -r template_dir; do
    template_name=$(basename "$template_dir")
    templates+=("$template_name")
done < <(find "$TEMPLATES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

if [[ ${#templates[@]} -eq 0 ]]; then
    log_warning "No templates found in $TEMPLATES_DIR"
    log_info "Templates should be directories containing Terraform files"
    exit 0
fi

log_info "Found ${#templates[@]} template(s) to deploy:"
for template in "${templates[@]}"; do
    echo "  - $template"
done
echo ""

# Deploy each template
success_count=0
failure_count=0
failed_templates=()

for template in "${templates[@]}"; do
    log_info "📤 Deploying template: $template"
    
    if [[ ! -x "$PUSH_SCRIPT" ]]; then
        log_error "Push script not executable: $PUSH_SCRIPT"
        log_info "Run: chmod +x $PUSH_SCRIPT"
        failed_templates+=("$template (script not executable)")
        ((failure_count++))
        continue
    fi
    
    # Run push script and capture output
    if "$PUSH_SCRIPT" "$template" 2>&1 | sed 's/^/  /'; then
        log_success "Successfully deployed: $template"
        ((success_count++))
    else
        log_error "Failed to deploy: $template"
        failed_templates+=("$template")
        ((failure_count++))
    fi
    echo ""
done

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Deployment Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Successful: $success_count"
if [[ $failure_count -gt 0 ]]; then
    log_error "Failed: $failure_count"
    for failed in "${failed_templates[@]}"; do
        echo "  - $failed"
    done
fi
echo ""

# Create marker file on completion (even with some failures)
if [[ $success_count -gt 0 ]]; then
    echo "Deployment completed on $(date)" > "$MARKER_FILE"
    echo "Deployed $success_count template(s)" >> "$MARKER_FILE"
    if [[ $failure_count -gt 0 ]]; then
        echo "Failed to deploy $failure_count template(s): ${failed_templates[*]}" >> "$MARKER_FILE"
    fi
    log_success "Marker file created: $MARKER_FILE"
    log_info "Templates won't be auto-deployed on next setup.sh run"
fi

if [[ $failure_count -gt 0 ]]; then
    log_warning "Some templates failed to deploy. Check logs above for details."
    log_info "To retry failed templates, fix issues and run: make redeploy-coder-templates"
else
    log_success "🎉 All templates deployed successfully!"
fi

echo ""
log_info "View templates in Coder: docker exec coder coder templates list"
echo ""

# Exit 0 even with failures (best-effort deployment)
exit 0
