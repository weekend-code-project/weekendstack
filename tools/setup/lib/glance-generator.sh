#!/bin/bash
# ==============================================================================
# Glance Dashboard Configuration Generator
# ==============================================================================
# Generates config/glance/glance.yml dynamically from the selected profiles
# stored in COMPOSE_PROFILES / SELECTED_PROFILES (or passed as arguments).
#
# Called by setup.sh:
#   - From preflight_fix_mounts() to ensure the file exists before docker up
#   - Can also be called standalone: bash tools/setup/lib/glance-generator.sh
#
# Rules:
#   - Single page only ("Home", slug: home)  — no separate External page
#   - Monitor widget entries filtered by enabled profile
#   - Speedtest in monitor widget (core, always), no separate custom-api widget
#   - Dozzle in monitor widget (monitoring section, gated by monitoring profile)
#   - Small column: server-stats (always), then profile-gated widgets
#   - Navigation url: fields always use /go/<service> (link-router handles context)
#   - Internal API urls use Docker-network service names (not HOST_IP) where possible
# ==============================================================================

# Resolve SCRIPT_DIR (works whether sourced or executed directly)
_glance_gen_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ws_root="$(cd "$_glance_gen_dir/../../.." && pwd)"

generate_glance_config() {
    local output="${1:-$_ws_root/config/glance/glance.yml}"
    local env_file="${2:-$_ws_root/.env}"

    # ── Read config from .env ────────────────────────────────────────────────
    local host_ip base_domain lab_domain kavita_port domain_mode
    host_ip=$(grep "^HOST_IP=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d ' "') 
    host_ip="${host_ip:-192.168.2.50}"
    base_domain=$(grep "^BASE_DOMAIN=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    base_domain="${base_domain:-}"
    lab_domain=$(grep "^LAB_DOMAIN=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    lab_domain="${lab_domain:-lab}"
    kavita_port=$(grep "^KAVITA_PORT=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    kavita_port="${kavita_port:-5002}"
    domain_mode=$(grep "^DOMAIN_MODE=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    domain_mode="${domain_mode:-ip}"

    # ── Determine enabled profiles ───────────────────────────────────────────
    local profiles_raw
    profiles_raw=$(grep "^COMPOSE_PROFILES=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
    # Also accept caller-passed profiles as $SELECTED_PROFILES env var
    if [[ -z "$profiles_raw" && -n "${SELECTED_PROFILES[*]:-}" ]]; then
        profiles_raw="${SELECTED_PROFILES[*]}"
        profiles_raw="${profiles_raw// /,}"
    fi

    # Service profiles: "all" implies these
    _glance_has_profile() {
        local check="$1"
        [[ ",$profiles_raw," == *",$check,"* ]] || [[ ",$profiles_raw," == *",all,"* ]]
    }
    # Infrastructure profiles: pihole/networking/external are NEVER implied by "all"
    _glance_has_infra_profile() {
        local check="$1"
        [[ ",$profiles_raw," == *",$check,"* ]]
    }

    local has_networking; _glance_has_infra_profile "networking" && has_networking=true || has_networking=false
    local has_pihole;     _glance_has_infra_profile "pihole"     && has_pihole=true     || has_pihole=false
    local has_monitoring; _glance_has_profile "monitoring" && has_monitoring=true || has_monitoring=false
    local has_ai;         _glance_has_profile "ai"         && has_ai=true         || has_ai=false
    local has_media;      _glance_has_profile "media"      && has_media=true      || has_media=false

    # ── Navigation URL strategy ───────────────────────────────────────────────
    # Use full absolute URLs so links work regardless of how glance is accessed
    # (direct IP, lab domain, or Cloudflare tunnel).
    # Priority: cloudflare/both → BASE_DOMAIN; pihole → LAB_DOMAIN; else → IP:PORT

    local url_dozzle url_speedtest url_traefik url_pihole
    local url_portainer url_uptimekuma url_wud
    local url_ollama url_whisper
    local url_immich url_kavita url_navidrome

    if [[ "$domain_mode" == "cloudflare" || "$domain_mode" == "both" ]]; then
        # Cloudflare tunnel — absolute HTTPS URLs (work from LAN and externally)
        url_dozzle="https://dozzle.${base_domain}"
        url_speedtest="https://speedtest.${base_domain}"
        url_traefik="https://traefik.${base_domain}"
        url_pihole="https://pihole.${base_domain}"
        url_portainer="https://portainer.${base_domain}"
        url_uptimekuma="https://uptime-kuma.${base_domain}"
        url_wud="https://wud.${base_domain}"
        url_ollama="https://ollama.${base_domain}"
        url_whisper="https://whisper.${base_domain}"
        url_immich="https://immich.${base_domain}"
        url_kavita="https://kavita.${base_domain}"
        url_navidrome="https://navidrome.${base_domain}"
    elif [[ "$domain_mode" == "pihole" ]]; then
        # Local lab domain (LAN only, requires Pi-hole DNS)
        url_dozzle="https://dozzle.${lab_domain}"
        url_speedtest="https://speedtest.${lab_domain}"
        url_traefik="https://traefik.${lab_domain}"
        url_pihole="https://pihole.${lab_domain}"
        url_portainer="https://portainer.${lab_domain}"
        url_uptimekuma="https://uptime-kuma.${lab_domain}"
        url_wud="https://wud.${lab_domain}"
        url_ollama="https://ollama.${lab_domain}"
        url_whisper="https://whisper.${lab_domain}"
        url_immich="https://immich.${lab_domain}"
        url_kavita="https://kavita.${lab_domain}"
        url_navidrome="https://navidrome.${lab_domain}"
    else
        # IP-only — direct HOST_IP:PORT links
        url_dozzle="http://${host_ip}:9999"
        url_speedtest="http://${host_ip}:8765"
        url_traefik="http://${host_ip}:8081"
        url_pihole="http://${host_ip}:8088/admin"
        url_portainer="http://${host_ip}:9000"
        url_uptimekuma="http://${host_ip}:3001"
        url_wud="http://${host_ip}:3002"
        url_ollama="http://${host_ip}:11434"
        url_whisper="http://${host_ip}:9002"
        url_immich="http://${host_ip}:2283"
        url_kavita="http://${host_ip}:${kavita_port}"
        url_navidrome="http://${host_ip}:4533"
    fi

    # ── Ensure output directory exists ───────────────────────────────────────
    mkdir -p "$(dirname "$output")"

    # ── Write config ─────────────────────────────────────────────────────────
    cat > "$output" << GLANCE_EOF
# ==============================================================================
# Glance Dashboard Configuration — AUTO-GENERATED
# ==============================================================================
# This file is generated by tools/setup/lib/glance-generator.sh.
# Re-run setup.sh or: bash tools/setup/lib/glance-generator.sh
# to regenerate it after changing service profiles.
#
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Profiles:  ${profiles_raw:-core}
# ==============================================================================

server:
  port: 8080
  proxied: true
  allow-potentially-dangerous-html: true

branding:
  hide-footer: true
  app-name: "Weekend Stack"

pages:
  - name: Home
    slug: home
    hide-desktop-navigation: true
    columns:
      - size: full
        widgets:
          - type: monitor
            cache: 1m
            title: APIs & Monitoring
            sites:
              # ── Core (always present) ─────────────────────────────────────
              - title: Speedtest
                url: ${url_speedtest}
                check-url: http://${host_ip}:8765
                icon: si:speedtest
GLANCE_EOF

    # Networking profile entries (Traefik only — Pi-hole is separate)
    if $has_networking; then
        cat >> "$output" << GLANCE_EOF
              # ── Networking ────────────────────────────────────────────────
              - title: Traefik
                url: ${url_traefik}
                check-url: http://${host_ip}:8081/api/overview
                icon: si:traefikproxy
GLANCE_EOF
    fi

    # Pi-hole (only when pihole profile explicitly selected)
    if $has_pihole; then
        cat >> "$output" << GLANCE_EOF
              - title: Pi-hole
                url: ${url_pihole}
                check-url: http://${host_ip}:8088/admin/
                icon: si:pihole
GLANCE_EOF
    fi

    # Monitoring profile entries (Dozzle, Portainer, Uptime Kuma, WUD)
    if $has_monitoring; then
        cat >> "$output" << GLANCE_EOF
              # ── Monitoring ────────────────────────────────────────────────
              - title: Dozzle
                url: ${url_dozzle}
                check-url: http://${host_ip}:9999
                icon: si:docker
              - title: Portainer
                url: ${url_portainer}
                check-url: http://${host_ip}:9000
                icon: si:portainer
              - title: Uptime Kuma
                url: ${url_uptimekuma}
                check-url: http://${host_ip}:3001
                icon: si:uptimekuma
              - title: WUD
                url: ${url_wud}
                check-url: http://${host_ip}:3002
                icon: si:docker
GLANCE_EOF
    fi

    # AI profile entries
    if $has_ai; then
        cat >> "$output" << GLANCE_EOF
              # ── AI ────────────────────────────────────────────────────────
              - title: Ollama
                url: ${url_ollama}
                check-url: http://${host_ip}:11434/api/tags
                icon: si:ollama
              - title: Whisper
                url: ${url_whisper}
                check-url: http://${host_ip}:9002
                icon: si:openai
GLANCE_EOF
    fi

    # Close monitor widget + add docker-containers widget
    cat >> "$output" << GLANCE_EOF

          - type: docker-containers
            limit: 50

      - size: small
        widgets:
          # ── Always present ─────────────────────────────────────────────
          - type: server-stats
            servers:
              - type: local
                name: Docker VM
GLANCE_EOF

    # Media profile widgets
    if $has_media; then
        cat >> "$output" << GLANCE_EOF

          # ── Media ──────────────────────────────────────────────────────
          - type: custom-api
            cache: 5m
            title: Immich Stats
            title-url: ${url_immich}
            url: http://${host_ip}:2283/api/server-info/stats
            headers:
              x-api-key: "\${IMMICH_API_KEY}"
            template: |
              {{ \$photos := .JSON.Int "photos" }}
              {{ \$videos := .JSON.Int "videos" }}
              <div style="display: flex; justify-content: space-around; margin: 1rem 0;">
                <div style="text-align: center;">
                  <div style="font-size: 1.4rem;">{{ \$photos }}</div>
                  <div style="font-size: 0.9rem; opacity: 0.8;">Photos</div>
                </div>
                <div style="text-align: center;">
                  <div style="font-size: 1.4rem;">{{ \$videos }}</div>
                  <div style="font-size: 0.9rem; opacity: 0.8;">Videos</div>
                </div>
                <div style="text-align: center;">
                  <div style="font-size: 1.4rem;">{{ add \$photos \$videos }}</div>
                  <div style="font-size: 0.9rem; opacity: 0.8;">Total</div>
                </div>
              </div>

          - type: custom-api
            cache: 5m
            title: Kavita Latest
            title-url: ${url_kavita}
            method: POST
            url: http://${host_ip}:${kavita_port}/api/Series/v2?pageNumber=1&pageSize=5
            headers:
              Authorization: "Bearer \${KAVITA_API_KEY}"
              Content-Type: application/json
            body: '{"statements":[],"combination":1,"sortOptions":{"sortField":5,"isAscending":false}}'
            template: |
              {{ range .JSON.Array "content" }}
                <li>
                  <div class="size-h4">{{ .String "name" }}</div>
                  <div style="font-size: 0.9rem; opacity: 0.8;">{{ .String "libraryName" }}</div>
                </li>
              {{ end }}

          - type: custom-api
            cache: 5m
            title: Navidrome Stats
            title-url: ${url_navidrome}
            url: http://${host_ip}:4533/rest/getUser.view?u=admin&p=admin&v=1.16.1&c=glance&f=json
            template: |
              {{ \$artists := .JSON.Int "subsonic-response.user.artistCount" }}
              {{ \$albums := .JSON.Int "subsonic-response.user.albumCount" }}
              {{ \$songs := .JSON.Int "subsonic-response.user.trackCount" }}
              <div style="display: flex; justify-content: space-around; margin: 1rem 0;">
                <div style="text-align: center;">
                  <div style="font-size: 1.4rem;">{{ \$artists }}</div>
                  <div style="font-size: 0.9rem; opacity: 0.8;">Artists</div>
                </div>
                <div style="text-align: center;">
                  <div style="font-size: 1.4rem;">{{ \$albums }}</div>
                  <div style="font-size: 0.9rem; opacity: 0.8;">Albums</div>
                </div>
                <div style="text-align: center;">
                  <div style="font-size: 1.4rem;">{{ \$songs }}</div>
                  <div style="font-size: 0.9rem; opacity: 0.8;">Songs</div>
                </div>
              </div>
GLANCE_EOF
    fi

    # Monitoring profile: WUD widget (monitoring tools management)
    if $has_monitoring; then
        cat >> "$output" << GLANCE_EOF

          # ── Monitoring ─────────────────────────────────────────────────
          - type: custom-api
            title: What's Up Docker?
            title-url: ${url_wud}
            cache: 1h
            url: http://wud:3000/api/containers/
            method: GET
            template: |
              {{/* WUD Monitor */}}
              {{ \$containers := .JSON.Array "" }}
              {{ \$total := len \$containers }}
              {{ \$updates := 0 }}
              {{ \$running := 0 }}
              {{ \$hasUpdates := false }}

              {{ range \$containers }}
                {{ if .Bool "updateAvailable" }}
                  {{ \$updates = add \$updates 1 }}
                {{ end }}
                {{ if eq (.String "status") "running" }}
                  {{ \$running = add \$running 1 }}
                {{ end }}
              {{ end }}

              <div style="display: flex; justify-content: space-around; margin: 1rem 0;">
                <div style="text-align: center;">
                  <div style="font-size: 1.4rem;">{{ \$updates }}</div>
                  <div style="font-size: 0.9rem; opacity: 0.8;">Updates</div>
                </div>
                <div style="text-align: center;">
                  <div style="font-size: 1.4rem;">{{ \$total }}</div>
                  <div style="font-size: 0.9rem; opacity: 0.8;">Total</div>
                </div>
                <div style="text-align: center;">
                  <div style="font-size: 1.4rem;">{{ \$running }}</div>
                  <div style="font-size: 0.9rem; opacity: 0.8;">Running</div>
                </div>
              </div>

              <ul class="list list-gap-10 collapsible-container" data-collapse-after="5">
                {{ range \$containers }}
                  {{ if .Bool "updateAvailable" }}
                    {{ \$hasUpdates = true }}
                    <li>
                      <div class="size-h4">
                        {{ if eq (.String "status") "running" }}
                          <span class="color-positive">●</span>
                        {{ else }}
                          <span class="color-negative">●</span>
                        {{ end }}
                        <a href="${url_wud}" target="_blank" style="color: inherit; text-decoration: none;">{{ .String "name" }}</a>
                      </div>
                      <div style="display: flex; gap: 1rem; margin-top: 0.25rem; font-size: 0.9rem; opacity: 0.8;">
                        {{ \$localValue := .String "updateKind.localValue" }}
                        {{ if ge (len \$localValue) 7 }}
                          {{ \$isSha256 := eq (slice \$localValue 0 7) "sha256:" }}
                          {{ if \$isSha256 }}
                            <span>{{ slice \$localValue 7 11 }}</span>
                          {{ else }}
                            <span>{{ \$localValue }}</span>
                          {{ end }}
                        {{ else }}
                          <span>{{ \$localValue }}</span>
                        {{ end }}
                        <div>→
                          {{ \$tagValue := .String "updateKind.remoteValue" }}
                          {{ if ge (len \$tagValue) 7 }}
                            {{ \$isSha256 := eq (slice \$tagValue 0 7) "sha256:" }}
                            {{ if \$isSha256 }}
                              <span class="color-primary">{{ slice \$tagValue 7 11 }}</span>
                            {{ else }}
                              <span class="color-primary">{{ \$tagValue }}</span>
                            {{ end }}
                          {{ else }}
                            <span class="color-primary">{{ \$tagValue }}</span>
                          {{ end }}
                        </div>
                      </div>
                    </li>
                  {{ end }}
                {{ end }}

                {{ if not \$hasUpdates }}
                  <li class="flex items-center justify-center">
                    <span class="color-positive size-h4">All containers are up to date!</span>
                  </li>
                {{ end }}
              </ul>
GLANCE_EOF
    fi

    # Close the YAML document
    echo "" >> "$output"

    if type log_success &>/dev/null; then
        log_success "Glance config generated: $output (profiles: ${profiles_raw:-core})"
    else
        echo "✓ Glance config generated: $output (profiles: ${profiles_raw:-core})"
    fi
}

# ── Standalone execution ──────────────────────────────────────────────────────
# If this script is run directly (not sourced), call generate_glance_config
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Simple logging fallback when common.sh is not loaded
    if ! type log_success &>/dev/null; then
        log_success() { echo "✓ $*"; }
        log_info()    { echo "i $*"; }
    fi
    generate_glance_config "$@"
fi
