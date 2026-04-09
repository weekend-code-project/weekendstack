#!/bin/bash
# Catalog-driven setup summary generator

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/service-catalog.sh"
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/auth-policy.sh" ]]; then
    # shellcheck source=./auth-policy.sh
    source "$(dirname "${BASH_SOURCE[0]}")/auth-policy.sh"
fi

summary_stack_dir() {
    if [[ -n "${SCRIPT_DIR:-}" && -d "${SCRIPT_DIR}" ]]; then
        printf '%s\n' "${SCRIPT_DIR}"
        return 0
    fi

    cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd
}

summary_env_file() {
    printf '%s/.env\n' "$(summary_stack_dir)"
}

summary_state_file() {
    printf '%s/setup-state.json\n' "$(summary_stack_dir)"
}

summary_csv_from_lines() {
    awk 'NF && !seen[$0]++' | paste -sd, -
}

summary_env_value() {
    local key="$1"
    local default_value="${2:-}"
    local value=""
    value="$(get_env_value "$key" "$(summary_env_file)" 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$default_value"
    fi
}

summary_access_mode() {
    normalize_access_mode "$(summary_env_value "DOMAIN_MODE" "ip")"
}

summary_state_matches_env() {
    local state_file env_profiles state_profiles env_mode state_mode
    state_file="$(summary_state_file)"
    [[ -f "$state_file" ]] || return 1

    env_profiles="$(summary_env_value "COMPOSE_PROFILES" "")"
    env_mode="$(summary_access_mode)"
    state_profiles="$(jq -r '.effective_profiles | join(",")' "$state_file" 2>/dev/null || true)"
    state_mode="$(jq -r '.access_mode // empty' "$state_file" 2>/dev/null || true)"

    if [[ -n "$env_profiles" && -n "$state_profiles" && "$env_profiles" != "$state_profiles" ]]; then
        return 1
    fi

    if [[ -n "$state_mode" && "$env_mode" != "$state_mode" ]]; then
        return 1
    fi

    return 0
}

summary_access_heading() {
    case "$1" in
        tunnel) echo "External Access (Cloudflare Tunnel)" ;;
        local) echo "Local Domain Access" ;;
        *) echo "Local IP Access" ;;
    esac
}

summary_access_intro() {
    local access_mode="$1"
    local host_ip="$2"
    local base_domain="$3"
    local lab_domain="$4"

    case "$access_mode" in
        tunnel) echo "Your WeekendStack is reachable through Cloudflare Tunnel on \`.${base_domain}\` URLs." ;;
        local) echo "Your WeekendStack is reachable on your LAN through \`.${lab_domain}\` hostnames." ;;
        *) echo "Your WeekendStack is reachable directly by IP on \`${host_ip}\`." ;;
    esac
}

summary_profiles_csv() {
    local explicit_profiles_csv="${1:-}"
    local state_file env_profiles

    state_file="$(summary_state_file)"
    if summary_state_matches_env && jq -e '.effective_profiles | length > 0' "$state_file" >/dev/null 2>&1; then
        jq -r '.effective_profiles | join(",")' "$state_file"
        return 0
    fi

    env_profiles="$(summary_env_value "COMPOSE_PROFILES" "")"
    if [[ -n "$env_profiles" ]]; then
        printf '%s\n' "$env_profiles"
        return 0
    fi

    printf '%s\n' "$explicit_profiles_csv"
}

summary_services_csv() {
    local explicit_profiles_csv="${1:-}"
    local state_file profiles_csv

    state_file="$(summary_state_file)"
    if summary_state_matches_env && jq -e '.effective_services | length >= 0' "$state_file" >/dev/null 2>&1; then
        jq -r '.effective_services | join(",")' "$state_file"
        return 0
    fi

    profiles_csv="$(summary_profiles_csv "$explicit_profiles_csv")"
    catalog_services_for_activation_profiles "$profiles_csv" | summary_csv_from_lines
}

summary_configure_actions_json() {
    local state_file access_mode profiles_csv tunnel_auth_password cloudflare_token

    state_file="$(summary_state_file)"
    if summary_state_matches_env && jq -e '.configure_actions' "$state_file" >/dev/null 2>&1; then
        jq -c '.configure_actions' "$state_file"
        return 0
    fi

    access_mode="$(summary_access_mode)"
    profiles_csv="$(summary_profiles_csv)"
    tunnel_auth_password="$(summary_env_value "DEFAULT_TRAEFIK_AUTH_PASS" "")"
    cloudflare_token="$(summary_env_value "CLOUDFLARE_TUNNEL_TOKEN" "$(summary_env_value "CLOUDFLARE_API_TOKEN" "")")"

    {
        if [[ "$access_mode" == "tunnel" && -z "$tunnel_auth_password" ]]; then
            jq -nc \
                --arg id "tunnel-auth" \
                --arg title "Set tunnel auth" \
                --arg command "./configure.sh --tunnel-auth" \
                --arg reason "Tunnel access is selected, but the Traefik auth popup credentials are not configured yet." \
                '{id:$id, title:$title, command:$command, reason:$reason}'
        fi

        if [[ "$access_mode" == "tunnel" && -z "$cloudflare_token" ]]; then
            jq -nc \
                --arg id "cloudflare" \
                --arg title "Configure Cloudflare tunnel" \
                --arg command "./configure.sh --cloudflare" \
                --arg reason "Tunnel access is selected, but Cloudflare tunnel credentials are not configured yet." \
                '{id:$id, title:$title, command:$command, reason:$reason}'
        fi

        if [[ ",${profiles_csv}," == *",dev,"* ]]; then
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
                --arg reason "Development mode is enabled, so the shared Coder workspace SSH key still needs to be linked for SSH-based clones." \
                '{id:$id, title:$title, command:$command, reason:$reason}'
        fi
    } | jq -s '.'
}

summary_manual_followups_json() {
    local explicit_profiles_csv="${1:-}"
    local state_file services_csv access_mode base_domain lab_domain host_ip

    state_file="$(summary_state_file)"
    if summary_state_matches_env && jq -e '.manual_followups' "$state_file" >/dev/null 2>&1; then
        jq -c '.manual_followups' "$state_file"
        return 0
    fi

    services_csv="$(summary_services_csv "$explicit_profiles_csv")"
    access_mode="$(summary_access_mode)"
    base_domain="$(summary_env_value "BASE_DOMAIN" "")"
    lab_domain="$(summary_env_value "LAB_DOMAIN" "lab")"
    host_ip="$(summary_env_value "HOST_IP" "")"
    catalog_manual_followups_json "$services_csv" "$access_mode" "$base_domain" "$lab_domain" "$host_ip"
}

summary_state_service_url() {
    local service="$1"
    local state_file
    state_file="$(summary_state_file)"
    if summary_state_matches_env; then
        jq -r --arg service "$service" '.health.services[]? | select(.service == $service) | .url // empty' "$state_file" | head -n 1
    fi
}

summary_runtime_ip_url() {
    local service="$1"
    local host_ip="$2"
    local port

    port="$(docker compose port "$service" 2>/dev/null | head -n 1 | awk -F: '{print $NF}')"
    if [[ -n "$port" ]]; then
        printf 'http://%s:%s\n' "$host_ip" "$port"
    fi
}

summary_service_url() {
    local service="$1"
    local access_mode="$2"
    local base_domain="$3"
    local lab_domain="$4"
    local host_ip="$5"
    local url=""

    url="$(summary_state_service_url "$service")"
    if [[ -n "$url" ]]; then
        printf '%s\n' "$url"
        return 0
    fi

    url="$(catalog_service_url "$service" "$access_mode" "$base_domain" "$lab_domain" "$host_ip")"
    if [[ -n "$url" ]]; then
        printf '%s\n' "$url"
        return 0
    fi

    if [[ "$access_mode" == "ip" && -n "$host_ip" ]]; then
        summary_runtime_ip_url "$service" "$host_ip"
    fi
}

summary_service_description() {
    catalog_service_field "$1" "description" ""
}

summary_profile_services_csv() {
    local services_csv="$1"
    local profile="$2"
    local service

    IFS=',' read -r -a services <<< "$services_csv"
    for service in "${services[@]}"; do
        [[ -z "$service" ]] && continue
        if [[ "$(catalog_service_field "$service" "profile" "")" == "$profile" ]]; then
            printf '%s\n' "$service"
        fi
    done | summary_csv_from_lines
}

summary_markdown_service_sections() {
    local summary_file="$1"
    local services_csv="$2"
    local access_mode="$3"
    local base_domain="$4"
    local lab_domain="$5"
    local host_ip="$6"
    local profiles_csv="$7"
    local profile services_for_profile_csv service heading url description profile_lines
    local -a profiles=()
    local rendered_any=false

    IFS=',' read -r -a profiles <<< "$profiles_csv"
    for profile in "${profiles[@]}"; do
        [[ -z "$profile" ]] && continue
        services_for_profile_csv="$(summary_profile_services_csv "$services_csv" "$profile")"
        [[ -z "$services_for_profile_csv" ]] && continue

        heading="$(catalog_profile_field "$profile" "display_name" "$profile") Services"
        profile_lines=""

        IFS=',' read -r -a profile_services <<< "$services_for_profile_csv"
        for service in "${profile_services[@]}"; do
            [[ -z "$service" ]] && continue
            url="$(summary_service_url "$service" "$access_mode" "$base_domain" "$lab_domain" "$host_ip")"
            description="$(summary_service_description "$service")"
            if [[ -n "$url" ]]; then
                profile_lines+="- [$(catalog_service_field "$service" "display_name" "$service")](${url})${description:+ - $description}"$'\n'
                rendered_any=true
            fi
        done
        if [[ -n "$profile_lines" ]]; then
            echo "### ${heading}" >> "$summary_file"
            echo "" >> "$summary_file"
            printf '%s' "$profile_lines" >> "$summary_file"
            echo "" >> "$summary_file"
        fi
    done

    if ! $rendered_any; then
        echo "No service URLs are available yet. Start the stack and re-run the summary if needed." >> "$summary_file"
        echo "" >> "$summary_file"
    fi
}

summary_followups_markdown() {
    local summary_file="$1"
    local followups_json="$2"
    local filebrowser_password="$3"
    local count

    count="$(printf '%s' "$followups_json" | jq 'length')"
    if [[ "$count" -eq 0 ]]; then
        cat >> "$summary_file" <<'EOF'
No manual first-run tasks are currently pending.

EOF
        return 0
    fi

    printf '%s\n' "$followups_json" | jq -c '.[]' | while IFS= read -r item; do
        local service display_name mode url note
        service="$(printf '%s' "$item" | jq -r '.service')"
        display_name="$(printf '%s' "$item" | jq -r '.display_name')"
        mode="$(printf '%s' "$item" | jq -r '.mode')"
        url="$(printf '%s' "$item" | jq -r '.url // ""')"
        note="$(printf '%s' "$item" | jq -r '.note // ""')"

        echo "#### ${display_name}" >> "$summary_file"
        case "$mode" in
            random-password-log)
                if [[ -n "$filebrowser_password" ]]; then
                    echo "- Username: \`admin\`" >> "$summary_file"
                    echo "- Password: \`${filebrowser_password}\`" >> "$summary_file"
                else
                    echo "- Check the generated password in container logs:" >> "$summary_file"
                    echo '  - `docker logs filebrowser | grep "randomly generated password"`' >> "$summary_file"
                fi
                ;;
            installer-url)
                [[ -n "$url" ]] && echo "- Open: \`${url}\`" >> "$summary_file"
                echo "- Complete the first-run installer to create the initial account." >> "$summary_file"
                ;;
            *)
                [[ -n "$url" ]] && echo "- Open: \`${url}\`" >> "$summary_file"
                echo "- Create the first account inside the app." >> "$summary_file"
                ;;
        esac
        [[ -n "$note" ]] && echo "- Note: ${note}" >> "$summary_file"
        echo "" >> "$summary_file"
    done
}

summary_running_services() {
    docker compose ps --format "{{.Service}}" 2>/dev/null \
        | grep -v -E 'database|db|postgres|redis|init|socat|guacd|error-pages|cloudflare-tunnel|registry-cache|coder-registry' \
        | awk 'NF && !seen[$0]++'
}

summary_filebrowser_password() {
    docker logs --tail 100 filebrowser 2>&1 \
        | sed -n "s/.*randomly generated password: //p" \
        | tail -n 1
}

generate_setup_summary() {
    local stack_dir summary_file access_mode host_ip base_domain lab_domain profiles_csv services_csv followups_json configure_actions_json
    local quick_access_heading quick_access_intro local_dns_mode traefik_auth_user traefik_auth_password filebrowser_password
    local needs_dev_config configure_count
    local raw_profiles=("$@")

    stack_dir="$(summary_stack_dir)"
    summary_file="$stack_dir/SETUP_SUMMARY.md"
    access_mode="$(summary_access_mode)"
    host_ip="$(summary_env_value "HOST_IP" "127.0.0.1")"
    base_domain="$(summary_env_value "BASE_DOMAIN" "localhost")"
    lab_domain="$(summary_env_value "LAB_DOMAIN" "lab")"
    local_dns_mode="$(summary_env_value "LOCAL_DNS_MODE" "none")"
    traefik_auth_user="$(summary_env_value "DEFAULT_TRAEFIK_AUTH_USER" "admin")"
    traefik_auth_password="$(summary_env_value "DEFAULT_TRAEFIK_AUTH_PASS" "")"
    profiles_csv="$(summary_profiles_csv "$(printf '%s\n' "${raw_profiles[@]}" | summary_csv_from_lines)")"
    services_csv="$(summary_services_csv "$profiles_csv")"
    followups_json="$(summary_manual_followups_json "$profiles_csv")"
    configure_actions_json="$(summary_configure_actions_json)"
    configure_count="$(printf '%s' "$configure_actions_json" | jq 'length')"
    filebrowser_password="$(summary_filebrowser_password)"
    quick_access_heading="$(summary_access_heading "$access_mode")"
    quick_access_intro="$(summary_access_intro "$access_mode" "$host_ip" "$base_domain" "$lab_domain")"

    log_header "Generating Setup Summary"

    cat > "$summary_file" <<EOF
# WeekendStack Setup Summary

**Setup completed successfully.**

This document captures the generated access details, configure steps, and first-run tasks for this install.

---

## Quick Access

### ${quick_access_heading}

${quick_access_intro}

EOF

    summary_markdown_service_sections "$summary_file" "$services_csv" "$access_mode" "$base_domain" "$lab_domain" "$host_ip" "$profiles_csv"

    cat >> "$summary_file" <<'EOF'
---

## Access Authentication

WeekendStack no longer seeds default app accounts automatically.
Most apps still need their first account created inside the service itself.

EOF

    if [[ "$access_mode" == "tunnel" ]]; then
        if [[ -n "$traefik_auth_password" ]]; then
            cat >> "$summary_file" <<EOF
### External Tunnel Auth

- **Username:** \`${traefik_auth_user}\`
- **Password:** \`${traefik_auth_password}\`

This only applies to the Traefik auth popup on selected tunnel-exposed routes.

EOF
        else
            cat >> "$summary_file" <<'EOF'
### External Tunnel Auth

Tunnel auth is not configured yet.
Run `./configure.sh --tunnel-auth` before exposing tunnel routes.

EOF
        fi
    else
        cat >> "$summary_file" <<'EOF'
### Local Access

No extra Traefik auth popup is configured for local-only access.

EOF
    fi

    cat >> "$summary_file" <<'EOF'
---

## Configure Next

EOF

    if [[ "$configure_count" -gt 0 ]]; then
        printf '%s\n' "$configure_actions_json" | jq -r '.[] | "- `" + .command + "` — " + .reason' >> "$summary_file"
        echo "" >> "$summary_file"
        echo 'Use `./configure.sh --all` to run the guided configure flow in one pass.' >> "$summary_file"
        echo "" >> "$summary_file"
    else
        cat >> "$summary_file" <<'EOF'
No configure steps are pending for this install.

EOF
    fi

    if [[ "$access_mode" == "local" ]]; then
        cat >> "$summary_file" <<EOF
### Local HTTPS And DNS

- Trust the local CA certificate if your browser warns about HTTPS: \`config/traefik/certs/ca-cert.pem\`
- DNS mode: \`${local_dns_mode}\`
- Point local clients at \`${host_ip}\` for \`*.${lab_domain}\` resolution when using Pi-hole or your own wildcard DNS.

EOF
    elif [[ "$access_mode" == "tunnel" ]]; then
        cat >> "$summary_file" <<EOF
### Tunnel Routing

- Cloudflare tunnel URLs use the \`.${base_domain}\` domain.
- Tunnel-exposed services keep Traefik authentication middleware where configured.

EOF
    else
        cat >> "$summary_file" <<EOF
### Direct IP Access

- No local DNS or local CA certificate setup is required.
- Access services directly on \`${host_ip}\` using the ports listed above.

EOF
    fi

    cat >> "$summary_file" <<'EOF'
---

## First-Time Service Setup

EOF

    summary_followups_markdown "$summary_file" "$followups_json" "$filebrowser_password"

    cat >> "$summary_file" <<'EOF'
---

## Maintenance Commands

### Plan
```bash
./setup.sh --plan
```

### Apply
```bash
./setup.sh --apply
```

### Configure
```bash
./configure.sh --all
```

### Doctor
```bash
./setup.sh --doctor --json
```

### Repair
```bash
./setup.sh --repair
```

---

## Files

- Canonical config: `weekendstack.config.json`
- Generated env: `.env`
- Machine state: `setup-state.json`
- Custom compose profile: `docker-compose.custom.yml`
- Stack summary: `SETUP_SUMMARY.md`

EOF

    log_success "Setup summary saved to: $summary_file"
    echo ""
}

add_service_urls() {
    local summary_file="$1"
    local lab_domain="$2"
    local base_domain="$3"
    shift 3
    local profiles_csv
    profiles_csv="$(printf '%s\n' "$@" | summary_csv_from_lines)"
    summary_markdown_service_sections "$summary_file" "$(summary_services_csv "$profiles_csv")" "$(summary_access_mode)" "$base_domain" "$lab_domain" "$(summary_env_value "HOST_IP" "127.0.0.1")" "$profiles_csv"
}

add_external_service_urls() {
    local summary_file="$1"
    local base_domain="$2"
    shift 2
    local services_csv access_mode host_ip lab_domain

    access_mode="$(summary_access_mode)"
    host_ip="$(summary_env_value "HOST_IP" "127.0.0.1")"
    lab_domain="$(summary_env_value "LAB_DOMAIN" "lab")"
    services_csv="$(summary_services_csv "$(printf '%s\n' "$@" | summary_csv_from_lines)")"
    summary_markdown_service_sections "$summary_file" "$services_csv" "$access_mode" "$base_domain" "$lab_domain" "$host_ip" "$(printf '%s\n' "$@" | summary_csv_from_lines)"
}

display_summary_to_console() {
    local access_mode host_ip base_domain lab_domain services_csv configure_actions_json followups_json
    local traefik_auth_user traefik_auth_password running_services filebrowser_password
    local service url configure_count

    access_mode="$(summary_access_mode)"
    host_ip="$(summary_env_value "HOST_IP" "127.0.0.1")"
    base_domain="$(summary_env_value "BASE_DOMAIN" "localhost")"
    lab_domain="$(summary_env_value "LAB_DOMAIN" "lab")"
    traefik_auth_user="$(summary_env_value "DEFAULT_TRAEFIK_AUTH_USER" "admin")"
    traefik_auth_password="$(summary_env_value "DEFAULT_TRAEFIK_AUTH_PASS" "")"
    services_csv="$(summary_services_csv)"
    configure_actions_json="$(summary_configure_actions_json)"
    followups_json="$(summary_manual_followups_json)"
    configure_count="$(printf '%s' "$configure_actions_json" | jq 'length')"
    running_services="$(summary_running_services)"
    filebrowser_password="$(summary_filebrowser_password)"

    clear_screen
    echo ""
    log_header "Setup Complete!"
    echo ""

    echo -e "${BOLD}Quick Start:${NC}"
    case "$access_mode" in
        tunnel) echo "  Open your dashboard: https://home.${base_domain}" ;;
        local) echo "  Open your dashboard: https://home.${lab_domain}" ;;
        *) echo "  Open your dashboard: http://${host_ip}:8080" ;;
    esac
    echo ""

    echo -e "${BOLD}Services Running:${NC}"
    echo ""
    if [[ -n "$running_services" ]]; then
        local printed_services=false
        printf "  %-25s %s\n" "SERVICE" "ACCESS URL"
        printf "  %-25s %s\n" "$(printf '%.0s─' {1..25})" "$(printf '%.0s─' {1..50})"
        while IFS= read -r service; do
            [[ -z "$service" ]] && continue
            url="$(summary_service_url "$service" "$access_mode" "$base_domain" "$lab_domain" "$host_ip")"
            [[ -z "$url" ]] && continue
            printf "  %-25s %s\n" "$service" "$url"
            printed_services=true
        done <<< "$running_services"
        if [[ "$printed_services" != true ]]; then
            echo "  No public service URLs are available yet."
        fi
    else
        echo "  No services running yet. Start them with: docker compose up -d"
    fi
    echo ""

    echo -e "${BOLD}Access Methods:${NC}"
    case "$access_mode" in
        tunnel)
            echo "  Using Cloudflare Tunnel on .${base_domain}"
            if [[ -n "$traefik_auth_password" ]]; then
                echo ""
                echo "  External auth credentials:"
                echo "    • Username:    ${traefik_auth_user}"
                echo "    • Password:    ${traefik_auth_password}"
            else
                echo ""
                echo "  External auth is still pending:"
                echo "    • Run:         ./configure.sh --tunnel-auth"
            fi
            ;;
        local)
            echo "  Using local domain .${lab_domain}"
            echo "  Traefik basic auth is disabled for local-only routes"
            echo "  Point local clients at ${host_ip} for DNS resolution"
            ;;
        *)
            echo "  Using direct local IP access on ${host_ip}"
            echo "  Traefik basic auth is disabled for local-only routes"
            ;;
    esac
    echo ""

    echo -e "${BOLD}Configure Next:${NC}"
    if [[ "$configure_count" -gt 0 ]]; then
        printf '%s\n' "$configure_actions_json" | jq -r '.[] | "  • " + .command'
    else
        echo "  • No configure steps are pending for this install"
    fi
    echo ""

    echo -e "${BOLD}First-Time Service Setup:${NC}"
    if [[ "$(printf '%s' "$followups_json" | jq 'length')" -eq 0 ]]; then
        echo "  • No manual first-run tasks are pending"
    else
        printf '%s\n' "$followups_json" | jq -c '.[]' | while IFS= read -r item; do
            local display_name mode url note
            display_name="$(printf '%s' "$item" | jq -r '.display_name')"
            mode="$(printf '%s' "$item" | jq -r '.mode')"
            url="$(printf '%s' "$item" | jq -r '.url // ""')"
            note="$(printf '%s' "$item" | jq -r '.note // ""')"
            echo "  • ${display_name}:"
            case "$mode" in
                random-password-log)
                    echo "    Username: admin"
                    if [[ -n "$filebrowser_password" ]]; then
                        echo "    Password: ${filebrowser_password}"
                    else
                        echo '    Check: docker logs filebrowser | grep "randomly generated password"'
                    fi
                    ;;
                installer-url)
                    [[ -n "$url" ]] && echo "    Open: ${url}"
                    echo "    Complete the installer to create the first account"
                    ;;
                *)
                    [[ -n "$url" ]] && echo "    Open: ${url}"
                    echo "    Create the first account inside the app"
                    ;;
            esac
            [[ -n "$note" ]] && echo "    Note: ${note}"
        done
    fi
    echo ""

    echo -e "${BOLD}Important:${NC}"
    echo "  • Review SETUP_SUMMARY.md for the full configure and first-run checklist"
    echo "  • Agents should use weekendstack.config.json + setup-state.json instead of scraping terminal output"
    echo ""

    if [[ "$configure_count" -gt 0 ]]; then
        log_success "Base stack is ready. Run ./configure.sh --all to finish integrations."
    else
        log_success "Your WeekendStack is ready to use!"
    fi
    echo ""
}

export -f generate_setup_summary add_service_urls add_external_service_urls
export -f display_summary_to_console
