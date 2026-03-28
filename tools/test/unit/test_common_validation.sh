#!/bin/bash
# Unit tests for common validation helpers

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"
source "$PROJECT_ROOT/tools/setup/lib/common.sh"

test_suite_start "Common Validation Helpers"

test_case "validate_email accepts a normal email address"
if validate_email "admin@example.com"; then
    test_pass
else
    test_fail "Expected admin@example.com to be valid"
fi

test_case "validate_email rejects an obviously invalid email"
if ! validate_email "not-an-email"; then
    test_pass
else
    test_fail "Expected not-an-email to be rejected"
fi

test_suite_end
