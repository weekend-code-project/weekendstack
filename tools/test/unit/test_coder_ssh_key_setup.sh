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

test_case "setup offers a multi-select None GitHub Gitea SSH key picker when Gitea is enabled"
if grep -q "Choose where to add this key (space-separated for multiple, e.g. '2 3'):" "$SETUP_FILE" && \
   grep -q 'None    - I will do this later' "$SETUP_FILE" && \
   grep -q 'GitHub  - upload the key to your GitHub account' "$SETUP_FILE" && \
   grep -q 'Gitea   - show where to add the key in Gitea' "$SETUP_FILE" && \
   grep -q 'for provider in \$provider_input; do' "$SETUP_FILE" && \
   grep -q '^setup_coder_gitea_ssh_key()' "$SETUP_FILE" && \
   grep -q '^setup_coder_git_provider_ssh_keys()' "$SETUP_FILE"; then
    test_pass
else
    test_fail "Expected setup.sh to provide a multi-select None/GitHub/Gitea SSH key setup prompt"
fi

test_case "setup still routes the dev flow through the SSH key setup step"
if grep -q 'setup_coder_git_provider_ssh_keys' "$SETUP_FILE"; then
    test_pass
else
    test_fail "Expected dev setup flow to invoke the provider-aware SSH key setup"
fi

test_case "setup exposes an ssh-key-only rerun flag"
if grep -q -- '--ssh-key-only' "$SETUP_FILE" && \
   grep -q '^run_coder_git_ssh_setup_only()' "$SETUP_FILE"; then
    test_pass
else
    test_fail "Expected setup.sh to expose a --ssh-key-only shortcut for rerunning just the Git SSH key step"
fi

test_case "setup explains when the Coder shared SSH key cannot be fetched yet"
if grep -q '^show_coder_git_ssh_key_unavailable()' "$SETUP_FILE" && \
   grep -q "Git SSH Key Setup Pending" "$SETUP_FILE" && \
   grep -q "Coder session token is missing from .env." "$SETUP_FILE" && \
   grep -q "./setup.sh --ssh-key-only" "$SETUP_FILE"; then
    test_pass
else
    test_fail "Expected setup.sh to explain why Git SSH key setup was skipped and how to rerun it"
fi

test_suite_end
