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

export -f auth_policy_access_mode_from_env generate_traefik_service_middlewares
