#!/bin/bash
# WeekendStack Interactive Setup Script
# Automated deployment with interactive customization

set -e

# If stdin is not an interactive terminal (e.g. run via curl | sudo bash),
# reopen it from /dev/tty so that all interactive prompts work correctly.
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
    exec < /dev/tty
fi

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# Load library functions
for lib in "$SCRIPT_DIR/tools/setup/lib"/*.sh; do
    if [[ -f "$lib" ]]; then
        source "$lib"
    fi
done

# Version
VERSION="1.0.0"

# Global flags
SETUP_MODE="interactive"  # interactive or quick
SKIP_AUTH=false
SKIP_PULL=false
SKIP_CLOUDFLARE=false
SKIP_CERTS=false
DRY_RUN=false
FORCE_RECONFIGURE=false

# Show usage
show_usage() {
    cat << EOF
WeekendStack Setup Script v$VERSION

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -v, --version           Show version information
    -q, --quick             Quick setup with defaults (non-interactive)
    -i, --interactive       Interactive setup (default)
    --skip-auth             Skip Docker registry authentication
    --skip-pull             Skip image pulling
    --skip-cloudflare       Skip Cloudflare Tunnel setup
    --skip-certs            Skip certificate generation
    --reconfigure           Force full configuration wizard (ignore existing .env)
    --dry-run               Show what would be done without executing
    --validate              Validate configuration without starting services
    --status                Show current deployment status
    --rollback              Restore previous .env from backup
    --cloudflare-only       Run only the Cloudflare Tunnel setup wizard
    --certs-only            Run only certificate generation and CA installation
    --docker-only           Run only Docker registry authentication
    --start                 Start the stack after setup
    --stop                  Stop all services
    --restart               Restart all services

EXAMPLES:
    # Interactive setup (recommended for first-time)
    $0

    # Quick setup with defaults
    $0 --quick

    # Add more services to existing setup
    $0
    # (Detects existing .env and only updates profiles)

    # Reconfigure everything from scratch
    $0 --reconfigure

    # Setup without Cloudflare
    $0 --skip-cloudflare

    # Validate configuration
    $0 --validate

    # Start services
    $0 --start

DOCUMENTATION:
    See docs/setup-script-guide.md for detailed instructions
    See SETUP_SUMMARY.md (after setup) for service URLs and credentials

EOF
}

# Show version
show_version() {
    echo "WeekendStack Setup Script v$VERSION"
    echo "Copyright © 2026 WeekendStack Project"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -q|--quick)
                SETUP_MODE="quick"
                shift
                ;;
            -i|--interactive)
                SETUP_MODE="interactive"
                shift
                ;;
            --skip-auth)
                SKIP_AUTH=true
                shift
                ;;
            --skip-pull)
                SKIP_PULL=true
                shift
                ;;
            --skip-cloudflare)
                SKIP_CLOUDFLARE=true
                shift
                ;;
            --skip-certs)
                SKIP_CERTS=true
                shift
                ;;
            --reconfigure)
                FORCE_RECONFIGURE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --validate)
                validate_configuration
                exit $?
                ;;
            --status)
                show_deployment_status
                exit $?
                ;;
            --rollback)
                rollback_configuration
                exit $?
                ;;
            --start)
                start_services
                exit $?
                ;;
            --stop)
                stop_services
                exit $?
                ;;
            --restart)
                restart_services
                exit $?
                ;;
            --cloudflare-only)
                # Load .env if it exists
                if [[ -f "$SCRIPT_DIR/.env" ]]; then
                    set -a; source "$SCRIPT_DIR/.env"; set +a
                fi
                setup_cloudflare_tunnel
                exit $?
                ;;
            --certs-only)
                # Load .env if it exists
                if [[ -f "$SCRIPT_DIR/.env" ]]; then
                    set -a; source "$SCRIPT_DIR/.env"; set +a
                fi
                setup_certificates
                exit $?
                ;;
            --docker-only)
                source "$SCRIPT_DIR/tools/setup/lib/docker-auth.sh"
                docker_login_hub
                exit $?
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run '$0 --help' for usage"
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    clear
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  WeekendStack Interactive Setup Script v$VERSION${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log_header "Prerequisites Check"
    
    local errors=0
    
    # Check Docker
    if ! check_command docker; then
        log_error "Docker is not installed"
        echo "Install Docker: https://docs.docker.com/get-docker/"
        errors=$((errors + 1))
    else
        local docker_version=$(docker --version | grep -oP '\d+\.\d+' | head -n1)
        log_success "Docker installed: v$docker_version"
    fi
    
    # Check Docker Compose
    if ! check_command docker compose version; then
        log_error "Docker Compose V2 is not available"
        echo "Ensure Docker Compose V2 is installed (docker compose)"
        errors=$((errors + 1))
    else
        local compose_version=$(docker compose version --short)
        log_success "Docker Compose installed: v$compose_version"
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        echo "Start Docker daemon: sudo systemctl start docker"
        errors=$((errors + 1))
    else
        log_success "Docker daemon: running"
    fi
    
    # Check user permissions
    if ! docker ps >/dev/null 2>&1; then
        log_warn "Current user may not have Docker permissions"
        echo "Add user to docker group: sudo usermod -aG docker \$USER"
    fi
    
    # Check disk space (need at least 50GB; <5GB is a hard stop)
    local available_disk=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if ((available_disk < 5)); then
        log_error "Critically low disk space: ${available_disk}GB available."
        log_error "Setup cannot proceed — Docker builds will fail with 'No space left on device'."
        log_error "Free space first by removing unused Docker images:"
        log_error "  docker image prune -af"
        log_error "Or run: sudo ./uninstall.sh --level 2 --non-interactive (then re-run setup)"
        exit 1
    elif ((available_disk < 50)); then
        log_warn "Low disk space: ${available_disk}GB available (recommended: 50GB+)"
    else
        log_success "Disk space: ${available_disk}GB available"
    fi
    
    # Check memory (16GB recommended for the full stack, especially AI services)
    if check_command free; then
        local total_memory=$(free -g | awk '/^Mem:/{print $2}')
        export TOTAL_MEMORY_GB=$total_memory
        if ((total_memory < 8)); then
            log_warn "Low memory: ${total_memory}GB available (minimum: 8GB)"
        elif ((total_memory < 16)); then
            log_warn "Low memory: ${total_memory}GB available (recommended: 16GB+)"
            log_warn "Low memory for AI: 32GB+ required to run AI services"
        else
            log_success "Memory: ${total_memory}GB available"
        fi
    else
        export TOTAL_MEMORY_GB=999
    fi
    
    # Check for GPU (informational)
    if check_command nvidia-smi; then
        log_success "NVIDIA GPU detected"
        export GPU_AVAILABLE=true
    else
        log_warn "No NVIDIA GPU detected (AI services will use CPU)"
        export GPU_AVAILABLE=false
    fi

    # Check jq (required for env template assembly) — auto-install if missing
    if ! check_command jq; then
        log_info "jq not found — installing automatically..."
        if sudo apt-get install -y -qq jq >/dev/null 2>&1; then
            log_success "jq installed: $(jq --version)"
        else
            log_error "jq could not be installed automatically"
            echo "Install manually with: sudo apt-get install -y jq"
            errors=$((errors + 1))
        fi
    else
        log_success "jq installed: $(jq --version)"
    fi
    
    if ((errors > 0)); then
        log_error "Prerequisites check failed with $errors errors"
        return 1
    fi
    
    log_success "All prerequisites met"
    return 0
}

# Add Coder's SSH public key to GitHub so workspace git clones work
setup_coder_github_ssh_key() {
    # Load env so we have CODER_SESSION_TOKEN and CODER_ACCESS_URL
    local env_file="$SCRIPT_DIR/.env"
    if [[ ! -f "$env_file" ]]; then return 0; fi
    local token access_url
    token=$(grep "^CODER_SESSION_TOKEN=" "$env_file" | cut -d'=' -f2 | tr -d ' ')
    access_url=$(grep "^CODER_ACCESS_URL=" "$env_file" | cut -d'=' -f2 | tr -d ' ')
    if [[ -z "$token" || -z "$access_url" ]]; then return 0; fi

    # Fetch the Coder SSH public key for this user
    local ssh_key
    ssh_key=$(curl -sf -H "Coder-Session-Token: $token" \
        "${access_url}/api/v2/users/me/gitsshkey" 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('public_key',''))" 2>/dev/null || true)
    if [[ -z "$ssh_key" ]]; then return 0; fi

    clear
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  GitHub SSH Key Setup${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Coder workspaces use this SSH key to clone private GitHub repos:"
    echo ""
    echo -e "  ${BOLD}$ssh_key${NC}"
    echo ""
    echo -e "  This key is shared by ALL workspaces on this Coder server."
    echo -e "  Add it to GitHub once and every workspace clone will work automatically."
    echo ""

    if ! prompt_yes_no "Add this key to GitHub now (uses the GitHub CLI)?" "y"; then
        echo ""
        echo -e "  You can add it manually at: ${CYAN}https://github.com/settings/ssh/new${NC}"
        echo ""
        return 0
    fi

    # Install gh CLI if missing
    if ! command -v gh &>/dev/null; then
        log_info "Installing GitHub CLI..."
        (
            type -p curl >/dev/null || sudo apt-get install -y curl
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
            sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
            sudo apt-get update -qq && sudo apt-get install -y gh
        ) >/dev/null 2>&1
        if ! command -v gh &>/dev/null; then
            log_warn "Could not install gh CLI. Add the key manually at: https://github.com/settings/ssh/new"
            return 0
        fi
        log_success "GitHub CLI installed"
    fi

    # Authenticate with GitHub (device flow)
    echo ""
    log_info "Authenticating with GitHub..."
    echo ""
    echo "  Steps:"
    echo "    1. A browser window will open to https://github.com/login/device"
    echo "    2. Copy and paste the authorization code that appears"
    echo "    3. Log in as the GitHub user who owns your private repos"
    echo ""
    read -rp "  Press Enter when you are ready to continue..."
    echo ""
    
    if ! gh auth login --git-protocol ssh --web 2>&1; then
        log_warn "GitHub auth failed. Add the key manually at: https://github.com/settings/ssh/new"
        return 0
    fi

    # Write key to a temp file and upload
    local key_file
    key_file=$(mktemp /tmp/coder-ssh-key.XXXXXX.pub)
    echo "$ssh_key" > "$key_file"

    # Build a unique title: "Coder @ hostname (YYYY-MM-DD)"
    local hostname_short install_date key_title
    hostname_short=$(hostname -s 2>/dev/null || echo "server")
    install_date=$(date +%Y-%m-%d)
    key_title="Coder @ ${hostname_short} (${install_date})"

    echo ""
    log_info "Adding Coder SSH key to GitHub as: \"$key_title\""
    if gh ssh-key add "$key_file" --title "$key_title" --type authentication 2>&1; then
        log_success "SSH key added to GitHub! Workspace git clones will now work automatically."
    else
        log_warn "Key may already exist on GitHub, or upload failed."
        echo -e "  You can verify at: ${CYAN}https://github.com/settings/keys${NC}"
    fi
    rm -f "$key_file"
    echo ""
}

# Trigger the first speedtest immediately after setup so the Glance widget
# has data without waiting for the first scheduled run (default: hourly).
# Uses 'artisan schedule:run' which invokes the CheckForScheduledSpeedtests
# callback — no API token or credentials required.
provision_speedtest_initial_run() {
    local max_wait=120  # seconds to wait for container to be healthy
    local waited=0

    # Only run if speedtest-tracker is in the deployed profiles
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^speedtest-tracker$'; then
        return 0
    fi

    log_step "Triggering initial speedtest (this may take 30-60 seconds)..."

    # Wait for the container to be fully ready
    while (( waited < max_wait )); do
        if docker exec speedtest-tracker test -f /config/www/database/database.sqlite 2>/dev/null; then
            break
        fi
        sleep 2
        (( waited += 2 )) || true
    done

    # Give Laravel a moment to fully initialize
    sleep 5

    # Try multiple methods to trigger a speedtest
    local triggered=false
    
    # Method 1: Try the speedtest:run command (most reliable)
    if docker exec speedtest-tracker php /app/www/artisan app:run-speedtest 2>/dev/null; then
        triggered=true
        log_success "Initial speedtest started — results will appear in Glance within ~60 seconds"
    elif docker exec speedtest-tracker php /app/www/artisan speedtest:run 2>/dev/null; then
        triggered=true
        log_success "Initial speedtest started — results will appear in Glance within ~60 seconds"
    # Method 2: Force the scheduled task to run
    elif docker exec speedtest-tracker php /app/www/artisan schedule:run --force 2>/dev/null | grep -q 'Running'; then
        triggered=true
        log_success "Initial speedtest queued — results will appear in Glance within ~60 seconds"
    fi
    
    if ! $triggered; then
        log_info "Speedtest will run automatically on its schedule (${SPEEDTEST_SCHEDULE:-0 2 * * *})"
        log_info "Or trigger manually via the web UI at http://${HOST_IP}:8765"
    fi
}

# Prompt for the Kavita API key used by the Glance widget.
# Called after services are started (so Kavita is accessible).
# Saves KAVITA_API_KEY to .env; glance-generator skips the widget when the key is empty.
setup_kavita_glance_widget() {
    # Build the Kavita URL the same way the rest of setup does
    local domain_mode base_domain host_ip kavita_port lab_domain
    domain_mode=$(grep "^DOMAIN_MODE=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    base_domain=$(grep "^BASE_DOMAIN=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    host_ip=$(grep "^HOST_IP=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    kavita_port=$(grep "^KAVITA_PORT=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "'); kavita_port="${kavita_port:-5002}"
    lab_domain=$(grep "^LAB_DOMAIN=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "'); lab_domain="${lab_domain:-lab}"

    local kavita_url
    if [[ "$domain_mode" == "cloudflare" || "$domain_mode" == "both" ]]; then
        kavita_url="https://kavita.${base_domain}"
    elif [[ "$domain_mode" == "pihole" ]]; then
        kavita_url="https://kavita.${lab_domain}"
    else
        kavita_url="http://${host_ip}:${kavita_port}"
    fi

    echo ""
    log_step "Kavita Glance Widget"
    echo ""
    echo "The Kavita widget shows recently added manga/books in your Glance dashboard."
    echo ""
    if ! prompt_yes_no "Configure the Kavita Glance widget?" "y"; then
        log_info "Kavita widget skipped — it will be omitted from Glance"
        if grep -q "^KAVITA_API_KEY=" "$SCRIPT_DIR/.env"; then
            sed -i "s|^KAVITA_API_KEY=.*|KAVITA_API_KEY=|" "$SCRIPT_DIR/.env"
        else
            echo "KAVITA_API_KEY=" >> "$SCRIPT_DIR/.env"
        fi
        return 0
    fi
    echo ""
    echo "To get your Kavita API key:"
    echo "  1. Open Kavita: ${kavita_url}"
    echo "     (Complete the initial account setup if this is your first install)"
    echo "  2. Click your user icon → Settings"
    echo "  3. Go to Account → API Key / OPDS"
    echo "  4. Copy the API key"
    echo ""
    local api_key
    api_key=$(prompt_input "Paste your Kavita API key (or press Enter to skip)" "")
    if [[ -z "$api_key" ]]; then
        log_info "No key entered — Kavita widget will be omitted from Glance"
        if grep -q "^KAVITA_API_KEY=" "$SCRIPT_DIR/.env"; then
            sed -i "s|^KAVITA_API_KEY=.*|KAVITA_API_KEY=|" "$SCRIPT_DIR/.env"
        else
            echo "KAVITA_API_KEY=" >> "$SCRIPT_DIR/.env"
        fi
        return 0
    fi
    if grep -q "^KAVITA_API_KEY=" "$SCRIPT_DIR/.env"; then
        sed -i "s|^KAVITA_API_KEY=.*|KAVITA_API_KEY=$api_key|" "$SCRIPT_DIR/.env"
    else
        echo "KAVITA_API_KEY=$api_key" >> "$SCRIPT_DIR/.env"
    fi
    log_success "Kavita API key saved — widget will appear in Glance"
}

# Wait for the Coder HTTP API to respond before attempting template deployment.
# Polls /api/v2/buildinfo up to max_wait seconds (default: 180).
# Returns 0 when Coder is ready, 1 on timeout.
wait_for_coder() {
    local coder_url="${CODER_ACCESS_URL:-http://localhost:7080}"
    local max_wait="${1:-180}"
    local elapsed=0
    local interval=5

    log_step "Waiting for Coder to become ready (up to ${max_wait}s)..."
    while [[ $elapsed -lt $max_wait ]]; do
        if curl -sf --max-time 3 "${coder_url}/api/v2/buildinfo" >/dev/null 2>&1; then
            log_success "Coder is ready (${elapsed}s elapsed)"
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
        log_info "  Coder not yet ready — ${elapsed}s / ${max_wait}s elapsed..."
    done

    log_warn "Coder did not become ready within ${max_wait}s"
    log_warn "Template deployment will be skipped."
    log_info "Deploy templates later with: make coder-templates"
    return 1
}

# Interactive Coder template deployment
deploy_coder_templates_interactive() {
    local marker_file="$SCRIPT_DIR/config/coder/.template_deployment_complete"
    local deploy_script="$SCRIPT_DIR/config/coder/scripts/deploy-all-templates.sh"
    local coder_api_script="$SCRIPT_DIR/config/coder/scripts/lib/coder-api.sh"

    # Fall back to tools/coder/scripts if config copy is missing (e.g. after Level 2 uninstall)
    if [[ ! -x "$deploy_script" && -x "$SCRIPT_DIR/tools/coder/scripts/deploy-all-templates.sh" ]]; then
        local tools_scripts="$SCRIPT_DIR/tools/coder/scripts"
        mkdir -p "$SCRIPT_DIR/config/coder/scripts/lib"
        cp -r "$tools_scripts"/. "$SCRIPT_DIR/config/coder/scripts/"
        chmod +x "$SCRIPT_DIR/config/coder/scripts"/*.sh "$SCRIPT_DIR/config/coder/scripts/lib"/*.sh 2>/dev/null || true
    fi

    if [[ ! -x "$deploy_script" ]]; then
        log_warn "Coder template deployment script not found: $deploy_script"
        return 1
    fi

    # Wait for Coder API before showing anything
    if ! wait_for_coder 180; then
        return 1
    fi

    clear
    local coder_url="${CODER_ACCESS_URL:-http://localhost:7080}"

    # ── Step 1: Ask if user wants to install templates ────────────────────────
    echo ""
    log_header "Install Coder Templates"
    echo ""
    echo "Coder templates are pre-built workspace blueprints that let developers"
    echo "spin up ready-to-code environments with one click. This stack includes:"
    echo ""
    # List templates from disk
    local templates_dir="$SCRIPT_DIR/config/coder/templates"
    if [[ -d "$templates_dir" ]]; then
        for t in "$templates_dir"/*/; do
            local tname
            tname=$(basename "$t")
            local desc=""
            if [[ -f "$t/README.md" ]]; then
                desc=$(head -3 "$t/README.md" | grep -v "^#" | grep -v "^$" | head -1)
            fi
            echo "  ○ ${tname}${desc:+  — $desc}"
        done
    fi
    echo ""

    if ! prompt_yes_no "Install Coder templates?" "y"; then
        log_info "Skipping template installation. Run 'make coder-templates' later."
        return 0
    fi

    # ── Step 2: Authenticate ──────────────────────────────────────────────────
    clear
    log_header "Coder Authentication"
    echo "  To deploy templates, you need a CLI session token from Coder."
    echo ""
    echo "  1. Sign in (first user becomes admin):"
    echo "     ${coder_url}"
    echo ""
    echo "  2. Get your session token:"
    echo "     ${coder_url}/cli-auth"
    echo ""

    local token=""
    # Use existing token silently if it passes validation
    if [[ -n "${CODER_SESSION_TOKEN:-}" ]]; then
        local user_info
        user_info=$(curl -sf --max-time 5 \
            -H "Coder-Session-Token: $CODER_SESSION_TOKEN" \
            "$coder_url/api/v2/users/me" 2>/dev/null || true)
        if [[ -n "$user_info" ]] && echo "$user_info" | grep -q '"username"'; then
            token="$CODER_SESSION_TOKEN"
            local uname
            uname=$(echo "$user_info" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
            log_success "Already authenticated as: $uname"
        fi
    fi

    if [[ -z "$token" ]]; then
        read -rp "  Paste your Coder session token (or press Enter to skip): " token
        
        if [[ -z "$token" ]]; then
            log_warn "No token provided. Skipping Coder template installation."
            return 0
        fi
        
        # Validate token
        local user_info
        user_info=$(curl -sf --max-time 5 \
            -H "Coder-Session-Token: $token" \
            "$coder_url/api/v2/users/me" 2>/dev/null || true)
        if [[ -n "$user_info" ]] && echo "$user_info" | grep -q '"username"'; then
            local uname
            uname=$(echo "$user_info" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
            log_success "Authenticated as: $uname"
            
            # Save token to .env
            if grep -q "^CODER_SESSION_TOKEN=" "$SCRIPT_DIR/.env" 2>/dev/null; then
                sed -i "s|^CODER_SESSION_TOKEN=.*|CODER_SESSION_TOKEN=$token|" "$SCRIPT_DIR/.env"
            else
                echo "CODER_SESSION_TOKEN=$token" >> "$SCRIPT_DIR/.env"
            fi
            export CODER_SESSION_TOKEN="$token"
        else
            log_warn "Token invalid or Coder not reachable. Skipping template installation."
            return 0
        fi
    fi

    # ── Step 3: Deploy templates, showing live progress ───────────────────────
    echo ""
    echo "  Deploying templates:"
    echo ""

    local templates_dir="$SCRIPT_DIR/config/coder/templates"
    local push_script="$SCRIPT_DIR/config/coder/scripts/push-template.sh"
    local ok=0 fail=0

    for t in "$templates_dir"/*/; do
        local tname
        tname=$(basename "$t")
        printf "  ○ %-20s" "$tname"
        local log_out
        log_out=$(CODER_SESSION_TOKEN="$token" CODER_ACCESS_URL="$coder_url" \
            "$push_script" "$tname" 2>&1) && {
            printf "\r  ● %s\n" "$tname"
            ok=$((ok + 1))
        } || {
            printf "\r  ✗ %s (failed)\n" "$tname"
            fail=$((fail + 1))
        }
    done

    echo ""
    if [[ $fail -eq 0 ]]; then
        log_success "All $ok templates installed successfully"
        date > "$marker_file"
    else
        log_warn "$ok installed, $fail failed — run 'make coder-templates' to retry"
    fi
}

# Main setup workflow
main_setup() {
    # Export configuration flags
    export FORCE_RECONFIGURE
    
    local current_step=0

    # Helper to show progress
    show_setup_progress() {
        current_step=$((current_step + 1))
        clear
        echo ""
        echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}${CYAN}  Phase $current_step — $1${NC}"
        echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    }
    
    # 1. Check prerequisites
    show_setup_progress "Checking Prerequisites"
    if ! check_prerequisites; then
        log_error "Prerequisites check failed. Please fix errors and try again."
        exit 1
    fi
    
    # Ask to continue after prerequisites
    if [[ "$SETUP_MODE" == "interactive" ]] && ! $DRY_RUN; then
        echo ""
        read -r -p "Prerequisites check complete. Continue with setup? [Y/n]: " _prereq_continue </dev/tty
        _prereq_continue="${_prereq_continue:-y}"
        if [[ ! "${_prereq_continue,,}" =~ ^y ]]; then
            log_error "Setup cancelled by user"
            exit 0
        fi
        clear
    fi
    
    # 2. Select profiles
    show_setup_progress "Selecting Service Profiles"
    local selected_profiles=()
    if [[ "$SETUP_MODE" == "quick" ]]; then
        selected_profiles=($(select_profiles_quick))
    else
        selected_profiles=($(select_profiles_interactive))
    fi
    
    # Check if user wants templates-only mode
    if [[ "${selected_profiles[0]}" == "TEMPLATES_ONLY_MODE" ]]; then
        clear
        deploy_coder_templates_interactive
        echo ""
        log_success "Template management complete!"
        log_info "To make changes to services, run ./setup.sh again"
        exit 0
    fi

    if [[ "${selected_profiles[0]}" == "SETUP_CANCELLED" ]]; then
        echo ""
        log_info "Setup cancelled. Run ./setup.sh to start again."
        exit 0
    fi

    if [[ ${#selected_profiles[@]} -eq 0 ]]; then
        log_error "Profile selection returned empty — cannot continue"
        exit 1
    fi

    export SELECTED_PROFILES=("${selected_profiles[@]}")
    
    # Clear screen after selection
    clear
    
    # 3. Docker registry authentication
    # Note: Contextual authentication happens later (step 10.5) after analyzing image requirements
    
    # 4. Generate environment configuration
    show_setup_progress "Environment Configuration"
    if [[ "$SETUP_MODE" == "quick" ]]; then
        generate_env_quick "${selected_profiles[@]}"
    else
        generate_env_interactive "${selected_profiles[@]}"
    fi
    
    # 5. Validate .env file
    show_setup_progress "Validating Configuration"
    log_step "Validating environment configuration..."
    
    # Run validation and capture both output AND exit code (disable set -e temporarily)
    local validation_output
    local validation_exit_code=0
    set +e  # Temporarily disable exit on error
    validation_output=$("$SCRIPT_DIR/tools/validate-env.sh" 2>&1)
    validation_exit_code=$?
    set -e  # Re-enable exit on error
    
    if [[ $validation_exit_code -eq 0 ]]; then
        log_success "Environment validation passed"
    else
        echo ""
        log_warn "Environment validation found issues:"
        echo ""
        echo "$validation_output"
        echo ""
        
        # Check if errors or just warnings
        local has_errors=false
        if echo "$validation_output" | grep -q "error(s)"; then
            has_errors=true
        fi
        
        if [[ "$SETUP_MODE" == "interactive" ]]; then
            if $has_errors; then
                if ! prompt_yes_no "Validation found errors. Continue anyway?" "n"; then
                    log_error "Setup aborted due to validation errors"
                    exit 1
                fi
            else
                log_info "Validation warnings are acceptable, continuing..."
            fi
        else
            # In quick mode, abort on errors but continue on warnings
            if $has_errors; then
                log_error "Setup aborted due to validation errors (use --interactive to override)"
                exit 1
            else
                log_info "Validation warnings are acceptable, continuing..."
            fi
        fi
    fi
    
    # 6. Create directories
    show_setup_progress "Creating Directory Structure"
    if ! setup_all_directories "${selected_profiles[@]}"; then
        log_error "Failed to create directory structure"
        exit 1
    fi

    # 6b. SSH Key Setup (own step so the screen is clear and readable)
    show_setup_progress "SSH Key Setup"
    create_ssh_directory
    
    # 7. Create Docker networks
    # SKIPPED: Docker Compose creates networks automatically with proper labels
    # Manual creation causes "network exists but was not created by compose" errors
    # show_setup_progress "Creating Docker Networks"
    # if ! create_docker_networks; then
    #     log_error "Failed to create Docker networks"
    #     exit 1
    # fi
    
    # 8. Create Docker volumes
    show_setup_progress "Creating Docker Volumes"
    if ! create_docker_volumes; then
        log_error "Failed to create Docker volumes"
        exit 1
    fi
    
    # 9. Cloudflare Tunnel setup (when external domain is configured)
    show_setup_progress "Cloudflare Tunnel Configuration"
    local _domain_mode
    _domain_mode=$(grep "^DOMAIN_MODE=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    local _base_domain
    _base_domain=$(grep "^BASE_DOMAIN=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    if ! $SKIP_CLOUDFLARE && [[ "$SETUP_MODE" == "interactive" ]] && \
       [[ "$_domain_mode" =~ ^(cloudflare|both)$ ]]; then
        setup_cloudflare_tunnel || log_warn "Cloudflare Tunnel setup skipped"
    elif [[ "$_domain_mode" == "ip" || -z "$_domain_mode" ]]; then
        log_info "No external domain configured — skipping Cloudflare Tunnel setup"
    else
        log_info "Skipping Cloudflare Tunnel setup (--skip-cloudflare or quick mode)"
    fi
    # Immediately update custom profile after wizard so the tunnel service
    # is included even if the user skips starting services
    ensure_cloudflare_in_custom_profile

    # 10. Certificate setup (when local domain / Pi-hole is configured)
    # Generates self-signed CA + wildcard cert for local *.lab HTTPS access
    # These certs are for LAN access only — Cloudflare handles TLS for remote access
    show_setup_progress "Setting Up SSL Certificates"
    local _dm
    _dm=$(grep "^DOMAIN_MODE=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    if ! $SKIP_CERTS && [[ "$_dm" =~ ^(pihole|both)$ ]]; then
        setup_certificates || log_warn "Certificate setup incomplete (continuing anyway)"
    elif $SKIP_CERTS; then
        log_info "Skipping certificate setup (--skip-certs)"
    else
        log_info "No local domain configured — skipping self-signed certificate generation"
        log_info "(Certs are only needed for Pi-Hole / .lab domain access)"
    fi
    
    # 10.5. Image Pull Planning
    show_setup_progress "Analyzing Docker Images"
    if ! $SKIP_PULL; then
        # Source image analysis libraries
        source "$SCRIPT_DIR/tools/setup/lib/image-analyzer.sh"
        source "$SCRIPT_DIR/tools/setup/lib/image-puller.sh"
        source "$SCRIPT_DIR/tools/setup/lib/docker-auth.sh"
        
        log_step "Analyzing required images for selected profiles..."
        local image_analysis=$(analyze_compose_images "${selected_profiles[@]}")
        
        # Parse analysis
        declare -A img_data
        while IFS='=' read -r key value; do
            img_data[$key]="$value"
        done <<< "$image_analysis"
        
        local dockerhub_count="${img_data[DOCKERHUB_COUNT]:-0}"
        
        # Check rate limit status
        local rate_limit_status=$(format_rate_limit_status)
        
        # Show the pull plan
        show_pull_plan "$image_analysis" "$rate_limit_status"
        
        # Contextual authentication if needed and not skipped
        if ! $SKIP_AUTH && [[ $dockerhub_count -gt 0 ]] && [[ "$SETUP_MODE" == "interactive" ]]; then
            if prompt_hub_auth_contextual "$dockerhub_count"; then
                docker_login_hub || log_warn "Authentication failed or skipped"
            fi
        fi
        
        clear || true  # Non-fatal clear in case stdout is not a terminal
    fi
    
    # 11. Pull Docker images (optimized)
    show_setup_progress "Pulling Docker Images"
    if ! $SKIP_PULL; then
        if ! pull_images_optimized "${selected_profiles[@]}"; then
            log_error "Failed to pull Docker images"
            
            if [[ "$SETUP_MODE" == "interactive" ]]; then
                if ! prompt_yes_no "Some images failed. Continue anyway?" "n"; then
                    exit 1
                fi
            else
                exit 1
            fi
        fi
        
        # Ask about keeping cache
        if is_cache_running && [[ "$SETUP_MODE" == "interactive" ]]; then
            echo ""
            if prompt_yes_no "Keep registry cache running for future pulls?" "n"; then
                log_info "Registry cache will continue running"
            else
                stop_registry_cache
            fi
        fi
    else
        log_info "Skipping image pull (--skip-pull)"
    fi
    
    # 12. Run init containers
    show_setup_progress "Running Initialization Containers"
    local init_containers=($(get_init_containers_for_profiles "${selected_profiles[@]}"))
    if [[ ${#init_containers[@]} -gt 0 ]]; then
        if ! run_init_containers "${init_containers[@]}"; then
            log_warn "Some init containers failed (continuing anyway)"
        fi
    else
        log_info "No initialization containers needed"
    fi
    
    # 13. Generate setup summary
    show_setup_progress "Generating Setup Summary"
    if ! generate_setup_summary "${selected_profiles[@]}"; then
        log_warn "Failed to generate summary (continuing anyway)"
    fi

    # Ask to start services
    echo ""
    echo -e "${BOLD}${GREEN}Setup Complete!${NC}"
    echo ""
    if prompt_yes_no "Start WeekendStack services now?" "y"; then
        clear
        # Re-source .env to pick up any changes made by cloudflare wizard, cert setup, etc.
        if [[ -f "$SCRIPT_DIR/.env" ]]; then
            set -a
            source "$SCRIPT_DIR/.env"
            set +a
        fi
        
        # Ensure cloudflare-tunnel is in custom profile if wizard configured it
        ensure_cloudflare_in_custom_profile
        
        # Add external profile if Cloudflare tunnel is enabled AND token is configured
        if grep -q "^CLOUDFLARE_TUNNEL_ENABLED=true" "$SCRIPT_DIR/.env" 2>/dev/null; then
            local cf_token
            cf_token=$(grep "^CLOUDFLARE_TUNNEL_TOKEN=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
            if [[ -n "$cf_token" ]]; then
                if [[ ! " ${selected_profiles[*]} " =~ " external " ]]; then
                    selected_profiles+=("external")
                    log_info "Adding 'external' profile for Cloudflare Tunnel"
                fi
                # Persist to .env so start_services_with_profiles (which re-reads .env) picks it up
                local _sp_profiles
                _sp_profiles=$(grep "^COMPOSE_PROFILES=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2)
                if [[ -n "$_sp_profiles" && "$_sp_profiles" != *"external"* ]]; then
                    sed -i "s|^COMPOSE_PROFILES=.*|COMPOSE_PROFILES=${_sp_profiles},external|" "$SCRIPT_DIR/.env"
                elif [[ -z "$_sp_profiles" ]]; then
                    echo "COMPOSE_PROFILES=external" >> "$SCRIPT_DIR/.env"
                fi
            else
                log_warn "Cloudflare tunnel enabled but connector token is missing."
                log_warn "  The cloudflare-tunnel container will NOT start."
                log_info "  Fix: run './setup.sh --cloudflare-only' to re-fetch the connector token."
                log_info "  Then start services again with: docker compose --profile external up -d cloudflare-tunnel"
            fi
        fi
        start_services_with_profiles "${selected_profiles[@]}"

        # Trigger the first speedtest so the Glance widget has data immediately
        provision_speedtest_initial_run

        # Deploy Coder templates if dev profile was selected (or 'all')
        if [[ " ${selected_profiles[*]} " =~ " dev " ]] || [[ " ${selected_profiles[*]} " =~ " all " ]]; then
            deploy_coder_templates_interactive
            setup_coder_github_ssh_key
        fi

        # Kavita Glance widget — runs after services are up so Kavita is accessible
        if [[ "$SETUP_MODE" == "interactive" ]] && \
           { [[ " ${selected_profiles[*]} " =~ " media " ]] || [[ " ${selected_profiles[*]} " =~ " all " ]]; }; then
            setup_kavita_glance_widget
            # Regenerate glance config (now with or without kavita widget) and reload
            generate_glance_config "$SCRIPT_DIR/config/glance/glance.yml" "$SCRIPT_DIR/.env"
            docker restart glance 2>/dev/null || true
        fi

        display_summary_to_console
    else
        log_info "Services not started. Run './setup.sh --start' when ready."
        echo ""
        echo "To start services later:"
        echo "  docker compose up -d"
        echo ""
    fi
}

# Pull Docker images
pull_images() {
    local profiles=("$@")
    
    log_header "Pulling Docker Images"
    
    echo "This may take several minutes depending on your internet connection..."
    echo ""
    
    local profile_args=""
    for profile in "${profiles[@]}"; do
        profile_args="$profile_args --profile $profile"
    done
    
    log_step "Pulling images for profiles: ${profiles[*]}"
    
    if docker compose $profile_args pull 2>&1 | tee /tmp/docker-pull.log; then
        log_success "All images pulled successfully"
    else
        log_warn "Some images may have failed to pull (check /tmp/docker-pull.log)"
        if ! prompt_yes_no "Continue anyway?" "y"; then
            exit 1
        fi
        clear
    fi
}

# Ensure cloudflare-tunnel is in docker-compose.custom.yml when the tunnel
# is enabled and has a token. The custom profile is generated during env setup
# (before the cloudflare wizard), so this appends the service if missing.
ensure_cloudflare_in_custom_profile() {
    [[ -f "$SCRIPT_DIR/docker-compose.custom.yml" ]] || return 0
    
    local cf_enabled cf_token_val
    cf_enabled=$(grep "^CLOUDFLARE_TUNNEL_ENABLED=true" "$SCRIPT_DIR/.env" 2>/dev/null || true)
    cf_token_val=$(grep "^CLOUDFLARE_TUNNEL_TOKEN=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
    
    if [[ -n "$cf_enabled" && -n "$cf_token_val" ]] && \
       ! grep -q "cloudflare-tunnel:" "$SCRIPT_DIR/docker-compose.custom.yml"; then
        cat >> "$SCRIPT_DIR/docker-compose.custom.yml" << 'CFEOF'
  cloudflare-tunnel:
    profiles:
      - custom

CFEOF
        log_info "Added cloudflare-tunnel to custom profile"
    fi
}

# Detect and remove Docker phantom directories at paths that must be files.
# Docker silently creates a directory when a bind-mount source file is missing.
# For files with a .example counterpart, copies the example after fixing the phantom.
preflight_fix_mounts() {
    # NOTE: glance.yml is handled separately below (generated, not copied from .example)
    local file_mounts=(
        "$SCRIPT_DIR/config/filebrowser/init-filebrowser.sh"
    )
    local fixed=0

    # Glance config: remove phantom directory if Docker created one, then generate.
    local glance_cfg="$SCRIPT_DIR/config/glance/glance.yml"
    if [[ -d "$glance_cfg" ]]; then
        log_warn "Found directory where a file is expected: $glance_cfg"
        rmdir "$glance_cfg" 2>/dev/null || rm -rf "$glance_cfg"
        fixed=$((fixed + 1))
    fi

    # Fix any remaining phantom directories (mounted files Docker may turn into dirs)
    for path in "${file_mounts[@]}"; do
        if [[ -d "$path" ]]; then
            log_warn "Found directory where a file is expected: $path"
            rmdir "$path" 2>/dev/null || rm -rf "$path"
            local example="${path}.example"
            if [[ -f "$example" ]]; then
                cp "$example" "$path"
                log_success "Fixed phantom directory -> copied from .example: $path"
            else
                touch "$path"
                log_success "Fixed phantom directory -> placeholder file: $path"
            fi
            fixed=$((fixed + 1))
        fi
    done

    # Traefik config.yml needs a valid static config, not just a touch placeholder.
    if type _ensure_traefik_static_config &>/dev/null; then
        _ensure_traefik_static_config "$SCRIPT_DIR/config/traefik/config.yml"
    else
        local traefik_cfg="$SCRIPT_DIR/config/traefik/config.yml"
        if [[ -d "$traefik_cfg" ]]; then
            rmdir "$traefik_cfg" 2>/dev/null || rm -rf "$traefik_cfg"
            local traefik_example="${traefik_cfg}.example"
            if [[ -f "$traefik_example" ]]; then
                cp "$traefik_example" "$traefik_cfg"
                log_success "Fixed phantom directory -> copied from .example: $traefik_cfg"
            else
                touch "$traefik_cfg"
                log_success "Fixed phantom directory -> placeholder file: $traefik_cfg"
            fi
            fixed=$((fixed + 1))
        fi
    fi

    if [[ $fixed -gt 0 ]]; then
        log_info "Fixed $fixed mount path(s). Run --cloudflare-only or --certs-only to populate config."
    fi

    # Pre-create data directories that need specific user ownership.
    # Docker Compose creates missing bind-mount dirs as root; these services
    # run as non-root users and would fail with EACCES otherwise.
    local data_base="${DATA_BASE_DIR:-$SCRIPT_DIR/data}"
    # Evaluate variable references (DATA_BASE_DIR may itself contain vars)
    data_base=$(eval echo "$data_base")
    local -A dir_owners=(
        ["$data_base/n8n"]="1000:1000"   # n8n runs as node (uid 1000)
    )
    for dir in "${!dir_owners[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" 2>/dev/null || sudo mkdir -p "$dir"
            sudo chown "${dir_owners[$dir]}" "$dir" 2>/dev/null || true
            log_info "Created data directory with correct ownership: $dir"
        fi
    done

    # Generate Traefik basic-auth htpasswd files from DEFAULT_ADMIN_USER/PASSWORD.
    # These gate external-facing services (AI tools, IT-Tools, SearXNG, Guacamole,
    # Glance external) when accessed through the Cloudflare tunnel.
    local auth_dir="$SCRIPT_DIR/config/traefik/auth"
    mkdir -p "$auth_dir"
    local admin_user admin_pass
    admin_user=$(grep "^DEFAULT_ADMIN_USER=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    admin_pass=$(grep "^DEFAULT_ADMIN_PASSWORD=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    admin_user=${admin_user:-admin}
    admin_pass=${admin_pass:-changeme}

    # Check if any htpasswd file already has the right user; regenerate if not.
    # Always regenerate so password changes from setup are reflected.
    local needs_regen=true
    local htpasswd_file="$auth_dir/htpasswd-admin"

    if $needs_regen; then
        if command -v htpasswd >/dev/null 2>&1; then
            htpasswd -nbB "$admin_user" "$admin_pass" > "$htpasswd_file"
        elif docker info >/dev/null 2>&1; then
            docker run --rm httpd:2-alpine htpasswd -nbB "$admin_user" "$admin_pass" \
                > "$htpasswd_file" 2>/dev/null
        fi
        if [[ -f "$htpasswd_file" ]]; then
            chmod 600 "$htpasswd_file"
            log_info "Generated Traefik basic auth: $htpasswd_file (user: $admin_user)"
            # Keep legacy test files in sync so existing middleware configs still work
            for f in "$auth_dir"/htpasswd-test{1,2,3,4}; do
                cp "$htpasswd_file" "$f" 2>/dev/null || true
            done
        fi
    fi

    # Set FORCE_LINK_MODE in .env to drive link-router URL routing.
    # "external" = Cloudflare tunnel configured → all /go/ links route through tunnel.
    # "ip"       = No tunnel → all /go/ links go directly to HOST_IP:PORT (no DNS needed).
    if type update_env_var &>/dev/null && [[ -f "$SCRIPT_DIR/.env" ]]; then
        local _tunnel_enabled _tunnel_token
        _tunnel_enabled=$(grep "^CLOUDFLARE_TUNNEL_ENABLED=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
        _tunnel_token=$(grep "^CLOUDFLARE_TUNNEL_TOKEN=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
        if [[ "$_tunnel_enabled" == "true" && -n "$_tunnel_token" ]]; then
            update_env_var "FORCE_LINK_MODE" "external" "$SCRIPT_DIR/.env"
            log_info "Tunnel active — FORCE_LINK_MODE=external (all /go/ links via tunnel)"
        else
            update_env_var "FORCE_LINK_MODE" "ip" "$SCRIPT_DIR/.env"
            log_info "No tunnel — FORCE_LINK_MODE=ip (all /go/ links via HOST_IP:PORT)"
        fi
    fi

    # Generate Glance dashboard config filtered by selected profiles.
    generate_glance_config "$SCRIPT_DIR/config/glance/glance.yml" "$SCRIPT_DIR/.env"
}

# Expand abstract "all" profile into concrete Docker Compose profile names and
# resolve any cross-profile dependencies (e.g. external requires networking).
# Usage: expanded=($(expand_profiles "${arr[@]}"))
expand_profiles() {
    local -a input=("$@")
    declare -A seen
    local -a result=()

    # Base profiles that "all" maps to.
    # networking/pihole/external are NOT included here — they are auto-derived
    # by the Access Configuration wizard and appended to COMPOSE_PROFILES directly.
    local ALL_CONCRETE=(core monitoring productivity dev ai media)

    for p in "${input[@]}"; do
        if [[ "$p" == "all" ]]; then
            for cp in "${ALL_CONCRETE[@]}"; do
                [[ -z "${seen[$cp]:-}" ]] && { seen[$cp]=1; result+=("$cp"); }
            done
        else
            [[ -z "${seen[$p]:-}" ]] && { seen[$p]=1; result+=("$p"); }
        fi
    done

    # cloudflare-tunnel (external profile) depends on traefik (networking profile)
    if [[ -n "${seen[external]:-}" && -z "${seen[networking]:-}" ]]; then
        result+=("networking")
        seen[networking]=1
    fi
    # pihole also requires networking (Traefik provides HTTPS for pihole.lab)
    if [[ -n "${seen[pihole]:-}" && -z "${seen[networking]:-}" ]]; then
        result+=("networking")
        seen[networking]=1
    fi

    echo "${result[@]}"
}

# Start services with profiles
start_services_with_profiles() {
    local -a profiles=("$@")

    preflight_fix_mounts

    # Re-read COMPOSE_PROFILES from .env — the interactive wizard may have added
    # sub-profile choices (gitea, open-webui, librechat, homeassistant…)
    # that were not in the original in-memory selected_profiles array.
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        local env_compose_profiles
        env_compose_profiles=$(grep "^COMPOSE_PROFILES=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2- | tr -d '"')
        if [[ -n "$env_compose_profiles" ]]; then
            IFS=',' read -ra profiles <<< "$env_compose_profiles"
        fi
    fi

    # Expand "all" → concrete profiles and resolve cross-profile dependencies
    profiles=($(expand_profiles "${profiles[@]}"))

    log_header "Starting Services"

    local profile_args=""
    for profile in "${profiles[@]}"; do
        profile_args="$profile_args --profile $profile"
    done

    log_step "Starting services for profiles: ${profiles[*]}"

    # Remove any stale containers from previous (partial) runs before bringing
    # the stack up. --remove-orphans also cleans up containers for services
    # that are no longer defined in the current compose configuration.
    log_step "Removing any stale containers from previous runs..."
    docker compose $profile_args down --remove-orphans 2>/dev/null || true

    if docker compose $profile_args up -d --build --remove-orphans; then
        log_success "Services started successfully"

        echo ""
        log_info "Waiting for services to become healthy..."
        sleep 5

        # Show running services
        echo ""
        docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    else
        log_error "Failed to start services"
        exit 1
    fi
}

# Validate configuration
validate_configuration() {
    log_header "Configuration Validation"
    
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        log_error ".env file not found. Run setup first."
        return 1
    fi
    
    # Run validate-env.sh
    "$SCRIPT_DIR/tools/validate-env.sh"
    
    # Check compose files
    log_step "Validating docker-compose files..."
    # Suppress warnings about unset variables from unselected profiles
    if docker compose config >/dev/null 2>&1; then
        log_success "Docker Compose configuration is valid"
    else
        log_error "Docker Compose configuration has errors"
        return 1
    fi
    
    return 0
}

# Show deployment status
show_deployment_status() {
    log_header "Deployment Status"
    
    # Check if .env exists
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        log_warn "Not configured - run setup first"
        return 1
    fi
    
    # Show setup metadata
    if grep -q "SETUP_COMPLETED=true" "$SCRIPT_DIR/.env"; then
        local setup_date=$(grep "^SETUP_DATE=" "$SCRIPT_DIR/.env" | cut -d'=' -f2)
        local profiles=$(grep "^SELECTED_PROFILES=" "$SCRIPT_DIR/.env" | cut -d'=' -f2)
        
        echo "Setup completed: $setup_date"
        echo "Active profiles: $profiles"
        echo ""
    fi
    
    # Show running services
    log_step "Running services:"
    docker compose ps
    
    echo ""
    
    # Show resource usage
    log_step "Resource usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    
    return 0
}

# Rollback configuration
rollback_configuration() {
    log_header "Configuration Rollback"
    
    local backup_dir="$SCRIPT_DIR/_trash"
    local latest_backup=$(ls -t "$backup_dir"/.env.backup.* 2>/dev/null | head -n1)
    
    if [[ -z "$latest_backup" ]]; then
        log_error "No .env backup found in $backup_dir"
        return 1
    fi
    
    log_info "Latest backup: $latest_backup"
    
    if prompt_yes_no "Restore this backup?" "y"; then
        cp "$latest_backup" "$SCRIPT_DIR/.env"
        log_success "Configuration restored from backup"
        log_info "Restart services: ./setup.sh --restart"
    else
        log_info "Rollback cancelled"
    fi
    
    return 0
}

# Start services
start_services() {
    log_header "Starting Services"
    
    # Re-source .env for latest config
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        set -a
        source "$SCRIPT_DIR/.env"
        set +a
    fi
    
    # Ensure cloudflare-tunnel is in custom profile if enabled
    ensure_cloudflare_in_custom_profile
    
    if docker compose up -d; then
        log_success "Services started"
        docker compose ps
    else
        log_error "Failed to start services"
        return 1
    fi
}

# Stop services
stop_services() {
    log_header "Stopping Services"
    
    if docker compose down; then
        log_success "Services stopped"
    else
        log_error "Failed to stop services"
        return 1
    fi
}

# Restart services
restart_services() {
    log_header "Restarting Services"
    
    # Re-source .env for latest config
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        set -a
        source "$SCRIPT_DIR/.env"
        set +a
    fi
    
    # Ensure cloudflare-tunnel is in custom profile if enabled
    ensure_cloudflare_in_custom_profile
    
    # Use up -d instead of restart to also start any newly-enabled services
    if docker compose up -d --force-recreate; then
        log_success "Services restarted"
        docker compose ps
    else
        log_error "Failed to restart services"
        return 1
    fi
}

# Main entry point
main() {
    parse_args "$@"
    
    cd "$SCRIPT_DIR"
    
    if $DRY_RUN; then
        log_info "DRY RUN MODE - No changes will be made"
        SETUP_MODE="interactive"
    fi
    
    main_setup
}

# Run main function
main "$@"
