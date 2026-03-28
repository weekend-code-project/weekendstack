#!/bin/bash
# Unit tests for env assembly behavior

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Env Assembly"

test_case "assemble-env does not invoke docker while generating headers"
create_temp_env

mkdir -p "$TEST_DIR/bin"
DOCKER_LOG="$TEST_DIR/docker.log"
export DOCKER_LOG

cat > "$TEST_DIR/bin/docker" <<'EOF'
#!/bin/sh
echo "docker invoked" >> "${DOCKER_LOG:?}"
exit 99
EOF
chmod +x "$TEST_DIR/bin/docker"

if PATH="$TEST_DIR/bin:$PATH" \
   "$PROJECT_ROOT/tools/env/scripts/assemble-env.sh" --profiles "ai,searxng" --output "$TEST_ENV" >/dev/null 2>&1 && \
   [[ ! -f "$DOCKER_LOG" ]]; then
    test_pass
else
    test_fail "assemble-env unexpectedly invoked docker while assembling env output"
fi

test_suite_end
