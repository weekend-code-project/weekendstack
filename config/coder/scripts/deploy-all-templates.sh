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
PUSH_SCRIPT="$SCRIPT_DIR/push-template-local.sh"
TEMPLATE_INFO_SCRIPT="$SCRIPT_DIR/lib/get-template-info.sh"
CODER_API_SCRIPT="$SCRIPT_DIR/lib/coder-api.sh"

# Load environment variables
if [[ -f "$WORKSPACE_ROOT/.env" ]]; then
    set -a
    source "$WORKSPACE_ROOT/.env"
    set +a
fi

# API Configuration
CODER_URL="${CODER_ACCESS_URL:-http://localhost:7080}"
CODER_TOKEN="${CODER_SESSION_TOKEN:-}"

# Parse arguments
FORCE_REDEPLOY="false"
INTERACTIVE_MODE="false"
SELECTED_TEMPLATES=()

while [[ $# -gt 0 ]]; do
    case $1 in
        force|--force)
            FORCE_REDEPLOY="true"
            shift
            ;;
        --interactive)
            INTERACTIVE_MODE="true"
            shift
            ;;
        --templates)
            IFS=',' read -ra SELECTED_TEMPLATES <<< "$2"
            shift 2
            ;;
        *)
            # Backward compatibility: first arg "force" means force redeploy
            if [[ "$1" == "force" ]]; then
                FORCE_REDEPLOY="true"
            fi
            shift
            ;;
    esac
done

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

# Check if already deployed (unless forced or interactive mode)
if [[ -f "$MARKER_FILE" && "$FORCE_REDEPLOY" != "true" && "$INTERACTIVE_MODE" != "true" ]]; then
    log_info "Templates have already been deployed (marker file exists)"
    
    # Try to parse marker file if it's JSON
    if grep -q "deployment_date" "$MARKER_FILE" 2>/dev/null; then
        local deploy_date=$(grep "deployment_date" "$MARKER_FILE" | cut -d'"' -f4)
        local successful=$(grep '"successful":' "$MARKER_FILE" | grep -o '[0-9]*')
        log_info "Last deployment: $deploy_date ($successful templates)"
    fi
    
    log_info "To force redeployment, delete: $MARKER_FILE"
    log_info "Or run: make redeploy-coder-templates"
    exit 0
fi

# Remove marker if forcing redeployment
if [[ "$FORCE_REDEPLOY" == "true" && -f "$MARKER_FILE" ]]; then
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

# Check for authentication token
if [[ -z "$CODER_TOKEN" ]]; then
    log_error "CODER_SESSION_TOKEN not set in .env"
    echo ""
    log_info "Coder templates require authentication to deploy."
    log_info "Please complete Coder setup:"
    echo ""
    echo "  1. Open: $CODER_URL/cli-auth"
    echo "  2. Create your admin account if needed (first user becomes admin)"
    echo "  3. Copy your session token from the page"
    echo "  4. Add to .env: CODER_SESSION_TOKEN=<your-token>"
    echo ""
    log_info "Or run the setup helper: $CODER_API_SCRIPT setup"
    echo ""
    exit 1
fi

# Test authentication
log_info "Testing Coder authentication..."
if [[ -x "$CODER_API_SCRIPT" ]]; then
    if ! "$CODER_API_SCRIPT" test 2>/dev/null; then
        log_error "Authentication failed"
        log_info "Please verify your CODER_SESSION_TOKEN in .env"
        log_info "You can update it by running: $CODER_API_SCRIPT setup"
        exit 1
    fi
fi
log_success "Authentication successful"
echo ""

# Wait for Coder to be healthy with progress indication
log_info "Waiting for Coder to be healthy (max 120s)..."
timeout=120
elapsed=0
while ! docker exec coder curl -f -s http://localhost:7080/healthz >/dev/null 2>&1; do
    if [ $elapsed -ge $timeout ]; then
        log_error "Timeout waiting for Coder to become healthy"
        log_error "Check Coder logs with: docker logs coder"
        exit 1
    fi
    # Show progress bar
    percent=$((elapsed * 100 / timeout))
    bar_width=30
    filled=$((percent * bar_width / 100))
    if [[ $elapsed -gt 0 ]]; then
        printf "\r"
    fi
    printf "  Progress: ["
    printf "%${filled}s" | tr ' ' '='
    printf "%$((bar_width - filled))s" | tr ' ' ' '
    printf "] %3d%% (%ds / %ds)" "$percent" "$elapsed" "$timeout"
    sleep 5
    elapsed=$((elapsed + 5))
done
printf "\n"
log_success "Coder is healthy and ready"
echo ""

# Discover templates
if [[ ! -d "$TEMPLATES_DIR" ]]; then
    log_error "Templates directory not found: $TEMPLATES_DIR"
    exit 1
fi

# Find all template directories (directories with main.tf files)
all_templates=()
while IFS= read -r template_dir; do
    template_name=$(basename "$template_dir")
    if [[ -f "$template_dir/main.tf" ]]; then
        all_templates+=("$template_name")
    fi
done < <(find "$TEMPLATES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

if [[ ${#all_templates[@]} -eq 0 ]]; then
    log_warning "No templates found in $TEMPLATES_DIR"
    log_info "Templates should be directories containing Terraform files"
    exit 0
fi

# Use selected templates if provided, otherwise use all
if [[ ${#SELECTED_TEMPLATES[@]} -gt 0 ]]; then
    templates=("${SELECTED_TEMPLATES[@]}")
    log_info "Deploying ${#templates[@]} selected template(s)"
else
    templates=("${all_templates[@]}")
    log_info "Found ${#templates[@]} template(s) to deploy"
fi

# Display template info if available
if [[ -x "$TEMPLATE_INFO_SCRIPT" ]]; then
    "$TEMPLATE_INFO_SCRIPT" display
else
    for template in "${templates[@]}"; do
        echo "  - $template"
    done
fi
echo ""

# Interactive confirmation if in interactive mode
if [[ "$INTERACTIVE_MODE" == "true" ]]; then
    read -p "Proceed with deployment? [Y/n]: " -r response
    case "$response" in
        [nN][oO]|[nN])
            log_info "Deployment cancelled by user"
            exit 0
            ;;
        *)
            log_info "Starting deployment..."
            echo ""
            ;;
    esac
fi

# Deploy each template
success_count=0
failure_count=0
failed_templates=()
successful_templates=()
total_templates=${#templates[@]}
current=0

for template in "${templates[@]}"; do
    ((current++)) || true
    log_info "📤 Deploying template $current/$total_templates: $template"
    
    if [[ ! -x "$PUSH_SCRIPT" ]]; then
        log_error "Push script not executable: $PUSH_SCRIPT"
        log_info "Run: chmod +x $PUSH_SCRIPT"
        failed_templates+=("$template:script not executable")
        ((failure_count++)) || true
        continue
    fi
    
    # Run push script with session token
    if CODER_SESSION_TOKEN="$CODER_TOKEN" "$PUSH_SCRIPT" "$template" 2>&1 | sed 's/^/  /'; then
        log_success "Successfully deployed: $template"
        successful_templates+=("$template:success")
        ((success_count++)) || true
    else
        log_error "Failed to deploy: $template"
        failed_templates+=("$template:deployment failed")
        ((failure_count++)) || true
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

# Create JSON marker file on completion (even with some failures)
if [[ $success_count -gt 0 ]]; then
    cat > "$MARKER_FILE" <<EOF
{
  "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "total": $total_templates,
  "successful": $success_count,
  "failed": $failure_count,
  "templates": {
EOF
    
    # Add successful templates
    first=true
    for entry in "${successful_templates[@]}"; do
        template_name="${entry%%:*}"
        if [[ "$first" == "false" ]]; then
            echo "," >> "$MARKER_FILE"
        fi
        first=false
        echo -n "    \"$template_name\": {\"status\": \"success\"}" >> "$MARKER_FILE"
    done
    
    # Add failed templates
    for entry in "${failed_templates[@]}"; do
        template_name="${entry%%:*}"
        error_msg="${entry#*:}"
        if [[ "$first" == "false" ]]; then
            echo "," >> "$MARKER_FILE"
        fi
        first=false
        echo -n "    \"$template_name\": {\"status\": \"failed\", \"error\": \"$error_msg\"}" >> "$MARKER_FILE"
    done
    
    cat >> "$MARKER_FILE" <<EOF

  }
}
EOF
    
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
