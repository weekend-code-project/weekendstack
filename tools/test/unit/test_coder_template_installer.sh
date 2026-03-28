#!/bin/bash
# Unit tests for shared Coder template installer helpers

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"
source "$PROJECT_ROOT/tools/setup/lib/coder-template-installer.sh"

test_suite_start "Coder Template Installer"

test_case "Template discovery only returns deployable templates"
mkdir -p "$TEST_DIR/templates/base" "$TEST_DIR/templates/node" "$TEST_DIR/templates/readme-only"
touch "$TEST_DIR/templates/base/main.tf" "$TEST_DIR/templates/node/main.tf" "$TEST_DIR/templates/readme-only/README.md"

mapfile -t templates < <(list_coder_template_names "$TEST_DIR/templates")

if [[ "${templates[*]}" == "base node" ]]; then
    test_pass
else
    test_fail "Expected 'base node', got '${templates[*]}'"
fi

test_case "Token validation accepts a valid Coder response"
curl() {
    cat <<'EOF'
{"username":"jesse","email":"jessefreeman@gmail.com"}
EOF
}

if user_info=$(validate_coder_session_token "valid-token" "http://coder.local"); then
    username=$(extract_coder_username "$user_info")
    if [[ "$username" == "jesse" ]]; then
        test_pass
    else
        test_fail "Expected username 'jesse', got '$username'"
    fi
else
    test_fail "Expected token validation to succeed"
fi
unset -f curl

test_case "Token validation rejects an invalid Coder response"
curl() {
    return 22
}

if ! validate_coder_session_token "bad-token" "http://coder.local" >/dev/null 2>&1; then
    test_pass
else
    test_fail "Expected invalid token to fail validation"
fi
unset -f curl

test_case "Session token storage updates an existing .env entry"
create_temp_env
cat > "$TEST_ENV" <<'EOF'
HOST_IP=192.168.1.10
CODER_SESSION_TOKEN=old-token
EOF

store_coder_session_token "new-token" "$TEST_ENV"

if grep -q '^CODER_SESSION_TOKEN=new-token$' "$TEST_ENV"; then
    test_pass
else
    test_fail "Expected updated token in $TEST_ENV"
fi

test_case "Batch deployment passes token and URL to each template push"
mkdir -p "$TEST_DIR/batch/alpha" "$TEST_DIR/batch/bravo"
touch "$TEST_DIR/batch/alpha/main.tf" "$TEST_DIR/batch/bravo/main.tf"

cat > "$TEST_DIR/push-template.sh" <<EOF
#!/bin/bash
echo "\$1|\$CODER_SESSION_TOKEN|\$CODER_ACCESS_URL" >> "$TEST_DIR/push.log"
if [[ "\$1" == "bravo" ]]; then
    exit 1
fi
EOF
chmod +x "$TEST_DIR/push-template.sh"

if deploy_coder_templates_batch "$TEST_DIR/batch" "$TEST_DIR/push-template.sh" "session-123" "http://coder.local" >/dev/null 2>&1; then
    deploy_status=0
else
    deploy_status=$?
fi

if [[ $deploy_status -ne 0 ]] && \
   [[ $CODER_TEMPLATE_BATCH_SUCCESS_COUNT -eq 1 ]] && \
   [[ $CODER_TEMPLATE_BATCH_FAILURE_COUNT -eq 1 ]] && \
   grep -q '^alpha|session-123|http://coder.local$' "$TEST_DIR/push.log" && \
   grep -q '^bravo|session-123|http://coder.local$' "$TEST_DIR/push.log"; then
    test_pass
else
    test_fail "Unexpected deployment results (status=$deploy_status success=$CODER_TEMPLATE_BATCH_SUCCESS_COUNT fail=$CODER_TEMPLATE_BATCH_FAILURE_COUNT)"
fi

test_suite_end
