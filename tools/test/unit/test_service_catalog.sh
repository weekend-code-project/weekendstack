#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$PROJECT_ROOT/tools/setup/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"
source "$PROJECT_ROOT/tools/setup/lib/service-catalog.sh"

test_suite_start "Service Catalog"

test_case "catalog file and jq are available"
if catalog_requirements_ok; then
    test_pass
else
    test_fail "Catalog file or jq missing"
fi

test_case "selectable profiles include core and ai"
selectable_profiles="$(catalog_profile_ids selectable | tr '\n' ' ')"
if [[ "$selectable_profiles" == *"core"* && "$selectable_profiles" == *"ai"* ]]; then
    test_pass
else
    test_fail "Expected selectable profiles to include core and ai, got: $selectable_profiles"
fi

test_case "optional services expose service-specific activation profiles"
open_webui_profiles="$(catalog_service_activation_profiles open-webui | tr '\n' ',' | sed 's/,$//')"
gitea_profiles="$(catalog_service_activation_profiles gitea | tr '\n' ',' | sed 's/,$//')"
if [[ "$open_webui_profiles" == "open-webui" && "$gitea_profiles" == "gitea" ]]; then
    test_pass
else
    test_fail "Unexpected activation profiles: open-webui=$open_webui_profiles gitea=$gitea_profiles"
fi

test_case "service lookup uses activation profiles instead of broad ai defaults"
resolved_services="$(catalog_services_for_activation_profiles "core,ai,open-webui,networking" | tr '\n' ' ')"
if [[ "$resolved_services" == *"ollama"* && "$resolved_services" == *"open-webui"* && "$resolved_services" != *"paperclip"* ]]; then
    test_pass
else
    test_fail "Resolved services were incorrect: $resolved_services"
fi

test_case "resource totals include profile and optional service overrides"
read -r memory_gb disk_gb <<< "$(catalog_sum_resources "core,ai,networking" "paperclip,whisper")"
if [[ "$memory_gb" -ge 23 && "$disk_gb" -ge 55 ]]; then
    test_pass
else
    test_fail "Unexpected resource totals: memory=${memory_gb} disk=${disk_gb}"
fi

test_suite_end
