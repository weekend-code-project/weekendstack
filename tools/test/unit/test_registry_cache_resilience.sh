#!/bin/bash
# Unit tests for registry cache startup and uninstall resilience

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Registry Cache Resilience"

test_case "setup start paths prepare the registry cache before compose up"
startup_hook_count=$(grep -c 'prepare_registry_cache_for_startup' "$PROJECT_ROOT/setup.sh")
if [[ "$startup_hook_count" -ge 3 ]]; then
    test_pass
else
    test_fail "Expected setup.sh to prepare the registry cache in start, restart, and profile start paths"
fi

test_case "profile startup removes stale containers before bootstrapping registry cache"
profile_start_block=$(sed -n '/start_services_with_profiles()/,/^}/p' "$PROJECT_ROOT/setup.sh")
down_line=$(printf '%s\n' "$profile_start_block" | grep -n 'down --remove-orphans' | cut -d: -f1 | head -n1)
cache_line=$(printf '%s\n' "$profile_start_block" | grep -n 'prepare_registry_cache_for_startup' | cut -d: -f1 | head -n1)
if [[ -n "$down_line" && -n "$cache_line" && "$cache_line" -gt "$down_line" ]]; then
    test_pass
else
    test_fail "Expected profile startup to run compose down before starting the registry cache"
fi

test_case "registry cache helper can detect mirror state and prepare startup"
if grep -q '^docker_mirror_configured()' "$PROJECT_ROOT/tools/setup/lib/registry-cache.sh" && \
   grep -q '^prepare_registry_cache_for_startup()' "$PROJECT_ROOT/tools/setup/lib/registry-cache.sh" && \
   grep -q 'REGISTRY_DATA_DIR' "$PROJECT_ROOT/tools/setup/lib/registry-cache.sh" && \
   grep -q '^load_registry_proxy_credentials()' "$PROJECT_ROOT/tools/setup/lib/registry-cache.sh"; then
    test_pass
else
    test_fail "Expected registry-cache helpers for mirror detection, startup preparation, shared cache path resolution, and Docker Hub proxy auth"
fi

test_case "level 2 uninstall preserves registry cache data and restores daemon config"
if grep -q 'preserve_registry_cache_data' "$PROJECT_ROOT/uninstall.sh" && \
   grep -q 'restore_preserved_registry_cache_data' "$PROJECT_ROOT/uninstall.sh" && \
   grep -q 'restore_docker_config' "$PROJECT_ROOT/uninstall.sh" && \
   grep -q '/tmp/weekendstack-uninstall-backups' "$PROJECT_ROOT/uninstall.sh"; then
    test_pass
else
    test_fail "Expected uninstall.sh to preserve registry cache data, restore Docker mirror state, and survive an unwritable _trash backup directory"
fi

test_suite_end
