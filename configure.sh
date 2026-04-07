#!/bin/bash
# WeekendStack post-setup configuration flow
# Handles secrets and external/manual integrations after setup/apply

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup.sh"

CONFIGURE_MODE="all"

show_configure_usage() {
    cat <<EOF
WeekendStack Configure

USAGE:
    ./configure.sh [OPTION]

OPTIONS:
    -h, --help          Show this help message
    --all               Run the guided configure flow (default)
    --status            Show pending configure actions
    --tunnel-auth       Configure or reset tunnel auth credentials
    --cloudflare        Configure or repair Cloudflare Tunnel
    --git-ssh           Link the shared Coder SSH key to GitHub or Gitea
    --coder-templates   Push bundled WeekendStack templates into Coder

EXAMPLES:
    ./configure.sh
    ./configure.sh --all
    ./configure.sh --status
    ./configure.sh --cloudflare
EOF
}

parse_configure_args() {
    if [[ $# -eq 0 ]]; then
        CONFIGURE_MODE="all"
        return 0
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_configure_usage
                exit 0
                ;;
            --all)
                CONFIGURE_MODE="all"
                shift
                ;;
            --status)
                CONFIGURE_MODE="status"
                shift
                ;;
            --tunnel-auth)
                CONFIGURE_MODE="tunnel-auth"
                shift
                ;;
            --cloudflare)
                CONFIGURE_MODE="cloudflare"
                shift
                ;;
            --git-ssh)
                CONFIGURE_MODE="git-ssh"
                shift
                ;;
            --coder-templates)
                CONFIGURE_MODE="coder-templates"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run './configure.sh --help' for usage"
                exit 1
                ;;
        esac
    done
}

configure_require_env() {
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        log_error ".env file not found. Run ./setup.sh first."
        return 1
    fi

    set -a
    source "$SCRIPT_DIR/.env"
    set +a
}

configure_access_mode() {
    auth_policy_access_mode_from_env "$SCRIPT_DIR/.env"
}

configure_profiles_csv() {
    get_env_value "COMPOSE_PROFILES" "$SCRIPT_DIR/.env" 2>/dev/null || true
}

configure_dev_enabled() {
    local profiles_csv
    profiles_csv="$(configure_profiles_csv)"
    [[ ",${profiles_csv}," == *",dev,"* ]]
}

configure_coder_running() {
    docker ps --filter "name=^coder$" --format "{{.Names}}" 2>/dev/null | grep -q "^coder$"
}

configure_templates_already_deployed() {
    [[ -f "$SCRIPT_DIR/config/coder/.template_deployment_complete" ]]
}

configure_refresh_outputs() {
    refresh_setup_outputs
}

configure_show_status() {
    local access_mode tunnel_auth_pass
    local cloudflare_ready=false

    configure_require_env || return 1
    access_mode="$(configure_access_mode)"
    tunnel_auth_pass="$(get_env_value "DEFAULT_TRAEFIK_AUTH_PASS" "$SCRIPT_DIR/.env" 2>/dev/null || true)"
    if check_cloudflare_config; then
        cloudflare_ready=true
    fi

    log_header "WeekendStack Configure Status"

    if [[ "$access_mode" == "tunnel" && -z "$tunnel_auth_pass" ]]; then
        echo "  Pending: ./configure.sh --tunnel-auth"
    elif [[ "$access_mode" == "tunnel" ]]; then
        echo "  Ready:   tunnel auth is configured"
    fi

    if [[ "$access_mode" == "tunnel" && "$cloudflare_ready" == "false" ]]; then
        echo "  Pending: ./configure.sh --cloudflare"
    elif [[ "$access_mode" == "tunnel" ]]; then
        echo "  Ready:   Cloudflare tunnel is configured"
    fi

    if configure_dev_enabled; then
        if configure_templates_already_deployed; then
            echo "  Ready:   Coder templates have been deployed before"
        else
            echo "  Pending: ./configure.sh --coder-templates"
        fi
        echo "  Available: ./configure.sh --git-ssh"
    fi

    if [[ "$access_mode" != "tunnel" ]] && ! configure_dev_enabled; then
        echo "  No configure actions are pending for this install."
    fi
}

configure_tunnel_auth() {
    configure_require_env || return 1
    run_tunnel_auth_setup_only
    configure_refresh_outputs
}

configure_cloudflare() {
    configure_require_env || return 1

    if [[ "$(configure_access_mode)" != "tunnel" ]]; then
        log_error "Cloudflare configure is only available when access mode is Tunnel."
        return 1
    fi

    setup_cloudflare_tunnel
    ensure_cloudflare_in_custom_profile
    start_cloudflare_tunnel_if_configured
    configure_refresh_outputs
}

configure_git_ssh() {
    configure_require_env || return 1
    run_coder_git_ssh_setup_only
    configure_refresh_outputs
}

configure_coder_templates() {
    configure_require_env || return 1

    if ! configure_coder_running; then
        log_error "Coder is not running. Start services first, then rerun ./configure.sh --coder-templates."
        return 1
    fi

    deploy_coder_templates_interactive
    configure_refresh_outputs
}

configure_all() {
    local access_mode tunnel_auth_pass
    local ran_any=false

    configure_require_env || return 1
    access_mode="$(configure_access_mode)"
    tunnel_auth_pass="$(get_env_value "DEFAULT_TRAEFIK_AUTH_PASS" "$SCRIPT_DIR/.env" 2>/dev/null || true)"

    if [[ "$access_mode" == "tunnel" ]]; then
        if [[ -z "$tunnel_auth_pass" ]]; then
            configure_tunnel_auth
            ran_any=true
        else
            log_info "Tunnel auth is already configured"
        fi

        if ! check_cloudflare_config; then
            configure_cloudflare
            ran_any=true
        else
            log_info "Cloudflare tunnel is already configured"
        fi
    fi

    if configure_dev_enabled; then
        if ! configure_coder_running; then
            log_warn "Coder is not running. Start services, then rerun ./configure.sh --all for templates and Git SSH."
        else
            if configure_templates_already_deployed; then
                log_info "Coder templates were already deployed. Use ./configure.sh --coder-templates to redeploy."
            else
                configure_coder_templates
                ran_any=true
            fi

            configure_git_ssh
            ran_any=true
        fi
    fi

    if ! $ran_any; then
        log_success "No configure actions were required."
    fi

    configure_refresh_outputs
}

main() {
    parse_configure_args "$@"
    source "$SCRIPT_DIR/tools/setup/lib/env-generator.sh"
    source "$SCRIPT_DIR/tools/setup/lib/auth-policy.sh"
    source "$SCRIPT_DIR/tools/setup/lib/coder-template-installer.sh"
    source "$SCRIPT_DIR/tools/setup/lib/cloudflare-wizard.sh"
    source "$SCRIPT_DIR/tools/setup/lib/summary.sh"
    source "$SCRIPT_DIR/tools/setup/lib/setup-engine.sh"
    cd "$SCRIPT_DIR"

    case "$CONFIGURE_MODE" in
        all)
            configure_all
            ;;
        status)
            configure_show_status
            ;;
        tunnel-auth)
            configure_tunnel_auth
            ;;
        cloudflare)
            configure_cloudflare
            ;;
        git-ssh)
            configure_git_ssh
            ;;
        coder-templates)
            configure_coder_templates
            ;;
        *)
            log_error "Unknown configure mode: $CONFIGURE_MODE"
            return 1
            ;;
    esac
}

main "$@"
