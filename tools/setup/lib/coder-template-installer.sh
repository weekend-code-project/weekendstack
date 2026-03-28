#!/bin/bash
# Shared helpers for interactive Coder template installation.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CODER_TEMPLATE_BATCH_SUCCESS_COUNT=0
CODER_TEMPLATE_BATCH_FAILURE_COUNT=0
CODER_TEMPLATE_BATCH_FAILURES=()

validate_coder_session_token() {
    local token="${1:-}"
    local coder_url="${2:-${CODER_ACCESS_URL:-http://localhost:7080}}"

    if [[ -z "$token" ]]; then
        return 1
    fi

    curl -sf --max-time 5 \
        -H "Coder-Session-Token: $token" \
        "$coder_url/api/v2/users/me"
}

extract_coder_username() {
    local user_info="$1"

    echo "$user_info" | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4
}

store_coder_session_token() {
    local token="$1"
    local env_file="$2"

    if [[ -z "$token" ]]; then
        log_error "Cannot save an empty Coder session token"
        return 1
    fi

    if grep -q "^CODER_SESSION_TOKEN=" "$env_file" 2>/dev/null; then
        sed -i "s|^CODER_SESSION_TOKEN=.*|CODER_SESSION_TOKEN=$token|" "$env_file"
    else
        echo "CODER_SESSION_TOKEN=$token" >> "$env_file"
    fi

    export CODER_SESSION_TOKEN="$token"
    return 0
}

list_coder_template_names() {
    local templates_dir="$1"

    if [[ ! -d "$templates_dir" ]]; then
        return 0
    fi

    find "$templates_dir" -mindepth 1 -maxdepth 1 -type d | sort | while read -r template_dir; do
        if [[ -f "$template_dir/main.tf" ]]; then
            basename "$template_dir"
        fi
    done
}

show_coder_template_catalog() {
    local templates_dir="$1"
    local shown=0

    while IFS= read -r template_name; do
        [[ -z "$template_name" ]] && continue
        local desc=""
        local readme="$templates_dir/$template_name/README.md"
        if [[ -f "$readme" ]]; then
            desc=$(awk 'NF && $1 !~ /^#/ { print; exit }' "$readme")
        fi
        echo "  ○ ${template_name}${desc:+  - $desc}" >&2
        shown=$((shown + 1))
    done < <(list_coder_template_names "$templates_dir")

    if [[ $shown -eq 0 ]]; then
        log_warn "No deployable templates found in $templates_dir"
    fi
}

deploy_coder_templates_batch() {
    local templates_dir="$1"
    local push_script="$2"
    local token="$3"
    local coder_url="${4:-${CODER_ACCESS_URL:-http://localhost:7080}}"

    CODER_TEMPLATE_BATCH_SUCCESS_COUNT=0
    CODER_TEMPLATE_BATCH_FAILURE_COUNT=0
    CODER_TEMPLATE_BATCH_FAILURES=()

    if [[ ! -x "$push_script" ]]; then
        log_error "Coder template push script is not executable: $push_script"
        return 1
    fi

    local template_names=()
    while IFS= read -r template_name; do
        [[ -n "$template_name" ]] && template_names+=("$template_name")
    done < <(list_coder_template_names "$templates_dir")

    if [[ ${#template_names[@]} -eq 0 ]]; then
        log_warn "No deployable templates found"
        return 0
    fi

    for template_name in "${template_names[@]}"; do
        printf "  ○ %-20s" "$template_name" >&2
        if CODER_SESSION_TOKEN="$token" CODER_ACCESS_URL="$coder_url" \
            "$push_script" "$template_name" >/tmp/weekendstack-template-push.log 2>&1; then
            printf "\r  ● %s\n" "$template_name" >&2
            CODER_TEMPLATE_BATCH_SUCCESS_COUNT=$((CODER_TEMPLATE_BATCH_SUCCESS_COUNT + 1))
        else
            printf "\r  ✗ %s (failed)\n" "$template_name" >&2
            CODER_TEMPLATE_BATCH_FAILURE_COUNT=$((CODER_TEMPLATE_BATCH_FAILURE_COUNT + 1))
            CODER_TEMPLATE_BATCH_FAILURES+=("$template_name")
        fi
    done

    if [[ $CODER_TEMPLATE_BATCH_FAILURE_COUNT -eq 0 ]]; then
        return 0
    fi

    return 1
}

export -f validate_coder_session_token extract_coder_username
export -f store_coder_session_token list_coder_template_names
export -f show_coder_template_catalog deploy_coder_templates_batch
