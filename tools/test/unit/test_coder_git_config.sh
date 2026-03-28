#!/bin/bash
# Regression tests for the Coder git-config module

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Coder Git Config"

MODULE_FILE="$PROJECT_ROOT/config/coder/modules/feature/git-config/main.tf"

test_case "Git config only scans the repo's SSH host"
if grep -q 'HTTPS clone detected; skipping SSH host key scan' "$MODULE_FILE" && \
   grep -q 'ssh-keyscan -T 5 -H "\$_ssh_domain"' "$MODULE_FILE" && \
   ! grep -q 'for _gh in github.com gitlab.com bitbucket.org' "$MODULE_FILE"; then
    test_pass
else
    test_fail "git-config module still scans unrelated hosts or lacks timeout handling"
fi

test_suite_end
