#!/bin/bash
# Traefik access-mode helpers.

auth_policy_access_mode_from_env() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    local domain_mode
    domain_mode=$(grep "^DOMAIN_MODE=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    domain_mode="${domain_mode:-ip}"
    normalize_access_mode "$domain_mode"
}

generate_traefik_service_middlewares() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    local output_file="${2:-${SCRIPT_DIR}/config/traefik/auth/service-middlewares.yml}"
    local access_mode auth_block

    access_mode="$(auth_policy_access_mode_from_env "$env_file")"

    if [[ "$access_mode" == "tunnel" ]]; then
        auth_block='      basicAuth:
        usersFile: /config/traefik/auth/htpasswd-admin'
    else
        auth_block='      headers:
        customResponseHeaders:
          X-WeekendStack-Access-Mode: local'
    fi

    mkdir -p "$(dirname "$output_file")"
    cat > "$output_file" <<EOF
http:
  middlewares:
    monitoring-auth:
$auth_block

    ai-services-auth:
$auth_block

    it-tools-auth:
$auth_block

    searxng-auth:
$auth_block

    docmost-buffer:
      buffering:
        maxRequestBodyBytes: 104857600
        memRequestBodyBytes: 10485760

    guacamole-redirect:
      redirectRegex:
        regex: "^(https?://[^/]+)/?$"
        replacement: "\${1}/guacamole/"
        permanent: false
EOF
}

refresh_traefik_auth_assets() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    local auth_dir="${2:-${SCRIPT_DIR}/config/traefik/auth}"
    local access_mode tunnel_auth_user tunnel_auth_pass
    local htpasswd_file service_middlewares_file

    mkdir -p "$auth_dir"
    access_mode="$(auth_policy_access_mode_from_env "$env_file")"
    tunnel_auth_user=$(grep "^DEFAULT_TRAEFIK_AUTH_USER=" "$env_file" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    tunnel_auth_pass=$(grep "^DEFAULT_TRAEFIK_AUTH_PASS=" "$env_file" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    tunnel_auth_user=${tunnel_auth_user:-admin}

    htpasswd_file="$auth_dir/htpasswd-admin"

    if [[ "$access_mode" == "tunnel" ]]; then
        if [[ -z "$tunnel_auth_pass" ]]; then
            tunnel_auth_pass="pending-$(date +%s)-$RANDOM-$RANDOM"
            log_warn "Tunnel auth is not configured yet. External routes remain locked until you run ./configure.sh --tunnel-auth."
        fi

        if command -v htpasswd >/dev/null 2>&1; then
            htpasswd -nbB "$tunnel_auth_user" "$tunnel_auth_pass" > "$htpasswd_file"
        elif docker info >/dev/null 2>&1; then
            docker run --rm httpd:2-alpine htpasswd -nbB "$tunnel_auth_user" "$tunnel_auth_pass" \
                > "$htpasswd_file" 2>/dev/null
        else
            log_error "Could not generate Traefik auth file. Install apache2-utils or start Docker first."
            return 1
        fi

        if [[ ! -s "$htpasswd_file" ]]; then
            log_error "Failed to generate Traefik auth file at $htpasswd_file"
            return 1
        fi

        chmod 600 "$htpasswd_file"
        for f in "$auth_dir"/htpasswd-test{1,2,3,4}; do
            cp "$htpasswd_file" "$f" 2>/dev/null || true
        done
        log_info "Generated Traefik basic auth: $htpasswd_file (user: $tunnel_auth_user)"
    else
        rm -f "$htpasswd_file" "$auth_dir"/htpasswd-test{1,2,3,4} 2>/dev/null || true
        log_info "Tunnel auth disabled for local-only access"
    fi

    service_middlewares_file="$auth_dir/service-middlewares.yml"
    generate_traefik_service_middlewares "$env_file" "$service_middlewares_file"
    log_info "Configured Traefik service middlewares for access mode: $access_mode"
}

restart_traefik_if_running() {
    if docker ps --filter "name=^traefik$" --format "{{.Names}}" 2>/dev/null | grep -q "^traefik$"; then
        if docker restart traefik >/dev/null 2>&1; then
            log_success "Restarted Traefik to apply updated access authentication"
        else
            log_warn "Could not restart Traefik automatically. Run 'docker restart traefik' if auth changes do not appear."
        fi
    else
        log_info "Traefik is not running yet. Updated auth will apply on the next start."
    fi
}

export -f auth_policy_access_mode_from_env generate_traefik_service_middlewares refresh_traefik_auth_assets restart_traefik_if_running
