#!/bin/bash
# Shared helpers for service auth/bootstrap policy and Traefik access-mode auth.

auth_policy_file() {
    echo "${SCRIPT_DIR}/tools/env/mappings/service-auth-policy.json"
}

auth_policy_profile_map_file() {
    echo "${SCRIPT_DIR}/tools/env/mappings/profile-to-services.json"
}

auth_policy_service_metadata_file() {
    echo "${SCRIPT_DIR}/tools/env/mappings/service-metadata.json"
}

auth_policy_require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required for auth policy operations"
        return 1
    fi
}

auth_policy_get_field() {
    local service="$1"
    local field="$2"
    local policy_file
    policy_file="$(auth_policy_file)"

    auth_policy_require_jq || return 1
    jq -r --arg service "$service" --arg field "$field" \
        '.[$service][$field] // empty' "$policy_file"
}

auth_policy_service_display_name() {
    local service="$1"
    local metadata_file
    metadata_file="$(auth_policy_service_metadata_file)"

    auth_policy_require_jq || return 1
    jq -r --arg service "$service" \
        '.[$service].display_name // $service' "$metadata_file"
}

auth_policy_resolve_services() {
    local -a profiles=("$@")
    local policy_file profile_map_file
    policy_file="$(auth_policy_file)"
    profile_map_file="$(auth_policy_profile_map_file)"

    auth_policy_require_jq || return 1

    if [[ ${#profiles[@]} -eq 0 ]]; then
        return 0
    fi

    local selected_json
    selected_json=$(printf '%s\n' "${profiles[@]}" | jq -R . | jq -s .)

    jq -nr \
        --argjson selected "$selected_json" \
        --slurpfile policy "$policy_file" \
        --slurpfile profiles "$profile_map_file" '
        def top_level_services:
          $policy[0] | keys;

        def selected_services:
          if ($selected | index("all")) != null then
            top_level_services
          else
            [ $selected[] as $profile
              | ($profiles[0][$profile] // [])
              | .[]
              | select($policy[0][.] != null)
            ] | unique
          end;

        selected_services[]
        '
}

auth_policy_bucket_for_service() {
    local service="$1"
    local strategy tier uses_user uses_email uses_password
    strategy="$(auth_policy_get_field "$service" "auth_strategy")"
    tier="$(auth_policy_get_field "$service" "support_tier")"
    uses_user="$(auth_policy_get_field "$service" "uses_default_admin_user")"
    uses_email="$(auth_policy_get_field "$service" "uses_default_admin_email")"
    uses_password="$(auth_policy_get_field "$service" "uses_default_admin_password")"

    case "$strategy" in
        env|cli_init)
            echo "seeded"
            ;;
        access_password)
            if [[ "$uses_password" == "true" ]]; then
                echo "seeded"
            else
                echo "not_applicable"
            fi
            ;;
        token_only)
            echo "manual"
            ;;
        manual)
            if [[ "$tier" == "repo_custom" ]] && \
               [[ "$uses_user" == "true" || "$uses_email" == "true" || "$uses_password" == "true" ]]; then
                echo "seeded"
            else
                echo "manual"
            fi
            ;;
        *)
            echo "not_applicable"
            ;;
    esac
}

auth_policy_seeded_services() {
    local -a profiles=("$@")
    local service
    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        if [[ "$(auth_policy_bucket_for_service "$service")" == "seeded" ]]; then
            echo "$service"
        fi
    done < <(auth_policy_resolve_services "${profiles[@]}")
}

auth_policy_manual_services() {
    local -a profiles=("$@")
    local service
    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        if [[ "$(auth_policy_bucket_for_service "$service")" == "manual" ]]; then
            echo "$service"
        fi
    done < <(auth_policy_resolve_services "${profiles[@]}")
}

auth_policy_not_applicable_services() {
    local -a profiles=("$@")
    local service
    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        if [[ "$(auth_policy_bucket_for_service "$service")" == "not_applicable" ]]; then
            echo "$service"
        fi
    done < <(auth_policy_resolve_services "${profiles[@]}")
}

auth_policy_apply_seed_env_defaults() {
    local env_file="$1"
    local policy_file
    policy_file="$(auth_policy_file)"

    auth_policy_require_jq || return 1

    local final_user final_email final_pass
    final_user=$(grep "^DEFAULT_ADMIN_USER=" "$env_file" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    final_email=$(grep "^DEFAULT_ADMIN_EMAIL=" "$env_file" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    final_pass=$(grep "^DEFAULT_ADMIN_PASSWORD=" "$env_file" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')

    jq -r '
        to_entries[]
        | select(.value.seed_env != null)
        | .key as $service
        | .value.seed_env
        | to_entries[]
        | [
            $service,
            .key,
            (.value.literal // ""),
            (.value.min_length // ""),
            (.value.pad_suffix // "")
          ] | @tsv
    ' "$policy_file" | while IFS=$'\t' read -r service env_var literal min_length pad_suffix; do
        local value="$literal"

        value="${value//\$\{DEFAULT_ADMIN_USER\}/$final_user}"
        value="${value//\$\{DEFAULT_ADMIN_EMAIL\}/$final_email}"
        value="${value//\$\{DEFAULT_ADMIN_PASSWORD\}/$final_pass}"

        if [[ -n "$min_length" ]] && [[ ${#value} -lt $min_length ]]; then
            value="${value}${pad_suffix}"
            log_warn "${service}: ${env_var} required >=${min_length} chars; padded generated value"
        fi

        update_env_var "$env_var" "$value" "$env_file"
    done
}

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

gitea_admin_exec() {
    docker exec -u git gitea /usr/local/bin/gitea "$@" --config /data/gitea/conf/app.ini
}

ensure_gitea_installed() {
    local install_log="/tmp/weekendstack-gitea-install.log"

    if ! docker exec gitea test -f /data/gitea/conf/app.ini 2>/dev/null; then
        log_warn "Gitea config was not created yet"
        return 1
    fi

    if ! docker exec gitea sh -c "grep -q '^INSTALL_LOCK = true$' /data/gitea/conf/app.ini" 2>/dev/null; then
        log_info "Gitea is still in first-run install mode; locking setup and restarting it"
        if ! docker exec gitea sh -c "sed -i 's/^INSTALL_LOCK = false$/INSTALL_LOCK = true/' /data/gitea/conf/app.ini"; then
            log_warn "Failed to update Gitea install lock"
            return 1
        fi
        docker restart gitea >/dev/null 2>&1 || true
    fi

    local attempt
    for attempt in $(seq 1 30); do
        if gitea_admin_exec admin user list --admin >/dev/null 2>"$install_log"; then
            return 0
        fi
        sleep 2
    done

    log_warn "Gitea is not ready for admin bootstrap"
    cat "$install_log" >&2 || true
    return 1
}

bootstrap_gitea_admin() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"

    if ! docker compose ps --services --filter status=running 2>/dev/null | grep -qx "gitea"; then
        log_info "Gitea not running; skipping admin bootstrap"
        return 0
    fi

    local admin_user admin_email admin_pass
    admin_user=$(grep "^DEFAULT_ADMIN_USER=" "$env_file" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    admin_email=$(grep "^DEFAULT_ADMIN_EMAIL=" "$env_file" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    admin_pass=$(grep "^DEFAULT_ADMIN_PASSWORD=" "$env_file" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')

    ensure_gitea_installed || return 1

    if gitea_admin_exec admin user list --admin 2>/dev/null | grep -Eq "(^|[[:space:]])${admin_user}([[:space:]]|$)"; then
        log_info "Gitea admin already exists: ${admin_user}"
        return 0
    fi

    if gitea_admin_exec admin user create \
        --admin \
        --username "$admin_user" \
        --password "$admin_pass" \
        --email "$admin_email" \
        --must-change-password=false >/tmp/weekendstack-gitea-bootstrap.log 2>&1; then
        log_success "Bootstrapped Gitea admin user: ${admin_user}"
    elif grep -qi "already exists" /tmp/weekendstack-gitea-bootstrap.log 2>/dev/null; then
        log_info "Gitea admin already exists: ${admin_user}"
    else
        log_warn "Failed to bootstrap Gitea admin user"
        cat /tmp/weekendstack-gitea-bootstrap.log >&2 || true
        return 1
    fi
}

run_auth_bootstrap_tasks() {
    local env_file="${SCRIPT_DIR}/.env"
    local -a profiles=("$@")
    local service handler status=0

    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        handler="$(auth_policy_get_field "$service" "bootstrap_handler")"
        [[ -z "$handler" ]] && continue

        case "$handler" in
            bootstrap_gitea_admin)
                "$handler" "$env_file" || status=1
                ;;
            *)
                log_warn "Unknown bootstrap handler for ${service}: ${handler}"
                status=1
                ;;
        esac
    done < <(auth_policy_resolve_services "${profiles[@]}")

    return $status
}

export -f auth_policy_file auth_policy_profile_map_file auth_policy_service_metadata_file
export -f auth_policy_get_field auth_policy_service_display_name auth_policy_resolve_services
export -f auth_policy_bucket_for_service auth_policy_seeded_services auth_policy_manual_services auth_policy_not_applicable_services
export -f auth_policy_apply_seed_env_defaults auth_policy_access_mode_from_env generate_traefik_service_middlewares
export -f gitea_admin_exec ensure_gitea_installed bootstrap_gitea_admin run_auth_bootstrap_tasks
