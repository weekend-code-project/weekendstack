#!/bin/bash
# Regression tests for setup SSH key flows

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Coder SSH Key Setup"

SETUP_FILE="$PROJECT_ROOT/setup.sh"

test_case "GitHub auth flow requests admin:public_key scope"
if grep -q 'github_cli_device_auth_flow "refresh"' "$SETUP_FILE" && \
   grep -q 'github_cli_has_scope "admin:public_key"' "$SETUP_FILE" && \
   grep -q 'gh auth refresh -h github.com -s admin:public_key' "$SETUP_FILE"; then
    test_pass
else
    test_fail "Expected setup.sh to request and refresh the admin:public_key scope for GitHub SSH key uploads"
fi

test_case "setup offers a GitHub and Gitea SSH key picker when Gitea is enabled"
if grep -q 'Add this key to GitHub, Gitea, or both\?' "$SETUP_FILE" && \
   grep -q '^setup_coder_gitea_ssh_key()' "$SETUP_FILE" && \
   grep -q '^setup_coder_git_provider_ssh_keys()' "$SETUP_FILE"; then
    test_pass
else
    test_fail "Expected setup.sh to provide GitHub/Gitea/Both/Skip SSH key setup choices"
fi

test_case "setup still routes the dev flow through the SSH key setup step"
if grep -q 'setup_coder_git_provider_ssh_keys' "$SETUP_FILE"; then
    test_pass
else
    test_fail "Expected dev setup flow to invoke the provider-aware SSH key setup"
fi

test_suite_end
