#!/bin/bash
# Post-setup summary generator
# Creates service URL list and credentials summary

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

generate_setup_summary() {
    local stack_dir="${SCRIPT_DIR}"
    local profiles=("$@")
    local summary_file="$stack_dir/SETUP_SUMMARY.md"
    
    log_header "Generating Setup Summary"
    
    # Get configuration from .env
    local lab_domain=$(grep "^LAB_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ' || echo "lab")
    local base_domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ' || echo "localhost")
    local host_ip=$(grep "^HOST_IP=" "$stack_dir/.env" | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ' || echo "192.168.1.100")
    local admin_user=$(grep "^DEFAULT_ADMIN_USER=" "$stack_dir/.env" | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ' || echo "admin")
    local admin_email=$(grep "^DEFAULT_ADMIN_EMAIL=" "$stack_dir/.env" | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ' || echo "admin@example.com")
    local admin_password=$(grep "^DEFAULT_ADMIN_PASSWORD=" "$stack_dir/.env" | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' ' || echo "<check .env file>")
    
    # Generate summary file
    cat > "$summary_file" << 'EOF'
# WeekendStack Setup Summary

**Setup completed successfully!** 🎉

This document contains important information about your WeekendStack deployment.

---

## Quick Access

### Local Network Access (.lab domain)
EOF
    
    echo "" >> "$summary_file"
    echo "Your WeekendStack is accessible on your local network using the \`.$lab_domain\` domain:" >> "$summary_file"
    echo "" >> "$summary_file"
    
    # Add service URLs based on profiles
    add_service_urls "$summary_file" "$lab_domain" "$base_domain" "${profiles[@]}"
    
    # Add credentials section
    cat >> "$summary_file" << EOF

---

## Default Credentials

Many services use these default credentials for initial setup:

- **Username:** \`$admin_user\`
- **Email:** \`$admin_email\`
- **Password:** \`$admin_password\`

⚠️ **IMPORTANT SECURITY NOTICE:**
1. Change default passwords immediately after first login
2. Disable user registration on services after creating your account
3. Review and update all credentials in production environments

### First-Time Setup Services

These services require you to create the first user account (which becomes admin):

- **Open WebUI** - Visit https://open-webui.$lab_domain and sign up
- **Immich** - Visit https://immich.$lab_domain and create account
- **Mealie** - Visit https://mealie.$lab_domain and create account
- **Home Assistant** - Visit https://hass.$lab_domain and create account
- **Kavita** - Visit https://kavita.$lab_domain and create account
- **Navidrome** - Visit https://navidrome.$lab_domain and create account

The first user to register becomes the administrator.

---

## Next Steps

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

#### Glance Dashboard
Edit \`config/glance/glance.yml\` to customize your dashboard:
- Add API keys for weather, calendar, RSS feeds
- Configure widgets and layout
- Restart Glance: \`docker restart glance\`

#### Paperless-ngx
Place documents in: \`files/paperless/consume/\`
They will be automatically processed and indexed.

#### Coder
Access at https://coder.$lab_domain
Create development environments using the templates in \`config/coder/v2/templates/\`

EOF

    # Add Cloudflare section if enabled
    if grep -q "CLOUDFLARE_TUNNEL_ENABLED=true" "$stack_dir/.env" 2>/dev/null; then
        cat >> "$summary_file" << EOF

### 4. External Access (Cloudflare Tunnel)

Your services are accessible externally via Cloudflare Tunnel:

EOF
        add_external_service_urls "$summary_file" "$base_domain" "${profiles[@]}"
        echo "" >> "$summary_file"
        echo "**Security Note:** External services are protected by Traefik authentication middleware." >> "$summary_file"
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
    
    # Core services
    echo "**Core Services:**" >> "$summary_file"
    echo "- [Glance Dashboard](https://$lab_domain) - Homepage with widgets" >> "$summary_file"
    echo "- [Vaultwarden](https://vault.$lab_domain) - Password manager" >> "$summary_file"
    echo "- [Link Router](https://go.$lab_domain) - Go links service" >> "$summary_file"
    echo "" >> "$summary_file"
    
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
            all|ai)
                echo "**AI Services:**" >> "$summary_file"
                echo "- [Open WebUI](https://open-webui.$lab_domain) - Chat with AI models" >> "$summary_file"
                echo "- [LibreChat](https://librechat.$lab_domain) - Multi-model AI chat" >> "$summary_file"
                echo "- [SearXNG](https://searxng.$lab_domain) - Privacy-focused search" >> "$summary_file"
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

display_summary_to_console() {
    local stack_dir="${SCRIPT_DIR}"
    local lab_domain=$(grep "^LAB_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ' || echo "lab")
    local base_domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ' || echo "localhost")
    local host_ip=$(grep "^HOST_IP=" "$stack_dir/.env" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    local tunnel_enabled=$(grep "^CLOUDFLARE_TUNNEL_ENABLED=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "false")
    
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
    echo "  Open your dashboard: $(if [[ "$tunnel_enabled" == "true" ]]; then echo "https://home.${base_domain}"; else echo "http://${host_ip}:8080"; fi)"
    echo ""
    
    echo -e "${BOLD}Services Running:${NC}"
    echo ""
    
    if [[ -n "$running_services" ]]; then
        printf "  %-25s %s\n" "SERVICE" "ACCESS URL"
        printf "  %-25s %s\n" "$(printf '%.0s─' {1..25})" "$(printf '%.0s─' {1..50})"
        
        while IFS= read -r service; do
            local subdomain="${service_subdomains[$service]:-$service}"
            local url=""
            
            if [[ "$tunnel_enabled" == "true" ]]; then
                # External tunnel URL
                url="https://${subdomain}.${base_domain}"
            else
                # Local IP access
                url="http://${host_ip}:* (check docker ps)"
            fi
            
            printf "  %-25s %s\n" "$service" "$url"
        done <<< "$running_services"
    else
        echo "  No services running yet. Start them with: docker compose up -d"
    fi
    
    echo ""
    echo -e "${BOLD}Access Methods:${NC}"
    
    if [[ "$tunnel_enabled" == "true" ]]; then
        echo "  Using Cloudflare Tunnel (external access enabled)"
        echo "  Base Domain: ${base_domain}"
        echo ""
        echo "  Example URLs:"
        echo "    • Dashboard:   https://home.${base_domain}"
        echo "    • Coder:       https://coder.${base_domain}"
        echo "    • Traefik:     https://traefik.${base_domain}"
    else
        echo "  Local IP Access: ${host_ip}"
        echo ""
        echo "  Common services:"
        echo "    • Dashboard:   http://${host_ip}:8080"
        echo "    • Coder:       http://${host_ip}:7080"
        echo "    • Traefik:     http://${host_ip}:8081"
        echo "    • Pi-hole:     http://${host_ip}:8091"
        echo ""
        echo "  With .${lab_domain} DNS (requires Pi-hole setup):"
        echo "    • Dashboard:   https://home.${lab_domain}"
        echo "    • Any service: https://<service>.${lab_domain}"
    fi
    
    echo ""
    echo -e "${BOLD}Documentation:${NC}"
    echo "  • Complete summary: SETUP_SUMMARY.md"
    echo "  • Service guides:   docs/"
    echo ""
    
    echo -e "${BOLD}Important:${NC}"
    echo "  • CHANGE DEFAULT PASSWORDS after first login!"
    echo "  • First account created becomes admin for most services"
    echo "  • Uptime Kuma: add Docker host → Socket: /var/run/docker.sock"
    echo ""
    
    log_success "Your WeekendStack is ready to use!"
    echo ""
}

# Export functions
export -f generate_setup_summary add_service_urls add_external_service_urls
export -f display_summary_to_console
