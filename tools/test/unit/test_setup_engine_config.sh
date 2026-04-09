#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$PROJECT_ROOT/tools/setup/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"
source "$PROJECT_ROOT/tools/setup/lib/service-catalog.sh"
source "$PROJECT_ROOT/tools/setup/lib/env-generator.sh"
source "$PROJECT_ROOT/tools/setup/lib/setup-engine.sh"

save_optional_file() {
    local source_path="$1"
    local backup_path="$2"

    if [[ -f "$source_path" ]]; then
        mkdir -p "$(dirname "$backup_path")"
        cp "$source_path" "$backup_path"
        return 0
    fi

    return 1
}

restore_optional_file() {
    local target_path="$1"
    local backup_path="$2"

    if [[ -f "$backup_path" ]]; then
        cp "$backup_path" "$target_path"
        rm -f "$backup_path"
    else
        rm -f "$target_path"
    fi
}

test_suite_start "Setup Engine Config"

TEST_CONFIG="$TEST_DIR/weekendstack.config.json"

test_case "env migration creates canonical config with profiles and optional services"
create_temp_env
cat > "$TEST_ENV" <<'EOF'
COMPUTER_NAME=testbox
HOST_IP=192.168.2.50
TZ=America/New_York
PUID=1000
PGID=1000
DOMAIN_MODE=tunnel
LAB_DOMAIN=lab
BASE_DOMAIN=weekendcodeproject.dev
DEFAULT_TRAEFIK_AUTH_USER=weekend
DEFAULT_TRAEFIK_AUTH_PASS=StrongPass123!
FILES_BASE_DIR=/tmp/files
DATA_BASE_DIR=/tmp/data
WORKSPACE_DIR=/tmp/workspace
SSH_KEY_DIR=${CONFIG_BASE_DIR}/ssh
COMPOSE_PROFILES=core,dev,ai,open-webui,gitea,networking,external,ollama-cpu
EOF

setup_engine_migrate_env_to_config "$TEST_ENV" "$TEST_CONFIG" >/dev/null 2>&1

migrated_profiles="$(jq -r '.selection.profiles | join(",")' "$TEST_CONFIG")"
migrated_services="$(jq -r '.selection.services | join(",")' "$TEST_CONFIG")"
migrated_mode="$(jq -r '.access.mode' "$TEST_CONFIG")"

if [[ "$migrated_profiles" == "core,dev,ai" && "$migrated_services" == "open-webui,gitea" && "$migrated_mode" == "tunnel" ]]; then
    test_pass
else
    test_fail "Unexpected migrated config: profiles=$migrated_profiles services=$migrated_services mode=$migrated_mode"
fi

test_case "env migration preserves explicit all selection from SELECTED_PROFILES"
create_temp_env
cat > "$TEST_ENV" <<'EOF'
HOST_IP=192.168.2.50
TZ=America/New_York
DOMAIN_MODE=local
LAB_DOMAIN=lab
LOCAL_DNS_MODE=pihole
SELECTED_PROFILES=all
COMPOSE_PROFILES=all,gitea,open-webui,ollama-cpu,networking,pihole
GIT_SERVICE=gitea
EOF

setup_engine_migrate_env_to_config "$TEST_ENV" "$TEST_CONFIG" >/dev/null 2>&1

migrated_profiles="$(jq -r '.selection.profiles | join(",")' "$TEST_CONFIG")"
migrated_services="$(jq -r '.selection.services | join(",")' "$TEST_CONFIG")"
migrated_dns_mode="$(jq -r '.access.local_dns_mode' "$TEST_CONFIG")"

if [[ "$migrated_profiles" == "all" && "$migrated_services" == "open-webui,gitea" && "$migrated_dns_mode" == "pihole" ]]; then
    test_pass
else
    test_fail "Unexpected migrated all-profile config: profiles=$migrated_profiles services=$migrated_services dns=$migrated_dns_mode"
fi

test_case "add flow merges profiles and services without duplicates"
jq '.selection = {profiles:["core","ai"], services:["open-webui"], ai_runtime:"cpu"}' "$TEST_CONFIG" > "${TEST_CONFIG}.tmp" && mv "${TEST_CONFIG}.tmp" "$TEST_CONFIG"
setup_engine_add_to_config "$TEST_CONFIG" "monitoring,ai" "paperclip,open-webui"

merged_profiles="$(jq -r '.selection.profiles | join(",")' "$TEST_CONFIG")"
merged_services="$(jq -r '.selection.services | join(",")' "$TEST_CONFIG")"

if [[ "$merged_profiles" == "core,ai,monitoring" && "$merged_services" == "open-webui,paperclip" ]]; then
    test_pass
else
    test_fail "Unexpected merged config: profiles=$merged_profiles services=$merged_services"
fi

test_case "write env from config emits effective compose profiles"
cd "$PROJECT_ROOT"
save_optional_file "docker-compose.custom.yml" "$TEST_DIR/original.docker-compose.custom.yml"
GENERATED_ENV="$TEST_DIR/generated.env"

jq -n '
{
  version: 1,
  system: {computer_name:"testbox", host_ip:"192.168.2.50", timezone:"America/New_York", puid:1000, pgid:1000},
  access: {mode:"local", lab_domain:"lab", base_domain:"", local_dns_mode:"manual", tunnel_auth:{username:"admin", password:""}},
  selection: {profiles:["core","ai"], services:["open-webui","paperclip"], ai_runtime:"cpu"},
  paths: {files_base_dir:"'"$TEST_DIR"'/files", data_base_dir:"'"$TEST_DIR"'/data", workspace_dir:"'"$TEST_DIR"'/workspace", ssh_key_dir:"${CONFIG_BASE_DIR}/ssh"},
  cloudflare: {enabled:false, api_token:"", tunnel_id:"", tunnel_name:"weekendstack-tunnel", account_id:"", tunnel_token:""},
  options: {cleanup_mode:"auto"}
}
' > "$TEST_CONFIG"

setup_engine_write_env_from_config "$TEST_CONFIG" "$GENERATED_ENV"
compose_profiles="$(grep '^COMPOSE_PROFILES=' "$GENERATED_ENV" | cut -d'=' -f2-)"

if [[ "$compose_profiles" == *"core"* && "$compose_profiles" == *"ai"* && "$compose_profiles" == *"open-webui"* && "$compose_profiles" == *"paperclip"* && "$compose_profiles" == *"ollama-cpu"* && "$compose_profiles" == *"networking"* ]]; then
    test_pass
else
    test_fail "Unexpected COMPOSE_PROFILES: $compose_profiles"
fi

test_case "write env from config keeps selected profiles separate from effective compose profiles"
selected_profiles="$(grep '^SELECTED_PROFILES=' "$GENERATED_ENV" | cut -d'=' -f2-)"
local_dns_mode="$(grep '^LOCAL_DNS_MODE=' "$GENERATED_ENV" | cut -d'=' -f2-)"

if [[ "$selected_profiles" == "core,ai" && "$local_dns_mode" == "manual" ]]; then
    test_pass
else
    test_fail "Unexpected selected profile metadata: selected=$selected_profiles dns=$local_dns_mode"
fi

test_case "write env from config backfills compose-only vars for unselected services"
if grep -q '^CODER_HOSTNAME=' "$GENERATED_ENV" && \
   grep -q '^GITEA_DBPASS=' "$GENERATED_ENV" && \
   grep -q '^NOCODB_JWT_SECRET=' "$GENERATED_ENV"; then
    test_pass
else
    test_fail "Expected compose placeholders for unselected services to be backfilled into .env"
fi

restore_optional_file "docker-compose.custom.yml" "$TEST_DIR/original.docker-compose.custom.yml"

test_suite_end
