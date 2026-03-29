#!/bin/bash
# Unit tests for access mode normalization helpers

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"
source "$PROJECT_ROOT/tools/setup/lib/common.sh"

test_suite_start "Access Mode Helpers"

test_case "normalize_access_mode understands new and legacy values"
if [[ "$(normalize_access_mode tunnel)" == "tunnel" ]] && \
   [[ "$(normalize_access_mode local)" == "local" ]] && \
   [[ "$(normalize_access_mode ip)" == "ip" ]] && \
   [[ "$(normalize_access_mode cloudflare)" == "tunnel" ]] && \
   [[ "$(normalize_access_mode pihole)" == "local" ]] && \
   [[ "$(normalize_access_mode both)" == "tunnel" ]]; then
    test_pass
else
    test_fail "Expected access mode normalization to map tunnel/local/ip and legacy values correctly"
fi

test_case "legacy combined mode still reports both tunnel and local capabilities"
if has_tunnel_access_mode "both" && has_local_domain_access_mode "both"; then
    test_pass
else
    test_fail "Expected legacy DOMAIN_MODE=both to retain tunnel and local-domain capability checks"
fi

test_case "local mode does not report tunnel capability"
if ! has_tunnel_access_mode "local" && has_local_domain_access_mode "local"; then
    test_pass
else
    test_fail "Expected local access mode to be local-only"
fi

test_suite_end
