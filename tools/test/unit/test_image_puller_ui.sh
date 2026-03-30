#!/bin/bash
# Unit tests for image puller terminal behavior

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

IMAGE_PULLER="$PROJECT_ROOT/tools/setup/lib/image-puller.sh"

test_suite_start "Image Puller UI"

test_case "image pull plan uses safe clear_screen helper"
if grep -q 'clear_screen' "$IMAGE_PULLER" && ! grep -q '^    clear$' "$IMAGE_PULLER"; then
    test_pass
else
    test_fail "Expected image-puller.sh to use clear_screen instead of raw clear"
fi

test_suite_end
