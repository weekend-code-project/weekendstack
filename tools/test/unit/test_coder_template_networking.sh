#!/bin/bash
# Regression tests for Coder template networking defaults

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Coder Template Networking"

template_files=(
    "$PROJECT_ROOT/config/coder/templates/wordpress/main.tf"
    "$PROJECT_ROOT/config/coder/templates/database/main.tf"
    "$PROJECT_ROOT/config/coder/templates/node/main.tf"
    "$PROJECT_ROOT/config/coder/templates/vite/main.tf"
    "$PROJECT_ROOT/config/coder/templates/supabase/main.tf"
    "$PROJECT_ROOT/config/coder/templates/docker/main.tf"
)

test_case "Templates map host.docker.internal to the configured host IP"
bad_files=()
for file in "${template_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        bad_files+=("missing:$file")
        continue
    fi

    if ! grep -q 'host = "host.docker.internal"' "$file" || ! grep -q 'ip   = var.host_ip' "$file"; then
        bad_files+=("$file")
    fi
done

if [[ ${#bad_files[@]} -eq 0 ]]; then
    test_pass
else
    test_fail "Unexpected host mapping in: ${bad_files[*]}"
fi

test_case "Templates do not use unsupported host-gateway extra host values"
host_gateway_files=()
for file in "${template_files[@]}"; do
    if [[ -f "$file" ]] && grep -q '"host-gateway"' "$file"; then
        host_gateway_files+=("$file")
    fi
done

if [[ ${#host_gateway_files[@]} -eq 0 ]]; then
    test_pass
else
    test_fail "Found host-gateway in: ${host_gateway_files[*]}"
fi

test_case "Setup copy no longer claims hidden template selection"
if grep -q 'Pushing WeekendStack templates into the running Coder instance\.' "$PROJECT_ROOT/setup.sh" && \
   ! grep -q 'Pushing the selected templates into the running Coder instance\.' "$PROJECT_ROOT/setup.sh"; then
    test_pass
else
    test_fail "Unexpected Coder template deployment copy in setup.sh"
fi

test_suite_end
