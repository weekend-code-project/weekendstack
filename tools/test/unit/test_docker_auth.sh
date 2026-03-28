#!/bin/bash
# Unit tests for Docker auth helpers

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"
source "$PROJECT_ROOT/tools/setup/lib/docker-auth.sh"

test_suite_start "Docker Auth Helpers"

test_case "has_docker_hub_auth detects Docker Hub credentials in config.json"
tmp_home="$(mktemp -d)"
mkdir -p "$tmp_home/.docker"
cat > "$tmp_home/.docker/config.json" <<'EOF'
{"auths":{"https://index.docker.io/v1/":{"auth":"ZGVtbzpkZW1v"}}}
EOF

if HOME="$tmp_home" has_docker_hub_auth; then
    test_pass
else
    test_fail "Expected Docker Hub auth to be detected from config.json"
fi

rm -rf "$tmp_home"

test_case "has_docker_hub_auth returns false when config.json is missing"
tmp_home="$(mktemp -d)"

if ! HOME="$tmp_home" has_docker_hub_auth; then
    test_pass
else
    test_fail "Expected missing config.json to report no Docker Hub auth"
fi

rm -rf "$tmp_home"

test_suite_end
