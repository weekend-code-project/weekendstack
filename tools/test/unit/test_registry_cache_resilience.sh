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

test_case "registry cache helper can detect mirror state and prepare startup"
if grep -q '^docker_mirror_configured()' "$PROJECT_ROOT/tools/setup/lib/registry-cache.sh" && \
   grep -q '^prepare_registry_cache_for_startup()' "$PROJECT_ROOT/tools/setup/lib/registry-cache.sh" && \
   grep -q 'REGISTRY_DATA_DIR' "$PROJECT_ROOT/tools/setup/lib/registry-cache.sh"; then
    test_pass
else
    test_fail "Expected registry-cache helpers for mirror detection, startup preparation, and shared cache path resolution"
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
