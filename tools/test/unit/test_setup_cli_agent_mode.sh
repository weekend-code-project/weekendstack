#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$PROJECT_ROOT/tools/setup/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Setup CLI Agent Mode"

mkdir -p "$TEST_DIR"
TEST_CONFIG="$TEST_DIR/weekendstack-cli.config.json"

cat > "$TEST_CONFIG" <<EOF
{
  "version": 1,
  "system": {"computer_name":"agentbox","host_ip":"192.168.2.50","timezone":"America/New_York","puid":1000,"pgid":1000},
  "access": {"mode":"tunnel","lab_domain":"lab","base_domain":"weekendcodeproject.dev","local_dns_mode":"none","tunnel_auth":{"username":"weekend","password":"StrongPass123"}},
  "selection": {"profiles":["core","ai"],"services":["open-webui","paperclip"],"ai_runtime":"cpu"},
  "paths": {"files_base_dir":"$TEST_DIR/files","data_base_dir":"$TEST_DIR/data","workspace_dir":"$TEST_DIR/workspace","ssh_key_dir":"$TEST_DIR/ssh"},
  "cloudflare": {"enabled":true,"api_token":"","tunnel_id":"","tunnel_name":"weekendstack-tunnel","account_id":"","tunnel_token":""},
  "options": {"cleanup_mode":"auto"}
}
EOF

test_case "setup.sh --plan emits machine-readable JSON"
plan_output="$(bash "$PROJECT_ROOT/setup.sh" --plan --config "$TEST_CONFIG" --json)"
plan_mode="$(printf '%s' "$plan_output" | jq -r '.access_mode')"
plan_profiles="$(printf '%s' "$plan_output" | jq -r '.effective_profiles | join(",")')"

if [[ "$plan_mode" == "tunnel" ]] && [[ "$plan_profiles" == *"external"* ]]; then
    test_pass
else
    test_fail "Unexpected CLI plan output: mode=$plan_mode profiles=$plan_profiles"
fi

test_case "setup.sh --doctor emits machine-readable JSON"
doctor_output="$(bash "$PROJECT_ROOT/setup.sh" --doctor --config "$TEST_CONFIG" --json)"
config_exists="$(printf '%s' "$doctor_output" | jq -r '.files.config_exists')"
gpu_available="$(printf '%s' "$doctor_output" | jq -r '.host.gpu_available')"

if [[ "$config_exists" == "true" ]] && [[ "$gpu_available" =~ ^(true|false)$ ]]; then
    test_pass
else
    test_fail "Unexpected CLI doctor output: config_exists=$config_exists gpu_available=$gpu_available"
fi

test_suite_end
