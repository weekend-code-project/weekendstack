#!/bin/bash
# Agent-first setup engine for WeekendStack

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/service-catalog.sh"
source "$(dirname "${BASH_SOURCE[0]}")/post-install-cleanup.sh"

setup_engine_root() {
    if [[ -n "${SCRIPT_DIR:-}" && -d "${SCRIPT_DIR}" ]]; then
        printf '%s\n' "$SCRIPT_DIR"
        return 0
    fi
    cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd
}

setup_engine_default_config_path() {
    printf '%s/weekendstack.config.json\n' "$(setup_engine_root)"
}

setup_engine_state_path() {
    printf '%s/setup-state.json\n' "$(setup_engine_root)"
}

setup_engine_plan_path() {
    printf '%s/setup-plan.json\n' "$(setup_engine_root)"
}

setup_engine_csv_from_lines() {
    awk 'NF && !seen[$0]++' | paste -sd, -
}

setup_engine_json_array_from_csv() {
    local csv="${1:-}"
    jq -nc --arg csv "$csv" '$csv | split(",") | map(select(length > 0))'
}

setup_engine_host_memory_gb() {
    if command -v free >/dev/null 2>&1; then
        free -g | awk '/^Mem:/{print $2; exit}'
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.memsize 2>/dev/null | awk '{printf "%d\n", $1 / 1024 / 1024 / 1024}'
    else
        echo "0"
    fi
}

setup_engine_disk_free_gb() {
    local path="${1:-.}"

    while [[ ! -e "$path" && "$path" != "/" ]]; do
        path="$(dirname "$path")"
    done

    df -Pk "$path" 2>/dev/null | awk 'NR==2 {printf "%d\n", $4 / 1024 / 1024}' | tail -n 1
}

setup_engine_docker_reclaimable_gb() {
    local reclaimable_human reclaimable_bytes

    if ! command -v docker >/dev/null 2>&1; then
        echo "0"
        return 0
    fi

    reclaimable_human="$(get_docker_image_reclaimable_human)"
    reclaimable_bytes="$(human_size_to_bytes "$reclaimable_human")"
    awk -v bytes="${reclaimable_bytes:-0}" 'BEGIN { printf "%d\n", bytes / 1000000000 }'
}

setup_engine_cleanup_mode() {
    local config_file="$1"
    jq -r '.options.cleanup_mode // "auto"' "$config_file"
}

setup_engine_cleanup_can_reclaim_before_apply() {
    local config_file="$1"
    local cleanup_mode
    cleanup_mode="$(setup_engine_cleanup_mode "$config_file")"
    [[ "$cleanup_mode" == "auto" || "$cleanup_mode" == "always" ]]
}

setup_engine_preflight_cleanup_if_needed() {
    local config_file="$1"
    local required_disk="$2"
    local available_root_disk reclaimable_root_disk effective_root_disk

    available_root_disk="$(setup_engine_disk_free_gb "$(setup_engine_root)")"
    reclaimable_root_disk="$(setup_engine_docker_reclaimable_gb)"
    effective_root_disk=$(( available_root_disk + reclaimable_root_disk ))

    if ! setup_engine_cleanup_can_reclaim_before_apply "$config_file"; then
        return 0
    fi

    if (( available_root_disk >= required_disk )); then
        return 0
    fi

    if (( effective_root_disk < required_disk || reclaimable_root_disk <= 0 )); then
        return 0
    fi

    log_info "Root disk is below the current plan requirement. Running safe cleanup first to reclaim Docker image space."
    run_post_install_cleanup
}

setup_engine_compose_variable_names() {
    local root
    root="$(setup_engine_root)"
    if command -v rg >/dev/null 2>&1; then
        rg -o '\$\{[A-Z0-9_]+(?::-[^}]*)?\}' "$root/compose"/*.yml 2>/dev/null \
            | sed -E 's/.*\$\{([A-Z0-9_]+).*/\1/'
    else
        grep -Rho '\${[A-Z0-9_]\+\(:-[^}]*\)\?}' "$root/compose"/*.yml 2>/dev/null \
            | sed -E 's/.*\$\{([A-Z0-9_]+).*/\1/'
    fi | awk 'NF && !seen[$0]++'
}

setup_engine_backfill_optional_compose_vars() {
    local env_file="$1"
    local var_name

    while IFS= read -r var_name; do
        [[ -z "$var_name" ]] && continue
        if ! grep -q "^${var_name}=" "$env_file" 2>/dev/null; then
            printf '%s=\n' "$var_name" >> "$env_file"
        fi
    done < <(setup_engine_compose_variable_names)
}

setup_engine_gpu_available() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo "true"
    else
        echo "false"
    fi
}

setup_engine_service_selected_in_profiles() {
    local service="$1"
    local profiles_csv="$2"
    local activation_profile
    local profiles_sentinel=",${profiles_csv},"

    while IFS= read -r activation_profile; do
        [[ -z "$activation_profile" ]] && continue
        if [[ "$profiles_sentinel" != *",${activation_profile},"* ]]; then
            return 1
        fi
    done < <(catalog_service_activation_profiles "$service")

    return 0
}

setup_engine_resolve_config_path() {
    local requested="${1:-}"
    local default_path
    default_path="$(setup_engine_default_config_path)"

    if [[ -n "$requested" ]]; then
        printf '%s\n' "$requested"
    else
        printf '%s\n' "$default_path"
    fi
}

setup_engine_migrate_env_to_config() {
    local env_file="${1:-$(setup_engine_root)/.env}"
    local config_file="${2:-$(setup_engine_default_config_path)}"
    local compose_profiles_csv selected_profiles_source selected_profiles_csv selected_services_csv ai_runtime
    local access_mode local_dns_mode
    local -a selected_profiles=()
    local -a selected_services=()
    local profile service visible_profiles

    if [[ ! -f "$env_file" ]]; then
        log_error "Cannot migrate to config: .env not found at $env_file"
        return 1
    fi

    compose_profiles_csv="$(get_env_value "COMPOSE_PROFILES" "$env_file" 2>/dev/null || true)"
    selected_profiles_source="$(get_env_value "SELECTED_PROFILES" "$env_file" 2>/dev/null || true)"
    if [[ -z "$selected_profiles_source" ]]; then
        selected_profiles_source="$compose_profiles_csv"
    fi
    access_mode="$(normalize_access_mode "$(get_env_value "DOMAIN_MODE" "$env_file" 2>/dev/null || echo "ip")")"

    while IFS= read -r profile; do
        [[ -z "$profile" ]] && continue
        if [[ ",${selected_profiles_source}," == *",${profile},"* ]]; then
            selected_profiles+=("$profile")
        fi
    done < <(catalog_profile_ids selectable)
    if [[ ${#selected_profiles[@]} -eq 0 ]]; then
        if [[ ",${selected_profiles_source}," == *",all,"* ]]; then
            selected_profiles=("all")
        else
            selected_profiles=("core")
        fi
    fi

    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        if setup_engine_service_selected_in_profiles "$service" "$compose_profiles_csv"; then
            selected_services+=("$service")
        fi
    done < <(catalog_selectable_service_ids)

    if [[ ",${compose_profiles_csv}," == *",gpu,"* ]]; then
        ai_runtime="gpu"
    elif [[ ",${compose_profiles_csv}," == *",ai,"* ]]; then
        ai_runtime="cpu"
    else
        ai_runtime="none"
    fi

    case "$access_mode" in
        local)
            if [[ ",${compose_profiles_csv}," == *",pihole,"* ]]; then
                local_dns_mode="pihole"
            else
                local_dns_mode="manual"
            fi
            ;;
        *)
            local_dns_mode="none"
            ;;
    esac

    selected_profiles_csv="$(printf '%s\n' "${selected_profiles[@]}" | setup_engine_csv_from_lines)"
    selected_services_csv="$(printf '%s\n' "${selected_services[@]}" | setup_engine_csv_from_lines)"

    jq -n \
        --arg version "1" \
        --arg computer_name "$(get_env_value "COMPUTER_NAME" "$env_file" 2>/dev/null || hostname)" \
        --arg host_ip "$(get_env_value "HOST_IP" "$env_file" 2>/dev/null || true)" \
        --arg timezone "$(get_env_value "TZ" "$env_file" 2>/dev/null || echo "America/New_York")" \
        --arg puid "$(get_env_value "PUID" "$env_file" 2>/dev/null || id -u)" \
        --arg pgid "$(get_env_value "PGID" "$env_file" 2>/dev/null || id -g)" \
        --arg access_mode "$access_mode" \
        --arg lab_domain "$(get_env_value "LAB_DOMAIN" "$env_file" 2>/dev/null || echo "lab")" \
        --arg base_domain "$(get_env_value "BASE_DOMAIN" "$env_file" 2>/dev/null || true)" \
        --arg local_dns_mode "$local_dns_mode" \
        --arg traefik_user "$(get_env_value "DEFAULT_TRAEFIK_AUTH_USER" "$env_file" 2>/dev/null || echo "admin")" \
        --arg traefik_pass "$(get_env_value "DEFAULT_TRAEFIK_AUTH_PASS" "$env_file" 2>/dev/null || true)" \
        --arg profiles_csv "$selected_profiles_csv" \
        --arg services_csv "$selected_services_csv" \
        --arg ai_runtime "$ai_runtime" \
        --arg files_base_dir "$(get_env_value "FILES_BASE_DIR" "$env_file" 2>/dev/null || printf '%s/files' "$(setup_engine_root)")" \
        --arg data_base_dir "$(get_env_value "DATA_BASE_DIR" "$env_file" 2>/dev/null || printf '%s/data' "$(setup_engine_root)")" \
        --arg workspace_dir "$(get_env_value "WORKSPACE_DIR" "$env_file" 2>/dev/null || echo "/mnt/workspace")" \
        --arg ssh_key_dir "$(get_env_value "SSH_KEY_DIR" "$env_file" 2>/dev/null || echo "\${CONFIG_BASE_DIR}/ssh")" \
        --arg cf_api_token "$(get_env_value "CLOUDFLARE_API_TOKEN" "$env_file" 2>/dev/null || true)" \
        --arg cf_tunnel_id "$(get_env_value "CLOUDFLARE_TUNNEL_ID" "$env_file" 2>/dev/null || true)" \
        --arg cf_tunnel_name "$(get_env_value "CLOUDFLARE_TUNNEL_NAME" "$env_file" 2>/dev/null || echo "weekendstack-tunnel")" \
        --arg cf_account_id "$(get_env_value "CLOUDFLARE_ACCOUNT_ID" "$env_file" 2>/dev/null || true)" \
        --arg cf_tunnel_token "$(get_env_value "CLOUDFLARE_TUNNEL_TOKEN" "$env_file" 2>/dev/null || true)" \
        '
        {
          version: ($version | tonumber),
          system: {
            computer_name: $computer_name,
            host_ip: $host_ip,
            timezone: $timezone,
            puid: ($puid | tonumber),
            pgid: ($pgid | tonumber)
          },
          access: {
            mode: $access_mode,
            lab_domain: $lab_domain,
            base_domain: $base_domain,
            local_dns_mode: $local_dns_mode,
            tunnel_auth: {
              username: $traefik_user,
              password: $traefik_pass
            }
          },
          selection: {
            profiles: ($profiles_csv | split(",") | map(select(length > 0))),
            services: ($services_csv | split(",") | map(select(length > 0))),
            ai_runtime: $ai_runtime
          },
          paths: {
            files_base_dir: $files_base_dir,
            data_base_dir: $data_base_dir,
            workspace_dir: $workspace_dir,
            ssh_key_dir: $ssh_key_dir
          },
          cloudflare: {
            enabled: ($access_mode == "tunnel"),
            api_token: $cf_api_token,
            tunnel_id: $cf_tunnel_id,
            tunnel_name: $cf_tunnel_name,
            account_id: $cf_account_id,
            tunnel_token: $cf_tunnel_token
          },
          options: {
            cleanup_mode: "auto"
          }
        }
        ' > "$config_file"

    log_success "Canonical config written to: $config_file"
}

setup_engine_load_or_migrate_config() {
    local requested="${1:-}"
    local config_file

    config_file="$(setup_engine_resolve_config_path "$requested")"
    if [[ -f "$config_file" ]]; then
        printf '%s\n' "$config_file"
        return 0
    fi

    if [[ -f "$(setup_engine_root)/.env" ]]; then
        setup_engine_migrate_env_to_config "$(setup_engine_root)/.env" "$config_file" >/dev/null
        printf '%s\n' "$config_file"
        return 0
    fi

    return 1
}

setup_engine_normalize_config() {
    local config_file="$1"
    local temp_file config_dir root_dir
    config_dir="$(cd "$(dirname "$config_file")" && pwd)"
    root_dir="$(setup_engine_root)"
    temp_file="$(mktemp_in_dir "$config_dir" "$(basename "$config_file").normalize")"

    jq --arg root_dir "$root_dir" '
        .version = (.version // 1)
        | .system.computer_name = (.system.computer_name // "weekendstack")
        | .system.host_ip = (.system.host_ip // "")
        | .system.timezone = (.system.timezone // "America/New_York")
        | .system.puid = (.system.puid // 1000)
        | .system.pgid = (.system.pgid // 1000)
        | .access.mode = (.access.mode // "ip")
        | .access.lab_domain = (.access.lab_domain // "lab")
        | .access.base_domain = (.access.base_domain // "")
        | .access.local_dns_mode = (.access.local_dns_mode // (if .access.mode == "local" then "manual" else "none" end))
        | .access.tunnel_auth.username = (.access.tunnel_auth.username // "admin")
        | .selection.profiles = (
            ((.selection.profiles // ["core"]) + ["core"])
            | reduce .[] as $item ([]; if index($item) then . else . + [$item] end)
          )
        | .selection.services = (
            (.selection.services // [])
            | reduce .[] as $item ([]; if index($item) then . else . + [$item] end)
          )
        | .selection.ai_runtime = (.selection.ai_runtime // (if (.selection.profiles | index("ai")) then "cpu" else "none" end))
        | .paths.files_base_dir = (.paths.files_base_dir // ($root_dir + "/files"))
        | .paths.data_base_dir = (.paths.data_base_dir // ($root_dir + "/data"))
        | .paths.workspace_dir = (.paths.workspace_dir // "/mnt/workspace")
        | .paths.ssh_key_dir = (.paths.ssh_key_dir // "${CONFIG_BASE_DIR}/ssh")
        | .cloudflare.enabled = (.cloudflare.enabled // (.access.mode == "tunnel"))
        | .cloudflare.tunnel_name = (.cloudflare.tunnel_name // "weekendstack-tunnel")
        | .options.cleanup_mode = (.options.cleanup_mode // "auto")
    ' "$config_file" > "$temp_file"

    replace_file_safely "$temp_file" "$config_file"
}

setup_engine_effective_profiles_csv() {
    local config_file="$1"
    local access_mode local_dns_mode ai_runtime base_profiles_csv selected_services_csv
    local cloudflare_ready=false
    access_mode="$(jq -r '.access.mode // "ip"' "$config_file")"
    local_dns_mode="$(jq -r '.access.local_dns_mode // "none"' "$config_file")"
    ai_runtime="$(jq -r '.selection.ai_runtime // "none"' "$config_file")"
    base_profiles_csv="$(jq -r '.selection.profiles // [] | join(",")' "$config_file")"
    selected_services_csv="$(jq -r '.selection.services // [] | join(",")' "$config_file")"
    if [[ "$access_mode" == "tunnel" ]] && \
       { [[ -n "$(jq -r '.cloudflare.api_token // empty' "$config_file")" ]] || [[ -n "$(jq -r '.cloudflare.tunnel_token // empty' "$config_file")" ]]; }; then
        cloudflare_ready=true
    fi

    {
        catalog_build_effective_profiles "$access_mode" "$local_dns_mode" "$ai_runtime" "$base_profiles_csv" "$selected_services_csv"
        if $cloudflare_ready; then
            printf '%s\n' "external"
        fi
    } | setup_engine_csv_from_lines
}

setup_engine_effective_services_csv() {
    local config_file="$1"
    local effective_profiles_csv
    effective_profiles_csv="$(setup_engine_effective_profiles_csv "$config_file")"
    catalog_services_for_activation_profiles "$effective_profiles_csv" | setup_engine_csv_from_lines
}

setup_engine_required_directories_json() {
    local config_file="$1"
    local data_base_dir files_base_dir workspace_dir
    local effective_services_csv service
    local -a dirs=()

    data_base_dir="$(jq -r '.paths.data_base_dir' "$config_file")"
    files_base_dir="$(jq -r '.paths.files_base_dir' "$config_file")"
    workspace_dir="$(jq -r '.paths.workspace_dir' "$config_file")"
    effective_services_csv="$(setup_engine_effective_services_csv "$config_file")"

    dirs+=("$files_base_dir" "$data_base_dir" "$workspace_dir")

    IFS=',' read -r -a effective_services <<< "$effective_services_csv"
    for service in "${effective_services[@]}"; do
        while IFS= read -r required_dir; do
            [[ -z "$required_dir" ]] && continue
            dirs+=("$(setup_engine_root)/$required_dir")
        done < <(catalog_service_required_directories "$service")
    done

    printf '%s\n' "${dirs[@]}" | awk 'NF && !seen[$0]++' | jq -R . | jq -s .
}

setup_engine_configure_actions_json() {
    local config_file="$1"
    local access_mode effective_profiles_csv tunnel_auth_password cloudflare_api_token cloudflare_tunnel_token

    access_mode="$(jq -r '.access.mode // "ip"' "$config_file")"
    effective_profiles_csv="$(setup_engine_effective_profiles_csv "$config_file")"
    tunnel_auth_password="$(jq -r '.access.tunnel_auth.password // ""' "$config_file")"
    cloudflare_api_token="$(jq -r '.cloudflare.api_token // ""' "$config_file")"
    cloudflare_tunnel_token="$(jq -r '.cloudflare.tunnel_token // ""' "$config_file")"

    {
        if [[ "$access_mode" == "tunnel" && -z "$tunnel_auth_password" ]]; then
            jq -nc \
                --arg id "tunnel-auth" \
                --arg title "Configure tunnel auth" \
                --arg command "./configure.sh --tunnel-auth" \
                --arg reason "Tunnel access is selected, but the Traefik auth popup credentials have not been configured yet." \
                '{id:$id, title:$title, command:$command, reason:$reason}'
        fi

        if [[ "$access_mode" == "tunnel" && -z "$cloudflare_api_token" && -z "$cloudflare_tunnel_token" ]]; then
            jq -nc \
                --arg id "cloudflare" \
                --arg title "Configure Cloudflare Tunnel" \
                --arg command "./configure.sh --cloudflare" \
                --arg reason "Tunnel access is selected, but Cloudflare credentials have not been configured yet." \
                '{id:$id, title:$title, command:$command, reason:$reason}'
        fi

        if [[ ",${effective_profiles_csv}," == *",dev,"* ]]; then
            jq -nc \
                --arg id "coder-templates" \
                --arg title "Install Coder templates" \
                --arg command "./configure.sh --coder-templates" \
                --arg reason "Development mode is enabled, so the bundled Coder templates still need to be pushed into the running Coder instance." \
                '{id:$id, title:$title, command:$command, reason:$reason}'
            jq -nc \
                --arg id "git-ssh" \
                --arg title "Link the shared Coder SSH key" \
                --arg command "./configure.sh --git-ssh" \
                --arg reason "Development mode is enabled, so the shared Coder workspace SSH key still needs to be linked to GitHub or Gitea for SSH-based clones." \
                '{id:$id, title:$title, command:$command, reason:$reason}'
        fi
    } | jq -s '.'
}

setup_engine_plan_json() {
    local config_file="$1"
    local effective_profiles_csv effective_services_csv selected_services_csv access_mode base_domain lab_domain host_ip
    local required_memory required_disk available_memory available_root_disk available_data_disk available_effective_root_disk
    local reclaimable_root_disk cleanup_mode gpu_available local_dns_mode
    local blockers_json warnings_json manual_followups_json configure_actions_json

    effective_profiles_csv="$(setup_engine_effective_profiles_csv "$config_file")"
    effective_services_csv="$(setup_engine_effective_services_csv "$config_file")"
    selected_services_csv="$(jq -r '.selection.services // [] | join(",")' "$config_file")"
    access_mode="$(jq -r '.access.mode // "ip"' "$config_file")"
    local_dns_mode="$(jq -r '.access.local_dns_mode // "none"' "$config_file")"
    base_domain="$(jq -r '.access.base_domain // ""' "$config_file")"
    lab_domain="$(jq -r '.access.lab_domain // "lab"' "$config_file")"
    host_ip="$(jq -r '.system.host_ip // ""' "$config_file")"

    read -r required_memory required_disk <<< "$(catalog_sum_resources "$effective_profiles_csv" "$selected_services_csv")"
    available_memory="$(setup_engine_host_memory_gb)"
    available_root_disk="$(setup_engine_disk_free_gb "$(setup_engine_root)")"
    available_data_disk="$(setup_engine_disk_free_gb "$(jq -r '.paths.data_base_dir' "$config_file")")"
    cleanup_mode="$(setup_engine_cleanup_mode "$config_file")"
    reclaimable_root_disk="0"
    available_effective_root_disk="$available_root_disk"
    if setup_engine_cleanup_can_reclaim_before_apply "$config_file"; then
        reclaimable_root_disk="$(setup_engine_docker_reclaimable_gb)"
        available_effective_root_disk=$(( available_root_disk + reclaimable_root_disk ))
    fi
    gpu_available="$(setup_engine_gpu_available)"

    blockers_json="$(
        {
            if [[ "$available_memory" -lt "$required_memory" ]]; then
                printf 'Host RAM below requirement: %sGB available, %sGB required\n' "$available_memory" "$required_memory"
            fi
            if [[ "$available_effective_root_disk" -lt "$required_disk" ]]; then
                printf 'Root disk below requirement: %sGB available now, %sGB effective after safe cleanup, %sGB required\n' "$available_root_disk" "$available_effective_root_disk" "$required_disk"
            fi
            if [[ "$(jq -r '.selection.ai_runtime // "none"' "$config_file")" == "gpu" && "$gpu_available" != "true" ]]; then
                printf 'GPU runtime requested but no NVIDIA GPU was detected\n'
            fi
        } | jq -R . | jq -s .
    )"

    warnings_json="$(
        {
            if [[ "$access_mode" == "tunnel" && -z "$(jq -r '.access.tunnel_auth.password // empty' "$config_file")" ]]; then
                printf 'Tunnel mode is selected but tunnel auth is not configured yet; run ./configure.sh --tunnel-auth after setup.\n'
            fi
            if [[ "$access_mode" == "tunnel" && -z "$(jq -r '.cloudflare.api_token // empty' "$config_file")" && -z "$(jq -r '.cloudflare.tunnel_token // empty' "$config_file")" ]]; then
                printf 'Tunnel mode is selected but no Cloudflare API token is configured; external routing will remain pending.\n'
            fi
            if [[ "$access_mode" == "local" && "$local_dns_mode" == "manual" ]]; then
                printf 'Local domain mode is selected with manual DNS; wildcard DNS must be configured outside WeekendStack.\n'
            fi
            if [[ "$available_data_disk" -lt 10 ]]; then
                printf 'Configured data path has less than 10GB free space.\n'
            fi
            if [[ "$available_root_disk" -lt "$required_disk" && "$available_effective_root_disk" -ge "$required_disk" ]]; then
                printf 'Root disk is currently tight, but %sGB can be reclaimed from unused Docker images before apply (cleanup_mode=%s).\n' "$reclaimable_root_disk" "$cleanup_mode"
            fi
        } | jq -R . | jq -s .
    )"

    manual_followups_json="$(catalog_manual_followups_json "$effective_services_csv" "$access_mode" "$base_domain" "$lab_domain" "$host_ip")"
    configure_actions_json="$(setup_engine_configure_actions_json "$config_file")"

    jq -n \
        --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg config_file "$config_file" \
        --arg access_mode "$access_mode" \
        --arg effective_profiles_csv "$effective_profiles_csv" \
        --arg effective_services_csv "$effective_services_csv" \
        --argjson blockers "$blockers_json" \
        --argjson warnings "$warnings_json" \
        --argjson required_directories "$(setup_engine_required_directories_json "$config_file")" \
        --argjson selected_profiles "$(jq '.selection.profiles // []' "$config_file")" \
        --argjson selected_services "$(jq '.selection.services // []' "$config_file")" \
        --argjson manual_followups "$manual_followups_json" \
        --argjson configure_actions "$configure_actions_json" \
        --argjson cleanup_mode "$(jq '.options.cleanup_mode' "$config_file")" \
        --argjson generated_artifacts '[".env","docker-compose.custom.yml","SETUP_SUMMARY.md","setup-state.json"]' \
        --arg required_memory "$required_memory" \
        --arg required_disk "$required_disk" \
        --arg available_memory "$available_memory" \
        --arg available_root_disk "$available_root_disk" \
        --arg reclaimable_root_disk "$reclaimable_root_disk" \
        --arg available_effective_root_disk "$available_effective_root_disk" \
        --arg available_data_disk "$available_data_disk" \
        --arg gpu_available "$gpu_available" \
        '
        {
          version: 1,
          generated_at: $generated_at,
          config_file: $config_file,
          access_mode: $access_mode,
          selected_profiles: $selected_profiles,
          selected_services: $selected_services,
          effective_profiles: ($effective_profiles_csv | split(",") | map(select(length > 0))),
          effective_services: ($effective_services_csv | split(",") | map(select(length > 0))),
          generated_artifacts: $generated_artifacts,
          required_directories: $required_directories,
          resources: {
            required_memory_gb: ($required_memory | tonumber),
            required_disk_gb: ($required_disk | tonumber)
          },
          host_checks: {
            available_memory_gb: ($available_memory | tonumber),
            available_root_disk_gb: ($available_root_disk | tonumber),
            reclaimable_root_disk_gb: ($reclaimable_root_disk | tonumber),
            available_effective_root_disk_gb: ($available_effective_root_disk | tonumber),
            available_data_disk_gb: ($available_data_disk | tonumber),
            gpu_available: ($gpu_available == "true"),
            blockers: $blockers,
            warnings: $warnings
          },
          cleanup: {
            mode: $cleanup_mode,
            safe_targets: [
              "unused Docker images",
              "Docker builder cache",
              "apt cache",
              "old journal logs"
            ],
            preserve_targets: [
              "registry cache data",
              "named volumes",
              "selected service data",
              "currently required images"
            ]
          },
          manual_followups: $manual_followups,
          configure_actions: $configure_actions
        }
        '
}

setup_engine_write_plan_file() {
    local config_file="$1"
    setup_engine_plan_json "$config_file" > "$(setup_engine_plan_path)"
}

setup_engine_render_plan_text() {
    local plan_file="${1:-$(setup_engine_plan_path)}"
    local blockers_count warnings_count manual_count configure_count
    blockers_count="$(jq '.host_checks.blockers | length' "$plan_file")"
    warnings_count="$(jq '.host_checks.warnings | length' "$plan_file")"
    manual_count="$(jq '.manual_followups | length' "$plan_file")"
    configure_count="$(jq '.configure_actions | length' "$plan_file")"

    log_header "WeekendStack Plan"
    echo "  Config: $(jq -r '.config_file' "$plan_file")"
    echo "  Access mode: $(jq -r '.access_mode' "$plan_file")"
    echo "  Effective profiles: $(jq -r '.effective_profiles | join(", ")' "$plan_file")"
    echo "  Effective services: $(jq -r '.effective_services | length' "$plan_file") services"
    echo "  Resource estimate: $(jq -r '.resources.required_memory_gb' "$plan_file")GB RAM, $(jq -r '.resources.required_disk_gb' "$plan_file")GB disk"
    echo "  Root disk available: $(jq -r '.host_checks.available_root_disk_gb' "$plan_file")GB now, $(jq -r '.host_checks.available_effective_root_disk_gb' "$plan_file")GB after safe cleanup"
    echo ""

    if (( blockers_count > 0 )); then
        log_error "Blocking issues:"
        jq -r '.host_checks.blockers[] | "  - " + .' "$plan_file"
        echo ""
    else
        log_success "No blocking host issues detected"
    fi

    if (( warnings_count > 0 )); then
        log_warn "Warnings:"
        jq -r '.host_checks.warnings[] | "  - " + .' "$plan_file"
        echo ""
    fi

    if (( manual_count > 0 )); then
        log_info "Manual follow-ups:"
        jq -r '.manual_followups[] | "  - " + .display_name + " (" + .mode + ")" + (if .url != "" then ": " + .url else "" end)' "$plan_file"
        echo ""
    fi

    if (( configure_count > 0 )); then
        log_info "Run configure.sh after setup:"
        jq -r '.configure_actions[] | "  - " + .command + " — " + .reason' "$plan_file"
        echo ""
    fi

    log_info "Machine-readable plan saved to $(setup_engine_plan_path)"
}

setup_engine_write_env_from_config() {
    local config_file="$1"
    local env_file="${2:-$(setup_engine_root)/.env}"
    local root temp_template effective_profiles_csv access_mode local_dns_mode ai_runtime selected_profiles_csv selected_services_csv
    local computer_name host_ip timezone puid pgid lab_domain base_domain files_dir data_dir workspace_dir ssh_key_dir
    local traefik_auth_user traefik_auth_password git_service

    root="$(setup_engine_root)"
    setup_engine_normalize_config "$config_file"

    access_mode="$(jq -r '.access.mode // "ip"' "$config_file")"
    local_dns_mode="$(jq -r '.access.local_dns_mode // "none"' "$config_file")"
    ai_runtime="$(jq -r '.selection.ai_runtime // "none"' "$config_file")"
    selected_profiles_csv="$(jq -r '.selection.profiles // [] | join(",")' "$config_file")"
    selected_services_csv="$(jq -r '.selection.services // [] | join(",")' "$config_file")"
    effective_profiles_csv="$(setup_engine_effective_profiles_csv "$config_file")"

    computer_name="$(jq -r '.system.computer_name' "$config_file")"
    host_ip="$(jq -r '.system.host_ip' "$config_file")"
    timezone="$(jq -r '.system.timezone' "$config_file")"
    puid="$(jq -r '.system.puid' "$config_file")"
    pgid="$(jq -r '.system.pgid' "$config_file")"
    lab_domain="$(jq -r '.access.lab_domain // "lab"' "$config_file")"
    base_domain="$(jq -r '.access.base_domain // ""' "$config_file")"
    files_dir="$(jq -r '.paths.files_base_dir' "$config_file")"
    data_dir="$(jq -r '.paths.data_base_dir' "$config_file")"
    workspace_dir="$(jq -r '.paths.workspace_dir' "$config_file")"
    ssh_key_dir="$(jq -r '.paths.ssh_key_dir' "$config_file")"
    traefik_auth_user="$(jq -r '.access.tunnel_auth.username // "admin"' "$config_file")"
    traefik_auth_password="$(jq -r '.access.tunnel_auth.password // ""' "$config_file")"

    temp_template="${root}/.env.tmp"
    "${root}/tools/env/scripts/assemble-env.sh" --profiles "$effective_profiles_csv" --output "$temp_template" >/dev/null
    "${root}/tools/env-template-gen.sh" "$temp_template" "$env_file" >/dev/null
    rm -f "$temp_template"

    update_env_var "COMPUTER_NAME" "$computer_name" "$env_file"
    update_env_var "HOST_IP" "$host_ip" "$env_file"
    update_env_var "TZ" "$timezone" "$env_file"
    update_env_var "PUID" "$puid" "$env_file"
    update_env_var "PGID" "$pgid" "$env_file"
    update_env_var "LAB_DOMAIN" "$lab_domain" "$env_file"
    update_env_var "BASE_DOMAIN" "$base_domain" "$env_file"
    update_env_var "DOMAIN_MODE" "$access_mode" "$env_file"
    update_env_var "LOCAL_DNS_MODE" "$local_dns_mode" "$env_file"
    update_env_var "FILES_BASE_DIR" "$files_dir" "$env_file"
    update_env_var "DATA_BASE_DIR" "$data_dir" "$env_file"
    update_env_var "WORKSPACE_DIR" "$workspace_dir" "$env_file"
    update_env_var "SSH_KEY_DIR" "$ssh_key_dir" "$env_file"

    if [[ "$access_mode" == "tunnel" ]]; then
        update_env_var "DEFAULT_TRAEFIK_AUTH_USER" "$traefik_auth_user" "$env_file"
        update_env_var "DEFAULT_TRAEFIK_AUTH_PASS" "$traefik_auth_password" "$env_file"
    fi

    if jq -e '.cloudflare.api_token != ""' "$config_file" >/dev/null 2>&1; then
        update_env_var "CLOUDFLARE_API_TOKEN" "$(jq -r '.cloudflare.api_token' "$config_file")" "$env_file"
    fi
    if jq -e '.cloudflare.tunnel_id != ""' "$config_file" >/dev/null 2>&1; then
        update_env_var "CLOUDFLARE_TUNNEL_ID" "$(jq -r '.cloudflare.tunnel_id' "$config_file")" "$env_file"
    fi
    if jq -e '.cloudflare.tunnel_name != ""' "$config_file" >/dev/null 2>&1; then
        update_env_var "CLOUDFLARE_TUNNEL_NAME" "$(jq -r '.cloudflare.tunnel_name' "$config_file")" "$env_file"
    fi
    if jq -e '.cloudflare.account_id != ""' "$config_file" >/dev/null 2>&1; then
        update_env_var "CLOUDFLARE_ACCOUNT_ID" "$(jq -r '.cloudflare.account_id' "$config_file")" "$env_file"
    fi
    if jq -e '.cloudflare.tunnel_token != ""' "$config_file" >/dev/null 2>&1; then
        update_env_var "CLOUDFLARE_TUNNEL_TOKEN" "$(jq -r '.cloudflare.tunnel_token' "$config_file")" "$env_file"
    fi

    git_service="none"
    if [[ ",${selected_services_csv}," == *",gitea,"* ]]; then
        git_service="gitea"
    elif [[ ",${selected_services_csv}," == *",gitlab,"* ]]; then
        git_service="gitlab"
    fi
    update_env_var "GIT_SERVICE" "$git_service" "$env_file"

    if [[ ",${selected_profiles_csv}," == *",dev,"* ]]; then
        case "$access_mode" in
            tunnel)
                update_env_var "CODER_ACCESS_URL" "https://coder.${base_domain}" "$env_file"
                ;;
            local)
                update_env_var "CODER_ACCESS_URL" "https://coder.${lab_domain}" "$env_file"
                ;;
            *)
                update_env_var "CODER_ACCESS_URL" "http://${host_ip}:7080" "$env_file"
                ;;
        esac
    fi

    if [[ "$access_mode" == "tunnel" && -n "$base_domain" ]]; then
        update_env_var "DOCMOST_APP_URL" "https://docmost.${base_domain}" "$env_file"
        update_env_var "POSTIZ_MAIN_URL" "https://postiz.${base_domain}" "$env_file"
        update_env_var "POSTIZ_FRONTEND_URL" "https://postiz.${base_domain}" "$env_file"
        update_env_var "POSTIZ_NEXT_PUBLIC_BACKEND_URL" "https://postiz.${base_domain}/api" "$env_file"
        update_env_var "POSTIZ_NEXTAUTH_URL" "https://postiz.${base_domain}" "$env_file"
        update_env_var "POSTIZ_BASE_URL" "https://postiz.${base_domain}" "$env_file"
        update_env_var "NOCODB_PUBLIC_URL" "https://nocodb.${base_domain}" "$env_file"
        update_env_var "SPEEDTEST_APP_URL" "https://speedtest.${base_domain}" "$env_file"
    elif [[ "$access_mode" == "local" ]]; then
        update_env_var "DOCMOST_APP_URL" "https://docmost.${lab_domain}" "$env_file"
        update_env_var "POSTIZ_MAIN_URL" "https://postiz.${lab_domain}" "$env_file"
        update_env_var "POSTIZ_FRONTEND_URL" "https://postiz.${lab_domain}" "$env_file"
        update_env_var "POSTIZ_NEXT_PUBLIC_BACKEND_URL" "https://postiz.${lab_domain}/api" "$env_file"
        update_env_var "POSTIZ_NEXTAUTH_URL" "https://postiz.${lab_domain}" "$env_file"
        update_env_var "POSTIZ_BASE_URL" "https://postiz.${lab_domain}" "$env_file"
        update_env_var "NOCODB_PUBLIC_URL" "https://nocodb.${lab_domain}" "$env_file"
        update_env_var "SPEEDTEST_APP_URL" "https://speedtest.${lab_domain}" "$env_file"
    fi

    if [[ ",${selected_services_csv}," == *",paperclip,"* ]]; then
        case "$access_mode" in
            tunnel)
                update_env_var "PAPERCLIP_PUBLIC_URL" "https://paperclip.${base_domain}" "$env_file"
                update_env_var "PAPERCLIP_ALLOWED_HOSTNAMES" "paperclip.${base_domain},localhost,127.0.0.1" "$env_file"
                update_env_var "PAPERCLIP_DEPLOYMENT_EXPOSURE" "public" "$env_file"
                ;;
            local)
                update_env_var "PAPERCLIP_PUBLIC_URL" "https://paperclip.${lab_domain}" "$env_file"
                update_env_var "PAPERCLIP_ALLOWED_HOSTNAMES" "paperclip.${lab_domain},localhost,127.0.0.1" "$env_file"
                update_env_var "PAPERCLIP_DEPLOYMENT_EXPOSURE" "private" "$env_file"
                ;;
            *)
                update_env_var "PAPERCLIP_PUBLIC_URL" "http://${host_ip}:${PAPERCLIP_PORT:-3100}" "$env_file"
                update_env_var "PAPERCLIP_ALLOWED_HOSTNAMES" "${host_ip},localhost,127.0.0.1" "$env_file"
                update_env_var "PAPERCLIP_DEPLOYMENT_EXPOSURE" "private" "$env_file"
                ;;
        esac
        update_env_var "PAPERCLIP_DEPLOYMENT_MODE" "authenticated" "$env_file"
    fi

    update_env_var "REGISTRY_DATA_DIR" "${data_dir}/registry-cache" "$env_file"
    update_env_var "REGISTRY_PORT" "5000" "$env_file"
    update_env_var "REGISTRY_MEMORY_LIMIT" "256m" "$env_file"

    add_setup_metadata "$env_file" $(jq -r '.selection.profiles[]' "$config_file")
    update_env_var "COMPOSE_PROFILES" "$effective_profiles_csv" "$env_file"
    update_env_var "SELECTED_PROFILES" "$selected_profiles_csv" "$env_file"
    setup_engine_backfill_optional_compose_vars "$env_file"

    "${root}/tools/env/scripts/generate-custom-profile.sh" --profiles "$effective_profiles_csv" >/dev/null
}

setup_engine_materialize_config() {
    local config_file="$1"
    local default_config config_file_abs
    default_config="$(setup_engine_default_config_path)"
    config_file_abs="$(cd "$(dirname "$config_file")" 2>/dev/null && pwd)/$(basename "$config_file")"
    if [[ "$config_file_abs" != "$default_config" ]]; then
        cp "$config_file" "$default_config"
    fi
    printf '%s\n' "$default_config"
}

setup_engine_generate_local_certs_noninteractive() {
    local root cert_dir
    root="$(setup_engine_root)"
    cert_dir="$root/config/traefik/certs"
    if [[ -f "$cert_dir/ca-cert.pem" && -f "$cert_dir/cert.pem" && -f "$cert_dir/key.pem" ]]; then
        return 0
    fi

    log_step "Generating local HTTPS certificates..."
    if docker compose --profile=setup up cert-generator >/dev/null 2>&1; then
        log_success "Local HTTPS certificates generated"
    else
        log_warn "Certificate generation did not complete successfully"
    fi
}

setup_engine_validate_generated_env() {
    local root
    root="$(setup_engine_root)"
    (cd "$root" && "$root/tools/validate-env.sh" >/dev/null)
}

setup_engine_capture_filebrowser_password() {
    docker logs --tail 100 filebrowser 2>&1 | sed -n 's/.*randomly generated password: //p' | tail -n 1
}

setup_engine_write_state() {
    local config_file="$1"
    local action="${2:-apply}"
    local repair_scope="${3:-}"
    local state_file
    local effective_profiles_csv effective_services_csv access_mode base_domain lab_domain host_ip root docker_ok
    local generated_creds_json service_entries_json running_services_json followups_json filebrowser_password
    local configure_actions_json
    local service url status health_state

    root="$(setup_engine_root)"
    state_file="$(setup_engine_state_path)"
    effective_profiles_csv="$(setup_engine_effective_profiles_csv "$config_file")"
    effective_services_csv="$(setup_engine_effective_services_csv "$config_file")"
    access_mode="$(jq -r '.access.mode // "ip"' "$config_file")"
    base_domain="$(jq -r '.access.base_domain // ""' "$config_file")"
    lab_domain="$(jq -r '.access.lab_domain // "lab"' "$config_file")"
    host_ip="$(jq -r '.system.host_ip // ""' "$config_file")"
    followups_json="$(catalog_manual_followups_json "$effective_services_csv" "$access_mode" "$base_domain" "$lab_domain" "$host_ip")"
    configure_actions_json="$(setup_engine_configure_actions_json "$config_file")"

    if docker compose version >/dev/null 2>&1; then
        docker_ok=true
    else
        docker_ok=false
    fi

    if $docker_ok; then
        filebrowser_password="$(setup_engine_capture_filebrowser_password)"
        service_entries_json="$(
            {
                first=true
                IFS=',' read -r -a effective_services <<< "$effective_services_csv"
                for service in "${effective_services[@]}"; do
                    [[ -z "$service" ]] && continue
                    local container_id
                    container_id="$(docker compose ps -q "$service" 2>/dev/null | head -n 1)"
                    status="missing"
                    health_state=""
                    if [[ -n "$container_id" ]]; then
                        status="$(docker inspect --format '{{.State.Status}}' "$container_id" 2>/dev/null || echo "unknown")"
                        health_state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container_id" 2>/dev/null || true)"
                    fi
                    url="$(catalog_service_url "$service" "$access_mode" "$base_domain" "$lab_domain" "$host_ip")"
                    if [[ "$first" != true ]]; then
                        printf ','
                    fi
                    jq -nc \
                        --arg service "$service" \
                        --arg display_name "$(catalog_service_field "$service" "display_name" "$service")" \
                        --arg status "$status" \
                        --arg health "$health_state" \
                        --arg url "$url" \
                        '{service:$service, display_name:$display_name, status:$status, health:$health, url:$url}'
                    first=false
                done
            } | { printf '['; cat; printf ']'; }
        )"
    else
        service_entries_json='[]'
        filebrowser_password=""
    fi

    generated_creds_json="$(jq -n \
        --arg access_mode "$access_mode" \
        --arg traefik_user "$(jq -r '.access.tunnel_auth.username // ""' "$config_file")" \
        --arg traefik_pass "$(jq -r '.access.tunnel_auth.password // ""' "$config_file")" \
        --arg filebrowser_password "$filebrowser_password" \
        '
        {
          traefik_auth: (
            if $access_mode == "tunnel" then
              {configured: ($traefik_pass != ""), username: (if $traefik_pass != "" then $traefik_user else "" end)}
            else
              null
            end
          ),
          filebrowser: (
            if $filebrowser_password != "" then
              {username:"admin", password_captured:true, source:"container-logs"}
            else
              null
            end
          )
        }
        '
    )"

    jq -n \
        --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg config_file "$config_file" \
        --arg action "$action" \
        --arg repair_scope "$repair_scope" \
        --argjson selected_profiles "$(jq '.selection.profiles // []' "$config_file")" \
        --argjson selected_services "$(jq '.selection.services // []' "$config_file")" \
        --arg effective_profiles_csv "$effective_profiles_csv" \
        --arg effective_services_csv "$effective_services_csv" \
        --argjson manual_followups "$followups_json" \
        --argjson configure_actions "$configure_actions_json" \
        --argjson generated_credentials "$generated_creds_json" \
        --argjson services "$service_entries_json" \
        '
        {
          version: 1,
          updated_at: $updated_at,
          config_file: $config_file,
          selected_profiles: $selected_profiles,
          selected_services: $selected_services,
          effective_profiles: ($effective_profiles_csv | split(",") | map(select(length > 0))),
          effective_services: ($effective_services_csv | split(",") | map(select(length > 0))),
          generated_artifacts: {
            env: ".env",
            custom_compose: "docker-compose.custom.yml",
            summary: "SETUP_SUMMARY.md"
          },
          generated_credentials: $generated_credentials,
          configure_actions: $configure_actions,
          manual_followups: $manual_followups,
          health: {
            docker_available: true,
            services: $services
          },
          last_action: $action,
          last_repair_scope: $repair_scope
        }
        ' > "$state_file"

    log_info "Machine-readable state saved to $state_file"
}

setup_engine_auto_cleanup() {
    local config_file="$1"
    local cleanup_mode
    cleanup_mode="$(jq -r '.options.cleanup_mode // "auto"' "$config_file")"

    case "$cleanup_mode" in
        never)
            log_info "Skipping post-apply cleanup (cleanup_mode=never)"
            ;;
        always)
            run_post_install_cleanup
            ;;
        *)
            if should_offer_post_install_cleanup; then
                run_post_install_cleanup
            else
                log_info "No automatic cleanup needed"
            fi
            ;;
    esac
}

setup_engine_apply_config() {
    local config_file="$1"
    local canonical_config effective_profiles_csv access_mode required_disk
    local -a effective_profiles=()

    canonical_config="$(setup_engine_materialize_config "$config_file")"
    setup_engine_normalize_config "$canonical_config"
    setup_engine_write_plan_file "$canonical_config"
    if [[ "$(jq '.host_checks.blockers | length' "$(setup_engine_plan_path)")" -gt 0 ]]; then
        setup_engine_render_plan_text "$(setup_engine_plan_path)"
        return 1
    fi

    required_disk="$(jq -r '.resources.required_disk_gb' "$(setup_engine_plan_path)")"
    setup_engine_preflight_cleanup_if_needed "$canonical_config" "$required_disk"
    setup_engine_write_plan_file "$canonical_config"
    if [[ "$(jq '.host_checks.blockers | length' "$(setup_engine_plan_path)")" -gt 0 ]]; then
        setup_engine_render_plan_text "$(setup_engine_plan_path)"
        return 1
    fi

    setup_engine_write_env_from_config "$canonical_config"
    setup_engine_validate_generated_env

    effective_profiles_csv="$(setup_engine_effective_profiles_csv "$canonical_config")"
    IFS=',' read -r -a effective_profiles <<< "$effective_profiles_csv"

    if ! setup_all_directories "${effective_profiles[@]}"; then
        log_error "Failed to create directory structure"
        return 1
    fi

    create_ssh_directory
    create_docker_volumes

    access_mode="$(jq -r '.access.mode // "ip"' "$canonical_config")"
    case "$access_mode" in
        local)
            setup_engine_generate_local_certs_noninteractive
            ;;
        tunnel)
            if [[ -n "$(jq -r '.cloudflare.api_token // empty' "$canonical_config")" ]]; then
                setup_cloudflare_tunnel || log_warn "Cloudflare tunnel remains incomplete; review setup-state.json follow-ups"
            fi
            ;;
    esac

    start_services_with_profiles "${effective_profiles[@]}"
    provision_speedtest_initial_run
    setup_engine_auto_cleanup "$canonical_config"
    setup_engine_write_state "$canonical_config" "apply" ""
    generate_setup_summary "${effective_profiles[@]}"
    display_summary_to_console
}

setup_engine_doctor_json() {
    local config_file="${1:-}"
    local config_exists env_exists state_exists summary_exists custom_profile_exists docker_ok compose_ok
    local expected_profiles_csv current_profiles_csv drift_profiles registry_issue configure_actions_json

    if [[ -n "$config_file" && -f "$config_file" ]]; then
        config_exists=true
    elif [[ -f "$(setup_engine_default_config_path)" ]]; then
        config_file="$(setup_engine_default_config_path)"
        config_exists=true
    else
        config_exists=false
    fi

    [[ -f "$(setup_engine_root)/.env" ]] && env_exists=true || env_exists=false
    [[ -f "$(setup_engine_state_path)" ]] && state_exists=true || state_exists=false
    [[ -f "$(setup_engine_root)/SETUP_SUMMARY.md" ]] && summary_exists=true || summary_exists=false
    [[ -f "$(setup_engine_root)/docker-compose.custom.yml" ]] && custom_profile_exists=true || custom_profile_exists=false
    docker compose version >/dev/null 2>&1 && compose_ok=true || compose_ok=false
    docker info >/dev/null 2>&1 && docker_ok=true || docker_ok=false

    expected_profiles_csv=""
    current_profiles_csv=""
    drift_profiles=false
    if $config_exists; then
        expected_profiles_csv="$(setup_engine_effective_profiles_csv "$config_file")"
        configure_actions_json="$(setup_engine_configure_actions_json "$config_file")"
    else
        configure_actions_json='[]'
    fi
    if $env_exists; then
        current_profiles_csv="$(get_env_value "COMPOSE_PROFILES" "$(setup_engine_root)/.env" 2>/dev/null || true)"
    fi
    if [[ -n "$expected_profiles_csv" && -n "$current_profiles_csv" && "$expected_profiles_csv" != "$current_profiles_csv" ]]; then
        drift_profiles=true
    fi

    registry_issue=false
    if type docker_mirror_configured >/dev/null 2>&1 && type is_cache_running >/dev/null 2>&1 && docker_mirror_configured && ! is_cache_running; then
        registry_issue=true
    fi

    jq -n \
        --argjson config_exists "$config_exists" \
        --argjson env_exists "$env_exists" \
        --argjson state_exists "$state_exists" \
        --argjson summary_exists "$summary_exists" \
        --argjson custom_profile_exists "$custom_profile_exists" \
        --argjson docker_ok "$docker_ok" \
        --argjson compose_ok "$compose_ok" \
        --argjson drift_profiles "$drift_profiles" \
        --argjson registry_issue "$registry_issue" \
        --argjson configure_actions "$configure_actions_json" \
        --arg expected_profiles "$expected_profiles_csv" \
        --arg current_profiles "$current_profiles_csv" \
        --arg memory_gb "$(setup_engine_host_memory_gb)" \
        --arg root_disk_gb "$(setup_engine_disk_free_gb "$(setup_engine_root)")" \
        --arg gpu_available "$(setup_engine_gpu_available)" \
        '
        {
          version: 1,
          checked_at: (now | todateiso8601),
          files: {
            config_exists: $config_exists,
            env_exists: $env_exists,
            state_exists: $state_exists,
            summary_exists: $summary_exists,
            custom_profile_exists: $custom_profile_exists
          },
          host: {
            docker_available: $docker_ok,
            compose_available: $compose_ok,
            memory_gb: ($memory_gb | tonumber),
            root_disk_gb: ($root_disk_gb | tonumber),
            gpu_available: ($gpu_available == "true")
          },
          drift: {
            expected_profiles: ($expected_profiles | split(",") | map(select(length > 0))),
            current_profiles: ($current_profiles | split(",") | map(select(length > 0))),
            compose_profiles_mismatch: $drift_profiles,
            registry_cache_mirror_broken: $registry_issue
          },
          configure_actions: $configure_actions
        }
        '
}

setup_engine_doctor() {
    local config_file="${1:-}"
    local json_file
    json_file="$(mktemp)"
    setup_engine_doctor_json "$config_file" > "$json_file"

    log_header "WeekendStack Doctor"
    jq -r '
      "  Config file: " + (if .files.config_exists then "present" else "missing" end),
      "  Env file: " + (if .files.env_exists then "present" else "missing" end),
      "  State file: " + (if .files.state_exists then "present" else "missing" end),
      "  Docker: " + (if .host.docker_available then "ok" else "missing/offline" end),
      "  Compose: " + (if .host.compose_available then "ok" else "missing" end),
      "  Host RAM: " + (.host.memory_gb|tostring) + "GB",
      "  Root disk free: " + (.host.root_disk_gb|tostring) + "GB"
    ' "$json_file"
    echo ""
    if jq -e '.drift.compose_profiles_mismatch or .drift.registry_cache_mirror_broken or (.files.config_exists|not) or (.files.env_exists|not)' "$json_file" >/dev/null; then
        log_warn "Issues detected:"
        jq -r '
            if (.files.config_exists|not) then "  - Canonical config is missing" else empty end,
            if (.files.env_exists|not) then "  - Generated .env is missing" else empty end,
            if .drift.compose_profiles_mismatch then "  - Config and .env COMPOSE_PROFILES differ" else empty end,
            if .drift.registry_cache_mirror_broken then "  - Docker mirror points at a dead registry cache" else empty end
        ' "$json_file"
    else
        log_success "No infrastructure drift detected"
    fi

    if jq -e '.configure_actions | length > 0' "$json_file" >/dev/null; then
        echo ""
        log_info "Configure next:"
        jq -r '.configure_actions[] | "  - " + .command + " — " + .reason' "$json_file"
    fi

    rm -f "$json_file"
}

setup_engine_add_to_config() {
    local config_file="$1"
    local profiles_csv="${2:-}"
    local services_csv="${3:-}"
    local temp_file config_dir
    config_dir="$(cd "$(dirname "$config_file")" && pwd)"
    temp_file="$(mktemp_in_dir "$config_dir" "$(basename "$config_file").add")"

    jq \
        --arg profiles_csv "$profiles_csv" \
        --arg services_csv "$services_csv" \
        '
        .selection.profiles = (
            ((.selection.profiles // []) + ($profiles_csv | split(",") | map(select(length > 0))))
            | reduce .[] as $item ([]; if index($item) then . else . + [$item] end)
          )
        | .selection.services = (
            ((.selection.services // []) + ($services_csv | split(",") | map(select(length > 0))))
            | reduce .[] as $item ([]; if index($item) then . else . + [$item] end)
          )
        ' "$config_file" > "$temp_file"
    replace_file_safely "$temp_file" "$config_file"
    setup_engine_normalize_config "$config_file"
}

setup_engine_repair() {
    local config_file="$1"
    local scope="${2:-infra}"
    local effective_profiles_csv
    local -a effective_profiles=()

    config_file="$(setup_engine_load_or_migrate_config "$config_file")" || {
        log_error "No config or .env available to repair"
        return 1
    }
    setup_engine_normalize_config "$config_file"
    setup_engine_write_env_from_config "$config_file"
    effective_profiles_csv="$(setup_engine_effective_profiles_csv "$config_file")"
    IFS=',' read -r -a effective_profiles <<< "$effective_profiles_csv"

    case "$scope" in
        infra)
            setup_all_directories "${effective_profiles[@]}"
            create_ssh_directory
            create_docker_volumes
            preflight_fix_mounts
            prepare_registry_cache_for_startup
            start_services_with_profiles "${effective_profiles[@]}"
            ;;
        cache)
            prepare_registry_cache_for_startup
            ;;
        network)
            preflight_fix_mounts
            if [[ "$(jq -r '.access.mode' "$config_file")" == "local" ]]; then
                setup_engine_generate_local_certs_noninteractive
            fi
            if [[ "$(jq -r '.access.mode' "$config_file")" == "tunnel" ]] && [[ -n "$(jq -r '.cloudflare.api_token // empty' "$config_file")" ]]; then
                setup_cloudflare_tunnel || true
            fi
            start_services_with_profiles "${effective_profiles[@]}"
            ;;
        auth)
            refresh_traefik_auth_assets "$(setup_engine_root)/.env"
            docker restart traefik >/dev/null 2>&1 || true
            ;;
        storage)
            setup_all_directories "${effective_profiles[@]}"
            create_docker_volumes
            ;;
        *)
            log_error "Unknown repair scope: $scope"
            return 1
            ;;
    esac

    generate_setup_summary "${effective_profiles[@]}"
    setup_engine_write_state "$config_file" "repair" "$scope"
}

export -f setup_engine_root setup_engine_default_config_path setup_engine_state_path
export -f setup_engine_plan_path setup_engine_migrate_env_to_config
export -f setup_engine_load_or_migrate_config setup_engine_normalize_config
export -f setup_engine_effective_profiles_csv setup_engine_effective_services_csv
export -f setup_engine_configure_actions_json
export -f setup_engine_plan_json setup_engine_write_plan_file setup_engine_render_plan_text
export -f setup_engine_write_env_from_config setup_engine_apply_config
export -f setup_engine_doctor_json setup_engine_doctor setup_engine_add_to_config
export -f setup_engine_repair setup_engine_write_state
