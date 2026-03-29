#!/bin/bash
# Unit tests for post-install disk cleanup helpers

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"
source "$PROJECT_ROOT/tools/setup/lib/post-install-cleanup.sh"

test_suite_start "Post-Install Cleanup Helpers"

test_case "human_size_to_bytes converts GB values"
if [[ "$(human_size_to_bytes "58.66GB")" == "58660000000" ]]; then
    test_pass
else
    test_fail "Expected 58.66GB to convert to 58660000000 bytes"
fi

test_case "docker_df_image_field_from_text reads image reclaimable size"
docker_df_sample=$'TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE\nImages          86        49        101.5GB   58.66GB (57%)'
if [[ "$(docker_df_image_field_from_text "$docker_df_sample" "reclaimable")" == "58.66GB" ]]; then
    test_pass
else
    test_fail "Expected docker_df_image_field_from_text to parse the reclaimable column"
fi

test_case "cleanup prompt appears when disk usage is high"
if should_offer_post_install_cleanup "90" "500MB"; then
    test_pass
else
    test_fail "Expected cleanup prompt when root disk usage is 90 percent"
fi

test_case "cleanup prompt appears when reclaimable images are large"
if should_offer_post_install_cleanup "55" "2.5GB"; then
    test_pass
else
    test_fail "Expected cleanup prompt when reclaimable images exceed 1GB"
fi

test_case "cleanup prompt stays hidden when little space can be recovered"
if ! should_offer_post_install_cleanup "55" "500MB"; then
    test_pass
else
    test_fail "Expected cleanup prompt to stay hidden for small reclaim amounts"
fi

test_case "setup runs the cleanup prompt after successful startup"
cleanup_line=$(grep -n 'prompt_for_post_install_cleanup' "$PROJECT_ROOT/setup.sh" | cut -d: -f1 | head -n1)
summary_line=$(grep -n 'display_summary_to_console' "$PROJECT_ROOT/setup.sh" | cut -d: -f1 | head -n1)
if [[ -n "$cleanup_line" && -n "$summary_line" && "$cleanup_line" -lt "$summary_line" ]]; then
    test_pass
else
    test_fail "Expected setup.sh to offer post-install cleanup before showing the final summary"
fi

test_case "cleanup helper always prompts and only changes the default answer"
if grep -q 'default_answer="n"' "$PROJECT_ROOT/tools/setup/lib/post-install-cleanup.sh" && \
   grep -q 'default_answer="y"' "$PROJECT_ROOT/tools/setup/lib/post-install-cleanup.sh" && \
   ! grep -q 'if ! should_offer_post_install_cleanup .*return 0' "$PROJECT_ROOT/tools/setup/lib/post-install-cleanup.sh"; then
    test_pass
else
    test_fail "Expected prompt_for_post_install_cleanup to always show the prompt and only vary the default answer"
fi

test_suite_end
