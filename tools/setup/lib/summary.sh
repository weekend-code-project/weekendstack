#!/bin/bash
# Post-setup summary generator
# Creates service URL list and credentials summary

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
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

generate_setup_summary() {
    local stack_dir
    stack_dir=$(summary_stack_dir)
    local profiles=("$@")
    local summary_file="$stack_dir/SETUP_SUMMARY.md"
    
    log_header "Generating Setup Summary"
    
    # Get configuration from .env
    local lab_domain=$(grep "^LAB_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ' || echo "lab")
    local base_domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ' || echo "localhost")
    local host_ip=$(grep "^HOST_IP=" "$stack_dir/.env" | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ' || echo "192.168.1.100")
    local traefik_auth_user=$(grep "^DEFAULT_TRAEFIK_AUTH_USER=" "$stack_dir/.env" | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ' || echo "admin")
    local traefik_auth_password=$(grep "^DEFAULT_TRAEFIK_AUTH_PASS=" "$stack_dir/.env" | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ' || echo "<check .env file>")
    local access_mode
    access_mode=$(auth_policy_access_mode_from_env "$stack_dir/.env")
    local resourcespace_port=$(grep "^RESOURCESPACE_PORT=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ' || echo "8099")
    local resourcespace_setup_url=""
    case "$access_mode" in
        tunnel) resourcespace_setup_url="https://resourcespace.${base_domain}/pages/setup.php" ;;
        local) resourcespace_setup_url="https://resourcespace.${lab_domain}/pages/setup.php" ;;
        *) resourcespace_setup_url="http://${host_ip}:${resourcespace_port}/pages/setup.php" ;;
    esac
    local profiles_raw
    local -a summary_profiles=("${profiles[@]}")
    profiles_raw=$(grep "^COMPOSE_PROFILES=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2- | tr -d '"')
    if [[ -n "$profiles_raw" ]]; then
        IFS=',' read -r -a summary_profiles <<< "$profiles_raw"
    fi
    
    local quick_access_heading="Local Network Access (.lab domain)"
    local quick_access_intro="Your WeekendStack is accessible on your local network using the \`.$lab_domain\` domain:"
    case "$access_mode" in
        tunnel)
            quick_access_heading="External Access (Cloudflare Tunnel)"
            quick_access_intro="Your WeekendStack is accessible externally through Cloudflare Tunnel using \`.$base_domain\` URLs:"
            ;;
        ip)
            quick_access_heading="Local IP Access"
            quick_access_intro="Your WeekendStack is accessible directly by IP on \`$host_ip\`:"
            ;;
    esac

    # Generate summary file
    cat > "$summary_file" << 'EOF'
# WeekendStack Setup Summary

**Setup completed successfully!** 🎉

This document contains important information about your WeekendStack deployment.

---

## Quick Access

### QUICK_ACCESS_HEADING
EOF
    sed -i "s|QUICK_ACCESS_HEADING|$quick_access_heading|" "$summary_file"

    echo "" >> "$summary_file"
    echo "$quick_access_intro" >> "$summary_file"
    echo "" >> "$summary_file"
    
    # Add service URLs based on profiles
    add_service_urls "$summary_file" "$lab_domain" "$base_domain" "${summary_profiles[@]}"
    
    # Add credentials section
    cat >> "$summary_file" << EOF

---

## Access Authentication

⚠️ **IMPORTANT SECURITY NOTICE:**
1. WeekendStack no longer seeds default app accounts automatically
2. Most services will need their first account created inside the app
3. Only tunnel-exposed routes use the Traefik basic-auth popup below

---

## Next Steps

EOF

    case "$access_mode" in
        local)
            cat >> "$summary_file" << EOF
### 1. Trust Local HTTPS Certificate

To avoid browser security warnings:

**Linux (Ubuntu/Debian):**
\`\`\`bash
sudo cp config/traefik/certs/ca-cert.pem /usr/local/share/ca-certificates/weekendstack-ca.crt
sudo update-ca-certificates
\`\`\`

**macOS:**
\`\`\`bash
sudo security add-trusted-cert -d -r trustRoot \\
  -k /Library/Keychains/System.keychain config/traefik/certs/ca-cert.pem
\`\`\`

**Windows (WSL):**
Import \`config/traefik/certs/ca-cert.pem\` via Windows certificate manager.

**Browsers:** Restart your browser after installing the certificate.

### 2. Configure DNS

**Option A: Use Pi-hole as DNS**
Set your device DNS to: \`$host_ip\`

**Option B: Edit /etc/hosts (Linux/macOS) or C:\\Windows\\System32\\drivers\\etc\\hosts (Windows)**
Add entries for each service manually.

### 3. Configure Services

EOF
            ;;
        tunnel)
            cat >> "$summary_file" << EOF
### 1. External Access Authentication

Use the Traefik basic-auth popup credentials below for selected tunnel-exposed tools.
No local DNS or local CA certificate setup is required for remote tunnel access.

### 2. Configure Services

EOF
            ;;
        *)
            cat >> "$summary_file" << EOF
### 1. Configure Services

No local DNS or local CA certificate setup is required for direct IP access.

EOF
            ;;
    esac

    cat >> "$summary_file" << EOF

#### Glance Dashboard
Edit \`config/glance/glance.yml\` to customize your dashboard:
- Add API keys for weather, calendar, RSS feeds
- Configure widgets and layout
- Restart Glance: \`docker restart glance\`

#### Paperless-ngx
Place documents in: \`files/paperless/consume/\`
They will be automatically processed and indexed.

#### Coder
Access at $(case "$access_mode" in tunnel) printf 'https://coder.%s' "$base_domain" ;; local) printf 'https://coder.%s' "$lab_domain" ;; *) printf 'http://%s:7080' "$host_ip" ;; esac)
Create development environments using the templates in \`config/coder/v2/templates/\`

EOF

    local summary_profiles_list=" ${summary_profiles[*]} "
    if [[ "$summary_profiles_list" == *" all "* || "$summary_profiles_list" == *" productivity "* ]]; then
        cat >> "$summary_file" << EOF
#### File Browser
File Browser creates its own initial admin account on first boot.
If you missed the generated password in the console summary, check:
\`\`\`bash
docker logs filebrowser | grep "randomly generated password"
\`\`\`

#### ResourceSpace
Complete the first-run installer here to create the first admin account:
\`${resourcespace_setup_url}\`

EOF
    fi

    if [[ "$access_mode" == "tunnel" ]]; then
        cat >> "$summary_file" << EOF
### External Tunnel Auth

- **Username:** \`$traefik_auth_user\`
- **Password:** \`$traefik_auth_password\`

This is only for the Traefik auth popup on selected external routes.
It is not a default account for the apps themselves.

EOF
    else
        cat >> "$summary_file" << EOF
### Local Access

No extra Traefik auth is configured for local-only access.
Create app accounts manually inside each service as needed.

EOF
    fi

    # Add Cloudflare section if enabled
    if grep -q "CLOUDFLARE_TUNNEL_ENABLED=true" "$stack_dir/.env" 2>/dev/null; then
        cat >> "$summary_file" << EOF

### 4. External Access (Cloudflare Tunnel)

Your services are accessible externally via Cloudflare Tunnel:

EOF
        add_external_service_urls "$summary_file" "$base_domain" "${summary_profiles[@]}"
        echo "" >> "$summary_file"
        if [[ "$access_mode" == "tunnel" ]]; then
            echo "**Security Note:** Tunnel-exposed services keep Traefik authentication middleware where configured." >> "$summary_file"
        fi
    fi
    
    # Add maintenance section
    cat >> "$summary_file" << EOF

---

## Maintenance Commands

### Start Services
\`\`\`bash
docker compose up -d
\`\`\`

### Stop Services
\`\`\`bash
docker compose down
\`\`\`

### View Logs
\`\`\`bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f <service-name>

\`\`\`

### Update Services
\`\`\`bash
docker compose pull
docker compose up -d
\`\`\`

### Restart a Service
\`\`\`bash
docker compose restart <service-name>
\`\`\`

### Check Service Health
\`\`\`bash
./tools/test_stack_health.sh
\`\`\`

### Validate Configuration
\`\`\`bash
./tools/validate-env.sh
\`\`\`

---

## File Locations

### User Data (BACKUP THESE!)
- **Documents:** \`files/paperless/\`
- **Photos:** \`files/immich/\` (or NFS mount)
- **Music:** \`files/navidrome/music/\`
- **Books:** \`files/kavita/library/\`
- **AI Models:** \`files/ai-models/ollama/\`
- **Workspaces:** \`files/coder/workspace/\` or \`$WORKSPACE_DIR\`

### Application Data
- **Databases:** Docker volumes (use \`docker volume ls\`)
- **Configurations:** \`config/\`
- **Application state:** \`data/\`

### Important Configuration Files
- **Environment:** \`.env\`
- **Traefik:** \`config/traefik/config.yml\`
- **Cloudflare:** \`config/cloudflare/config.yml\`
- **Glance:** \`config/glance/glance.yml\`

---

## Troubleshooting

### Service won't start
1. Check logs: \`docker compose logs <service>\`
2. Verify .env configuration: \`./tools/validate-env.sh\`
3. Check for port conflicts: \`docker compose ps\`

### Cannot access services on .lab domain
1. Verify Pi-hole is running: \`docker ps | grep pihole\`
2. Check DNS settings on your device (should be $host_ip)
3. Verify dnsmasq config: \`cat config/pihole/etc-dnsmasq.d/02-custom-lab.conf\`

### Browser shows security warning (HTTPS)
1. Install CA certificate (see "Trust Local HTTPS Certificate" above)
2. Restart browser after installing
3. If still showing, check certificate dates: \`openssl x509 -in config/traefik/certs/cert.pem -text\`

### Database connection errors
1. Wait for database to be healthy: \`docker ps\` (check "healthy" status)
2. Check database logs: \`docker compose logs <service>-db\`
3. Verify credentials in .env match service configuration

### Out of disk space
1. Clean up Docker: \`docker system prune -a\`
2. Check disk usage: \`du -sh files/ data/\`
3. Configure log rotation: \`docker compose --log-opt max-size=10m\`

---

## Documentation

For detailed setup and configuration guides, see:

- **Architecture:** \`docs/architecture.md\`
- **Network Setup:** \`docs/network-architecture.md\`
- **Service Guides:** \`docs/<service>-setup.md\`
- **Credentials:** \`docs/credentials-guide.md\`
- **File Paths:** \`docs/file-paths-reference.md\`

---

## Support & Community

- **Documentation:** \`docs/\` directory
- **Issues:** Check service-specific logs and documentation
- **Updates:** Run \`docker compose pull\` regularly

---

**Generated:** $(date +"%Y-%m-%d %H:%M:%S")
**Profiles:** ${profiles[*]}
**Setup Script:** WeekendStack v1.0
EOF
    
    log_success "Setup summary saved to: $summary_file"
    echo ""
}

add_service_urls() {
    local summary_file="$1"
    local lab_domain="$2"
    local base_domain="$3"
    shift 3
    local profiles=("$@")
    local profiles_list=" ${profiles[*]} "
    local has_ai_services=false
    
    # Core services
    echo "**Core Services:**" >> "$summary_file"
    echo "- [Glance Dashboard](https://$lab_domain) - Homepage with widgets" >> "$summary_file"
    echo "- [Vaultwarden](https://vault.$lab_domain) - Password manager" >> "$summary_file"
    echo "- [Link Router](https://go.$lab_domain) - Go links service" >> "$summary_file"
    echo "" >> "$summary_file"

    if [[ "$profiles_list" == *" all "* || "$profiles_list" == *" ai "* || "$profiles_list" == *" open-webui "* || "$profiles_list" == *" librechat "* || "$profiles_list" == *" anythingllm "* || "$profiles_list" == *" localai "* || "$profiles_list" == *" whisper "* || "$profiles_list" == *" whisperx "* || "$profiles_list" == *" privategpt "* || "$profiles_list" == *" searxng "* || "$profiles_list" == *" paperclip "* ]]; then
        has_ai_services=true
    fi
    
    # Check each profile
    for profile in "${profiles[@]}"; do
        case "$profile" in
            all|networking)
                echo "**Network Services:**" >> "$summary_file"
                echo "- [Traefik Dashboard](https://traefik.$lab_domain:8081) - Reverse proxy" >> "$summary_file"
                echo "- [Link Router](https://go.$lab_domain) - Go links service" >> "$summary_file"
                echo "" >> "$summary_file"
                ;;
        esac
        
        case "$profile" in
            all|pihole)
                echo "**DNS & Ad Blocking:**" >> "$summary_file"
                echo "- [Pi-hole Admin](http://pihole.$lab_domain/admin) - DNS and ad blocking" >> "$summary_file"
                echo "" >> "$summary_file"
                ;;
        esac
        
        case "$profile" in
            all|dev)
                echo "**Development Tools:**" >> "$summary_file"
                echo "- [Coder](https://coder.$lab_domain) - Cloud development environments" >> "$summary_file"
                echo "- [Gitea](https://gitea.$lab_domain) - Git service" >> "$summary_file"
                echo "- [GitLab](https://gitlab.$lab_domain) - Complete DevOps platform" >> "$summary_file"
                echo "" >> "$summary_file"
                ;;
        esac
        
        case "$profile" in
            all|productivity)
                echo "**Productivity Apps:**" >> "$summary_file"
                echo "- [Paperless-ngx](https://paperless.$lab_domain) - Document management" >> "$summary_file"
                echo "- [NocoDB](https://nocodb.$lab_domain) - No-code database" >> "$summary_file"
                echo "- [N8N](https://n8n.$lab_domain) - Workflow automation" >> "$summary_file"
                echo "- [FileBrowser](https://files.$lab_domain) - File management" >> "$summary_file"
                echo "" >> "$summary_file"
                ;;
        esac
        
        case "$profile" in
            all|monitoring)
                echo "**Monitoring Tools:**" >> "$summary_file"
                echo "- [Uptime Kuma](https://uptime.$lab_domain) - Uptime monitoring" >> "$summary_file"
                echo "" >> "$summary_file"
                ;;
        esac
    done

    if $has_ai_services; then
        echo "**AI Services:**" >> "$summary_file"
        echo "- [Ollama](https://ollama.$lab_domain) - Local LLM runtime" >> "$summary_file"
        if [[ "$profiles_list" == *" all "* || "$profiles_list" == *" open-webui "* ]]; then
            echo "- [Open WebUI](https://open-webui.$lab_domain) - Chat with AI models" >> "$summary_file"
        fi
        if [[ "$profiles_list" == *" all "* || "$profiles_list" == *" librechat "* ]]; then
            echo "- [LibreChat](https://librechat.$lab_domain) - Multi-model AI chat" >> "$summary_file"
        fi
        if [[ "$profiles_list" == *" all "* || "$profiles_list" == *" anythingllm "* ]]; then
            echo "- [AnythingLLM](https://anythingllm.$lab_domain) - Document Q&A workspace" >> "$summary_file"
        fi
        if [[ "$profiles_list" == *" all "* || "$profiles_list" == *" searxng "* ]]; then
            echo "- [SearXNG](https://searxng.$lab_domain) - Privacy-focused search" >> "$summary_file"
        fi
        if [[ "$profiles_list" == *" all "* || "$profiles_list" == *" localai "* ]]; then
            echo "- [LocalAI](https://localai.$lab_domain) - OpenAI-compatible local API" >> "$summary_file"
        fi
        if [[ "$profiles_list" == *" all "* || "$profiles_list" == *" paperclip "* ]]; then
            echo "- [Paperclip](https://paperclip.$lab_domain) - AI company control plane" >> "$summary_file"
        fi
        echo "" >> "$summary_file"
    fi
}

add_external_service_urls() {
    local summary_file="$1"
    local base_domain="$2"
    shift 2
    local profiles=("$@")
    
    if [[ "$base_domain" == "localhost" ]]; then
        return 0
    fi
    
    echo "External URLs (via Cloudflare Tunnel):" >> "$summary_file"
    echo "- Dashboard: https://$base_domain" >> "$summary_file"
    echo "- Coder: https://coder.$base_domain" >> "$summary_file"
    echo "- Other services: https://service-name.$base_domain" >> "$summary_file"
}

get_filebrowser_initial_password() {
    docker logs --tail 100 filebrowser 2>&1 \
        | sed -n "s/.*randomly generated password: //p" \
        | tail -n 1
}

display_summary_to_console() {
    local stack_dir
    stack_dir=$(summary_stack_dir)
    local lab_domain=$(grep "^LAB_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ' || echo "lab")
    local base_domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ' || echo "localhost")
    local host_ip=$(grep "^HOST_IP=" "$stack_dir/.env" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    local domain_mode=$(grep "^DOMAIN_MODE=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "ip")
    local traefik_auth_user=$(grep "^DEFAULT_TRAEFIK_AUTH_USER=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ' || echo "admin")
    local traefik_auth_password=$(grep "^DEFAULT_TRAEFIK_AUTH_PASS=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ' || echo "<check .env file>")
    local access_mode
    access_mode=$(normalize_access_mode "$domain_mode")
    local resourcespace_port=$(grep "^RESOURCESPACE_PORT=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ' || echo "8099")
    local filebrowser_password=""
    local resourcespace_setup_url=""
    local paperclip_setup_url=""
    
    # Define service subdomain mappings  
    declare -A service_subdomains=(
        # Core
        ["glance"]="home"
        ["speedtest-tracker"]="speedtest"
        # Networking
        ["traefik"]="traefik"
        ["pihole"]="pihole"
        # Dev
        ["coder"]="coder"
        ["gitea"]="gitea"
        ["registry"]="registry"
        ["it-tools"]="it-tools"
        # AI
        ["ollama"]="ollama"
        ["open-webui"]="openwebui"
        ["searxng"]="searxng"
        ["localai"]="localai"
        ["anythingllm"]="anythingllm"
        ["whisper"]="whisper"
        ["whisperx"]="whisperx"
        ["librechat"]="librechat"
        ["privategpt"]="privategpt"
        ["paperclip"]="paperclip"
        # Productivity
        ["nocodb"]="nocodb"
        ["n8n"]="n8n"
        ["paperless-ngx"]="paperless"
        ["activepieces"]="activepieces"
        ["postiz"]="postiz"
        ["focalboard"]="focalboard"
        ["trilium"]="trilium"
        ["vikunja"]="vikunja"
        ["excalidraw"]="excalidraw"
        ["docmost"]="docmost"
        ["filebrowser"]="filebrowser"
        ["hoarder"]="hoarder"
        ["bytestash"]="bytestash"
        ["resourcespace"]="resourcespace"
        # Media
        ["immich"]="immich"
        ["kavita"]="kavita"
        ["navidrome"]="navidrome"
        # Monitoring
        ["wud"]="wud"
        ["uptime-kuma"]="uptime-kuma"
    )
    
    # Get running services (exclude databases and support services)
    local running_services=$(docker compose ps --format "{{.Service}}" 2>/dev/null | grep -v -E 'database|db|postgres|redis|init|socat|guacd|error-pages|cloudflare-tunnel' | sort -u || true)
    
    clear
    echo ""
    log_header "Setup Complete!"
    
    echo ""
    echo -e "${BOLD}Quick Start:${NC}"
    case "$access_mode" in
        tunnel)
            echo "  Open your dashboard: https://home.${base_domain}"
            ;;
        local)
            echo "  Open your dashboard: https://home.${lab_domain}"
            ;;
        *)
            echo "  Open your dashboard: http://${host_ip}:8080"
            ;;
    esac
    echo ""
    
    echo -e "${BOLD}Services Running:${NC}"
    echo ""
    
    if [[ -n "$running_services" ]]; then
        printf "  %-25s %s\n" "SERVICE" "ACCESS URL"
        printf "  %-25s %s\n" "$(printf '%.0s─' {1..25})" "$(printf '%.0s─' {1..50})"
        
        while IFS= read -r service; do
            local subdomain="${service_subdomains[$service]:-$service}"
            local url=""
            
            case "$access_mode" in
                tunnel)
                    url="https://${subdomain}.${base_domain}"
                    ;;
                local)
                    url="https://${subdomain}.${lab_domain}"
                    ;;
                *)
                    url="http://${host_ip}:* (check docker ps)"
                    ;;
            esac
            
            printf "  %-25s %s\n" "$service" "$url"
        done <<< "$running_services"
    else
        echo "  No services running yet. Start them with: docker compose up -d"
    fi

    if printf '%s\n' "$running_services" | grep -q '^filebrowser$'; then
        filebrowser_password=$(get_filebrowser_initial_password)
    fi

    if printf '%s\n' "$running_services" | grep -q '^paperclip$'; then
        case "$access_mode" in
            tunnel)
                paperclip_setup_url="https://paperclip.${base_domain}"
                ;;
            local)
                paperclip_setup_url="https://paperclip.${lab_domain}"
                ;;
            *)
                paperclip_setup_url="http://${host_ip}:3100"
                ;;
        esac
    fi

    if printf '%s\n' "$running_services" | grep -q '^resourcespace$'; then
        case "$access_mode" in
            tunnel)
                resourcespace_setup_url="https://resourcespace.${base_domain}/pages/setup.php"
                ;;
            local)
                resourcespace_setup_url="https://resourcespace.${lab_domain}/pages/setup.php"
                ;;
            *)
                resourcespace_setup_url="http://${host_ip}:${resourcespace_port}/pages/setup.php"
                ;;
        esac
    fi
    
    echo ""
    echo -e "${BOLD}Access Methods:${NC}"
    
    case "$access_mode" in
        tunnel)
            echo "  Using Cloudflare Tunnel"
            echo "  Base Domain: ${base_domain}"
            echo "  Traefik basic auth stays enabled on selected tunnel-exposed tools"
            echo ""
            echo "  External auth credentials:"
            echo "    • Username:    ${traefik_auth_user}"
            echo "    • Password:    ${traefik_auth_password}"
            echo ""
            echo "  Example URLs:"
            echo "    • Dashboard:   https://home.${base_domain}"
            echo "    • Coder:       https://coder.${base_domain}"
            echo "    • Traefik:     https://traefik.${base_domain}"
            ;;
        local)
            echo "  Using local domain .${lab_domain}"
            echo "  Traefik basic auth is disabled for local .lab routes"
            echo ""
            echo "  Example URLs:"
            echo "    • Dashboard:   https://home.${lab_domain}"
            echo "    • Coder:       https://coder.${lab_domain}"
            echo "    • Traefik:     https://traefik.${lab_domain}"
            echo ""
            echo "  DNS requirement:"
            echo "    • Point clients at Pi-hole or add local DNS records for *.${lab_domain} -> ${host_ip}"
            ;;
        *)
            echo "  Using direct local IP access"
            echo "  Host IP: ${host_ip}"
            echo "  Traefik basic auth is disabled for local IP access"
            echo ""
            echo "  Common services:"
            echo "    • Dashboard:   http://${host_ip}:8080"
            echo "    • Coder:       http://${host_ip}:7080"
            echo "    • Traefik:     http://${host_ip}:8081"
            echo "    • Pi-hole:     http://${host_ip}:8088/admin"
            ;;
    esac
    
    echo ""
    echo -e "${BOLD}Documentation:${NC}"
    echo "  • Complete summary: SETUP_SUMMARY.md"
    echo "  • Canonical config: weekendstack.config.json"
    echo "  • Machine state:    setup-state.json"
    echo "  • Service guides:   docs/"
    echo ""

    if [[ -n "$filebrowser_password" || -n "$resourcespace_setup_url" || -n "$paperclip_setup_url" ]]; then
        echo -e "${BOLD}First-Time Service Setup:${NC}"
        if [[ -n "$filebrowser_password" ]]; then
            echo "  • File Browser first login:"
            echo "    Username: admin"
            echo "    Password: ${filebrowser_password}"
        fi
        if [[ -n "$resourcespace_setup_url" ]]; then
            echo "  • ResourceSpace first run:"
            echo "    Open ${resourcespace_setup_url}"
            echo "    Complete the web installer to create the first admin account"
        fi
        if [[ -n "$paperclip_setup_url" ]]; then
            echo "  • Paperclip first run:"
            echo "    Open ${paperclip_setup_url}"
            echo "    Create the first Paperclip account and company in the browser"
        fi
        echo ""
    fi
    
    echo -e "${BOLD}Important:${NC}"
    echo "  • Review SETUP_SUMMARY.md for tunnel auth and first-time service setup"
    echo "  • Agents should read weekendstack.config.json + setup-state.json instead of scraping terminal output"
    if [[ -n "$running_services" ]] && printf '%s\n' "$running_services" | grep -q '^gitea$'; then
        local gitea_url
        case "$access_mode" in
            tunnel) gitea_url="https://gitea.${base_domain}" ;;
            local) gitea_url="https://gitea.${lab_domain}" ;;
            *) gitea_url="http://${host_ip}:3300" ;;
        esac
        echo "  • Gitea first run: open ${gitea_url} and complete the web setup if prompted"
    fi
    echo "  • Uptime Kuma: add Docker host → Socket: /var/run/docker.sock"
    echo ""
    
    log_success "Your WeekendStack is ready to use!"
    echo ""
}

# Export functions
export -f generate_setup_summary add_service_urls add_external_service_urls
export -f display_summary_to_console
