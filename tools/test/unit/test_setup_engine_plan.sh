#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$PROJECT_ROOT/tools/setup/lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"
source "$PROJECT_ROOT/tools/setup/lib/service-catalog.sh"
source "$PROJECT_ROOT/tools/setup/lib/setup-engine.sh"

test_suite_start "Setup Engine Plan"

mkdir -p "$TEST_DIR"
TEST_CONFIG="$TEST_DIR/weekendstack-plan.config.json"

cat > "$TEST_CONFIG" <<EOF
{
  "version": 1,
  "system": {"computer_name":"agentbox","host_ip":"192.168.2.50","timezone":"America/New_York","puid":1000,"pgid":1000},
  "access": {"mode":"tunnel","lab_domain":"lab","base_domain":"weekendcodeproject.dev","local_dns_mode":"none","tunnel_auth":{"username":"weekend","password":""}},
  "selection": {"profiles":["core","ai"],"services":["open-webui","paperclip"],"ai_runtime":"cpu"},
  "paths": {"files_base_dir":"$TEST_DIR/files","data_base_dir":"$TEST_DIR/data","workspace_dir":"$TEST_DIR/workspace","ssh_key_dir":"$TEST_DIR/ssh"},
  "cloudflare": {"enabled":true,"api_token":"","tunnel_id":"","tunnel_name":"weekendstack-tunnel","account_id":"","tunnel_token":""},
  "options": {"cleanup_mode":"auto"}
}
EOF

test_case "planner expands effective profiles and services from config"
plan_json="$(setup_engine_plan_json "$TEST_CONFIG")"
effective_profiles="$(printf '%s' "$plan_json" | jq -r '.effective_profiles | join(",")')"
effective_services="$(printf '%s' "$plan_json" | jq -r '.effective_services | join(",")')"

if [[ "$effective_profiles" == "core,ai,open-webui,paperclip,ollama-cpu,networking" ]] && \
   [[ "$effective_services" == *"open-webui"* ]] && \
   [[ "$effective_services" == *"paperclip"* ]] && \
   [[ "$effective_services" != *"cloudflare-tunnel"* ]]; then
    test_pass
else
    test_fail "Unexpected plan output: profiles=$effective_profiles services=$effective_services"
fi

test_case "planner reports configure actions, tunnel warnings, and manual followups"
warning_count="$(printf '%s' "$plan_json" | jq '.host_checks.warnings | length')"
manual_followups="$(printf '%s' "$plan_json" | jq -r '.manual_followups | map(.service) | join(",")')"
configure_actions="$(printf '%s' "$plan_json" | jq -r '.configure_actions | map(.id) | join(",")')"

if [[ "$warning_count" -ge 1 ]] && \
   [[ "$configure_actions" == *"tunnel-auth"* ]] && \
   [[ "$configure_actions" == *"cloudflare"* ]] && \
   [[ "$manual_followups" == *"open-webui"* ]] && \
   [[ "$manual_followups" == *"paperclip"* ]]; then
    test_pass
else
    test_fail "Expected configure actions, tunnel warning, and manual followups, got warnings=$warning_count actions=$configure_actions followups=$manual_followups"
fi

test_case "planner counts reclaimable Docker image space toward disk feasibility"
original_disk_free_fn="$(declare -f setup_engine_disk_free_gb)"
original_reclaim_fn="$(declare -f setup_engine_docker_reclaimable_gb)"
original_memory_fn="$(declare -f setup_engine_host_memory_gb)"

setup_engine_disk_free_gb() { echo "10"; }
setup_engine_docker_reclaimable_gb() { echo "60"; }
setup_engine_host_memory_gb() { echo "128"; }

plan_json="$(setup_engine_plan_json "$TEST_CONFIG")"
blocker_count="$(printf '%s' "$plan_json" | jq '.host_checks.blockers | length')"
effective_root_disk="$(printf '%s' "$plan_json" | jq -r '.host_checks.available_effective_root_disk_gb')"
reclaimable_root_disk="$(printf '%s' "$plan_json" | jq -r '.host_checks.reclaimable_root_disk_gb')"
reclaim_warning="$(printf '%s' "$plan_json" | jq -r '.host_checks.warnings[] | select(test("reclaimed from unused Docker images"))' | head -n 1)"

eval "$original_disk_free_fn"
eval "$original_reclaim_fn"
eval "$original_memory_fn"

if [[ "$blocker_count" == "0" ]] && [[ "$effective_root_disk" == "70" ]] && [[ "$reclaimable_root_disk" == "60" ]] && [[ -n "$reclaim_warning" ]]; then
    test_pass
else
    test_fail "Expected reclaimable disk to clear blockers, got blockers=$blocker_count effective=$effective_root_disk reclaimable=$reclaimable_root_disk warning=$reclaim_warning"
fi

test_suite_end
