#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CATALOG_FILE="${REPO_ROOT}/tools/env/mappings/service-metadata.json"

usage() {
    cat <<'EOF'
Usage:
  tools/setup/scaffold-service.sh \
    --id SERVICE_ID \
    --display-name "Service Name" \
    --description "What it does" \
    --profile PROFILE \
    --template RELATIVE_TEMPLATE_PATH \
    --compose-file RELATIVE_COMPOSE_FILE \
    [--activation-profile PROFILE] \
    [--subdomain SUBDOMAIN] \
    [--port PORT] \
    [--selectable]

This creates:
  - a service catalog entry in tools/env/mappings/service-metadata.json
  - an env template stub
  - a compose snippet stub
  - a baseline unit test
EOF
}

SERVICE_ID=""
DISPLAY_NAME=""
DESCRIPTION=""
PROFILE=""
TEMPLATE_PATH=""
COMPOSE_FILE=""
ACTIVATION_PROFILE=""
SUBDOMAIN=""
PORT=""
SELECTABLE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --id) SERVICE_ID="$2"; shift 2 ;;
        --display-name) DISPLAY_NAME="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --template) TEMPLATE_PATH="$2"; shift 2 ;;
        --compose-file) COMPOSE_FILE="$2"; shift 2 ;;
        --activation-profile) ACTIVATION_PROFILE="$2"; shift 2 ;;
        --subdomain) SUBDOMAIN="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --selectable) SELECTABLE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[[ -n "$SERVICE_ID" && -n "$DISPLAY_NAME" && -n "$DESCRIPTION" && -n "$PROFILE" && -n "$TEMPLATE_PATH" && -n "$COMPOSE_FILE" ]] || {
    usage
    exit 1
}

[[ -f "$CATALOG_FILE" ]] || {
    echo "Catalog not found: $CATALOG_FILE" >&2
    exit 1
}

if jq -e --arg profile "$PROFILE" '._profiles[$profile]' "$CATALOG_FILE" >/dev/null 2>&1; then
    :
else
    echo "Unknown profile '$PROFILE' in $CATALOG_FILE" >&2
    exit 1
fi

if jq -e --arg service "$SERVICE_ID" 'has($service)' "$CATALOG_FILE" >/dev/null 2>&1; then
    echo "Service '$SERVICE_ID' already exists in the catalog" >&2
    exit 1
fi

ACTIVATION_PROFILE="${ACTIVATION_PROFILE:-$PROFILE}"
SUBDOMAIN="${SUBDOMAIN:-$SERVICE_ID}"

tmp_file="$(mktemp)"
jq \
    --arg service "$SERVICE_ID" \
    --arg display_name "$DISPLAY_NAME" \
    --arg description "$DESCRIPTION" \
    --arg template "$TEMPLATE_PATH" \
    --arg profile "$PROFILE" \
    --arg compose_file "$COMPOSE_FILE" \
    --arg activation_profile "$ACTIVATION_PROFILE" \
    --arg subdomain "$SUBDOMAIN" \
    --arg selectable "$SELECTABLE" \
    --arg port "$PORT" \
    '
    . + {
      ($service): {
        display_name: $display_name,
        description: $description,
        template: $template,
        profile: $profile,
        activation_profiles: [$activation_profile],
        compose_file: $compose_file,
        subdomain: $subdomain,
        first_run_mode: "manual",
        selectable_service: ($selectable == "true")
      }
    }
    | if $port != "" then .[$service].ip_port = ($port | tonumber) else . end
    ' "$CATALOG_FILE" > "$tmp_file"
mv "$tmp_file" "$CATALOG_FILE"

template_file="${REPO_ROOT}/tools/env/templates/${TEMPLATE_PATH}"
mkdir -p "$(dirname "$template_file")"
if [[ ! -f "$template_file" ]]; then
    cat > "$template_file" <<EOF
# =============================================================================
# ${DISPLAY_NAME}
# =============================================================================
# Add service-specific environment variables here.
EOF
fi

compose_stub="${REPO_ROOT}/tools/setup/scaffolds/${SERVICE_ID}.compose-snippet.yml"
mkdir -p "$(dirname "$compose_stub")"
cat > "$compose_stub" <<EOF
# Compose snippet for ${DISPLAY_NAME}
# Merge this into: ${COMPOSE_FILE}
${SERVICE_ID}:
  image: REPLACE_ME
  profiles:
    - ${ACTIVATION_PROFILE}
EOF

test_file="${REPO_ROOT}/tools/test/unit/test_${SERVICE_ID//-/_}_catalog.sh"
cat > "$test_file" <<EOF
#!/bin/bash
set -e

PROJECT_ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/../../.." && pwd)"
CATALOG_FILE="\${PROJECT_ROOT}/tools/env/mappings/service-metadata.json"

jq -e --arg service "${SERVICE_ID}" '.[\$service]' "\$CATALOG_FILE" >/dev/null
jq -e --arg service "${SERVICE_ID}" '.[\$service].compose_file != ""' "\$CATALOG_FILE" >/dev/null
jq -e --arg service "${SERVICE_ID}" '.[\$service].template != ""' "\$CATALOG_FILE" >/dev/null
EOF
chmod +x "$test_file"

echo "Scaffolded ${SERVICE_ID}"
echo "  Catalog: $CATALOG_FILE"
echo "  Template: $template_file"
echo "  Compose stub: $compose_stub"
echo "  Test: $test_file"
