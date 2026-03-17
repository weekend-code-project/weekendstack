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
#   - Speedtest in monitor widget (core, always) + custom-api stats widget (↓/↑/ping)
#   - Monitoring tools in monitor widget (monitoring section, gated by monitoring profile)
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
    local host_ip base_domain lab_domain kavita_port domain_mode kavita_api_key
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
    kavita_api_key=$(grep "^KAVITA_API_KEY=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    kavita_api_key="${kavita_api_key:-}"

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

    local url_speedtest url_traefik url_pihole
    local url_uptimekuma url_wud
    local url_ollama url_whisper
    local url_immich url_kavita url_navidrome

    if [[ "$domain_mode" == "cloudflare" || "$domain_mode" == "both" ]]; then
        # Cloudflare tunnel — absolute HTTPS URLs (work from LAN and externally)
        url_speedtest="https://speedtest.${base_domain}"
        url_traefik="https://traefik.${base_domain}"
        url_pihole="https://pihole.${base_domain}"
        url_uptimekuma="https://uptime-kuma.${base_domain}"
        url_wud="https://wud.${base_domain}"
        url_ollama="https://ollama.${base_domain}"
        url_whisper="https://whisper.${base_domain}"
        url_immich="https://immich.${base_domain}"
        url_kavita="https://kavita.${base_domain}"
        url_navidrome="https://navidrome.${base_domain}"
    elif [[ "$domain_mode" == "pihole" ]]; then
        # Local lab domain (LAN only, requires Pi-hole DNS)
        url_speedtest="https://speedtest.${lab_domain}"
        url_traefik="https://traefik.${lab_domain}"
        url_pihole="https://pihole.${lab_domain}"
        url_uptimekuma="https://uptime-kuma.${lab_domain}"
        url_wud="https://wud.${lab_domain}"
        url_ollama="https://ollama.${lab_domain}"
        url_whisper="https://whisper.${lab_domain}"
        url_immich="https://immich.${lab_domain}"
        url_kavita="https://kavita.${lab_domain}"
        url_navidrome="https://navidrome.${lab_domain}"
    else
        # IP-only — direct HOST_IP:PORT links
        url_speedtest="http://${host_ip}:8765"
        url_traefik="http://${host_ip}:8081"
        url_pihole="http://${host_ip}:8088/admin"
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

    # Monitoring profile entries (Uptime Kuma, WUD)
    if $has_monitoring; then
        cat >> "$output" << GLANCE_EOF
              # ── Monitoring ────────────────────────────────────────────────
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

          - type: custom-api
            cache: 5m
            title: Internet Speed
            title-url: ${url_speedtest}
            url: http://${host_ip}:8765/api/v1/results/latest
            headers:
              Authorization: "Bearer \${SPEEDTEST_TRACKER_API_TOKEN}"
            template: |
              {{ \$dl   := .JSON.Float "data.download" }}
              {{ \$ul   := .JSON.Float "data.upload" }}
              {{ \$ping := .JSON.Float "data.ping" }}
              {{ \$ts   := .JSON.String "data.created_at" }}
              <div style="display: flex; justify-content: space-around; margin: 1rem 0;">
                <div style="text-align: center;">
                  <div style="font-size: 1.4rem;">{{ printf "%.1f" \$dl }}</div>
                  <div style="font-size: 0.9rem; opacity: 0.8;">↓ Mbps</div>
                </div>
                <div style="text-align: center;">
                  <div style="font-size: 1.4rem;">{{ printf "%.1f" \$ul }}</div>
                  <div style="font-size: 0.9rem; opacity: 0.8;">↑ Mbps</div>
                </div>
                <div style="text-align: center;">
                  <div style="font-size: 1.4rem;">{{ printf "%.0f" \$ping }}</div>
                  <div style="font-size: 0.9rem; opacity: 0.8;">ms ping</div>
                </div>
              </div>
              <div style="text-align: center; font-size: 0.8rem; opacity: 0.5;">{{ \$ts }}</div>
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

    # Kavita widget — only included when KAVITA_API_KEY is configured
    if $has_media && [[ -n "$kavita_api_key" ]]; then
        # Write the widget header with interpolated bash variables
        cat >> "$output" << GLANCE_EOF

          # ── Kavita ─────────────────────────────────────────────────────
          - type: custom-api
            title: Kavita Latest
            title-url: ${url_kavita}
            frameless: true
            cache: 5m
            options:
              base-url: "${url_kavita}"
              api-key: "${kavita_api_key}"
              mode: "recently-added"
              library: "0"
              small-column: false
              show-thumbnail: false
              thumbnail-aspect-ratio: "portrait"
            template: |
GLANCE_EOF
        # Write the Go template separately (quoted heredoc prevents bash variable expansion)
        cat >> "$output" << 'KAVITA_TEMPLATE_EOF'
              {{/* Required config options */}}
              {{ $baseURL := .Options.StringOr "base-url" "" }}
              {{ $apiKey := .Options.StringOr "api-key" "" }}
              {{ $mode := .Options.StringOr "mode" "recently-added" }}

              {{/* Optional config options */}}
              {{ $library := .Options.StringOr "library" "0" }}
              {{ $isSmallColumn := .Options.BoolOr "small-column" false }}
              {{ $thumbAspectRatio := .Options.StringOr "thumbnail-aspect-ratio" "" }}
              {{ $showThumbnail := .Options.BoolOr "show-thumbnail" false }}
              {{ $showProgressBar := .Options.BoolOr "progress-bar" true }}

              {{/* Error message template */}}
              {{ define "errorMsg" }}
                <div class="widget-error-header">
                  <div class="color-negative size-h3">ERROR</div>
                  <svg class="widget-error-icon" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"></path>
                  </svg>
                </div>
                <p class="break-all">{{ . }}</p>
              {{ end }}

              {{/* Check required fields */}}
              {{ if or (eq $baseURL "") (eq $apiKey "") (eq $mode "") }}
                {{ template "errorMsg" "Some required options are not set." }}
              {{ else }}

                {{/* Authenticate with Kavita to get a session Bearer token */}}
                {{ $authenticateCall := newRequest (print $baseURL "/api/Plugin/authenticate")
                    | withParameter "apiKey" $apiKey
                    | withParameter "pluginName" "glance"
                    | withHeader "Accept" "application/json"
                    | withStringBody ""
                    | getResponse }}
                {{ $token := concat "Bearer " ($authenticateCall.JSON.String "token") }}

                {{ if eq $token "Bearer " }}
                  {{ template "errorMsg" (printf "Error authenticating with Kavita. Check that the base URL and API key are correct.") }}
                {{ else }}
                  {{ $items := "" }}

                  {{ if eq $mode "recently-added" }}
                    {{ $recentlyAddedCall := newRequest (print $baseURL "/api/Series/recently-added-v2")
                        | withParameter "pageNumber" "1"
                        | withParameter "pageSize" "20"
                        | withHeader "Authorization" $token
                        | withHeader "Accept" "application/json"
                        | withHeader "Content-Type" "application/json"
                        | withStringBody "{}"
                        | getResponse }}
                    {{ $items = $recentlyAddedCall.JSON.Array "" }}

                  {{ else if eq $mode "recently-updated" }}
                    {{ $recentlyUpdatedCall := newRequest (print $baseURL "/api/Series/recently-updated-series")
                        | withHeader "Authorization" $token
                        | withHeader "Accept" "application/json"
                        | withStringBody ""
                        | getResponse }}
                    {{ $items = $recentlyUpdatedCall.JSON.Array "" }}

                  {{ else if eq $mode "on-deck" }}
                    {{ $onDeckCall := newRequest (print $baseURL "/api/Series/on-deck")
                        | withParameter "libraryId" $library
                        | withHeader "Authorization" $token
                        | withHeader "Accept" "application/json"
                        | withStringBody ""
                        | getResponse }}
                    {{ $items = $onDeckCall.JSON.Array "" }}

                  {{ else }}
                    {{ template "errorMsg" "Unknown mode — expected 'recently-added', 'recently-updated', or 'on-deck'" }}
                  {{ end }}

                  {{ if eq (len $items) 0 }}
                    <p>No items found — start reading something!</p>
                  {{ else }}
                    <div class="carousel-container show-right-cutoff">
                      <div class="cards-horizontal carousel-items-container">
                        {{ range $n, $item := $items }}
                          {{ $libraryID := $item.String "libraryId" }}
                          {{ $seriesID := $item.String "id" }}
                          {{ $title := $item.String "name" }}
                          {{ $progressPercent := "" }}

                          {{ if eq $mode "recently-updated" }}
                            {{ $title = $item.String "seriesName" }}
                            {{ $seriesID = $item.String "seriesId" }}
                          {{ else if eq $mode "on-deck" }}
                            {{ $pagesRead := $item.Float "pagesRead" }}
                            {{ $pages := $item.Float "pages" }}
                            {{ $progress := div $pagesRead $pages }}
                            {{ $progressPercent = printf "%f" (mul 100 $progress) }}
                          {{ end }}

                          {{ $linkURL := concat $baseURL "/library/" $libraryID "/series/" $seriesID }}
                          {{ $thumbURL := concat $baseURL "/api/image/series-cover?seriesId=" $seriesID "&apiKey=" $apiKey }}

                          <a class="card widget-content-frame" href="{{ $linkURL | safeURL }}">
                            {{ if $showThumbnail }}
                              <div style="position: relative;">
                                <img src="{{ $thumbURL | safeURL }}"
                                  alt="{{ $title }} thumbnail"
                                  loading="lazy"
                                  class="media-server-thumbnail shrink-0"
                                  style="
                                    object-fit: fill;
                                    border-radius: var(--border-radius) var(--border-radius) 0 0;
                                    width: 100%;
                                    display: block;
                                    {{ if eq $thumbAspectRatio "square" }}aspect-ratio: 1;
                                    {{ else if eq $thumbAspectRatio "portrait" }}aspect-ratio: 2/3;
                                    {{ else if eq $thumbAspectRatio "landscape" }}aspect-ratio: 16/9;
                                    {{ else }}aspect-ratio: initial;
                                    {{ end }}
                                  "
                                />
                                {{ if and $showProgressBar (not (eq $progressPercent "")) }}
                                  <div style="
                                    position: absolute;
                                    bottom: 8px;
                                    left: 8px;
                                    right: 8px;
                                    height: 6px;
                                    border-radius: var(--border-radius);
                                    overflow: hidden;
                                    background-color: rgba(255, 255, 255, 0.2);
                                  ">
                                    <div style="
                                      width: {{ print $progressPercent "%" }};
                                      height: 100%;
                                      border-radius: var(--border-radius) 0 0 var(--border-radius);
                                      background-color: var(--color-primary)
                                    "></div>
                                  </div>
                                {{ end }}
                              </div>
                            {{ end }}
                            <div class="grow padding-inline-widget margin-top-10 margin-bottom-10">
                              <ul class="flex flex-column justify-evenly margin-bottom-3 {{ if $isSmallColumn }}size-h6{{ end }}" style="height: 100%;">
                                <li class="text-truncate">{{ $title }}</li>
                              </ul>
                            </div>
                          </a>
                        {{ end }}
                      </div>
                    </div>
                  {{ end }}
                {{ end }}
              {{ end }}
KAVITA_TEMPLATE_EOF
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
