#!/bin/bash
# Canonical WeekendStack service catalog helpers

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

service_catalog_file() {
    local lib_dir repo_root
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    repo_root="${SCRIPT_DIR:-$(cd "$lib_dir/../../.." && pwd)}"
    printf '%s\n' "$repo_root/tools/env/mappings/service-metadata.json"
}

catalog_requirements_ok() {
    command -v jq >/dev/null 2>&1 && [[ -f "$(service_catalog_file)" ]]
}

catalog_service_ids() {
    jq -r 'keys[] | select(startswith("_") | not)' "$(service_catalog_file)"
}

catalog_profile_ids() {
    local mode="${1:-all}"
    case "$mode" in
        selectable)
            jq -r '._profiles | to_entries[] | select(.value.user_selectable == true) | .key' "$(service_catalog_file)"
            ;;
        *)
            jq -r '._profiles | keys[]' "$(service_catalog_file)"
            ;;
    esac
}

catalog_profile_field() {
    local profile="$1"
    local field="$2"
    local default_value="${3:-}"
    jq -r --arg profile "$profile" --arg field "$field" --arg default_value "$default_value" \
        '._profiles[$profile][$field] // $default_value' "$(service_catalog_file)"
}

catalog_service_exists() {
    local service="$1"
    jq -e --arg service "$service" 'has($service)' "$(service_catalog_file)" >/dev/null 2>&1
}

catalog_service_field() {
    local service="$1"
    local field="$2"
    local default_value="${3:-}"
    jq -r --arg service "$service" --arg field "$field" --arg default_value "$default_value" \
        '.[$service][$field] // $default_value' "$(service_catalog_file)"
}

catalog_service_activation_profiles() {
    local service="$1"
    jq -r --arg service "$service" \
        '
        if ((.[$service].activation_profiles // []) | length) > 0 then
          .[$service].activation_profiles[]
        elif (.[$service].profile // "") != "" then
          .[$service].profile
        else
          empty
        end
        ' \
        "$(service_catalog_file)"
}

catalog_service_support_containers() {
    local service="$1"
    jq -r --arg service "$service" '(.[$service].support_containers // [])[]' "$(service_catalog_file)"
}

catalog_service_required_directories() {
    local service="$1"
    jq -r --arg service "$service" '(.[$service].required_directories // [])[]' "$(service_catalog_file)"
}

catalog_services_for_activation_profiles() {
    local csv="${1:-}"
    jq -r --arg csv "$csv" '
        ($csv | split(",") | map(select(length > 0))) as $profiles
        | to_entries[]
        | select(.key | startswith("_") | not)
        | (
            if ((.value.activation_profiles // []) | length) > 0 then
              .value.activation_profiles
            elif (.value.profile // "") != "" then
              [.value.profile]
            else
              []
            end
          ) as $activation_profiles
        | select(any($activation_profiles[]; . as $profile | $profiles | index($profile)))
        | .key
    ' "$(service_catalog_file)"
}

catalog_selectable_service_ids() {
    local group_profile="${1:-}"
    if [[ -n "$group_profile" ]]; then
        jq -r --arg group_profile "$group_profile" '
            to_entries[]
            | select(.key | startswith("_") | not)
            | select(.value.selectable_service == true and .value.profile == $group_profile)
            | .key
        ' "$(service_catalog_file)"
    else
        jq -r '
            to_entries[]
            | select(.key | startswith("_") | not)
            | select(.value.selectable_service == true)
            | .key
        ' "$(service_catalog_file)"
    fi
}

catalog_expand_base_profiles() {
    local profiles_csv="${1:-}"
    local -a input_profiles expanded_profiles visible_profiles
    local profile

    IFS=',' read -r -a input_profiles <<< "$profiles_csv"
    while IFS= read -r profile; do
        [[ -n "$profile" ]] && visible_profiles+=("$profile")
    done < <(
        jq -r '
            ._profiles
            | to_entries[]
            | select(.value.user_selectable == true and .key != "all")
            | .key
        ' "$(service_catalog_file)"
    )

    for profile in "${input_profiles[@]}"; do
        [[ -z "$profile" ]] && continue
        if [[ "$profile" == "all" ]]; then
            expanded_profiles+=("${visible_profiles[@]}")
        else
            expanded_profiles+=("$profile")
        fi
    done

    if [[ ! " ${expanded_profiles[*]} " =~ " core " ]]; then
        expanded_profiles=("core" "${expanded_profiles[@]}")
    fi

    printf '%s\n' "${expanded_profiles[@]}" | awk 'NF && !seen[$0]++'
}

catalog_build_effective_profiles() {
    local access_mode="$1"
    local local_dns_mode="$2"
    local ai_runtime="$3"
    local base_profiles_csv="$4"
    local selected_services_csv="${5:-}"

    local -a effective_profiles=()
    local -a base_profiles=()
    local -a selected_services=()
    local service

    while IFS= read -r profile; do
        [[ -n "$profile" ]] && base_profiles+=("$profile")
    done < <(catalog_expand_base_profiles "$base_profiles_csv")
    effective_profiles+=("${base_profiles[@]}")

    IFS=',' read -r -a selected_services <<< "$selected_services_csv"
    for service in "${selected_services[@]}"; do
        [[ -z "$service" ]] && continue
        while IFS= read -r profile; do
            [[ -n "$profile" ]] && effective_profiles+=("$profile")
        done < <(catalog_service_activation_profiles "$service")
    done

    if [[ " ${base_profiles[*]} " =~ " ai " ]]; then
        if [[ "$ai_runtime" == "gpu" ]]; then
            effective_profiles+=("gpu")
        else
            effective_profiles+=("ollama-cpu")
        fi
    fi

    case "$access_mode" in
        tunnel)
            effective_profiles+=("networking")
            ;;
        local)
            effective_profiles+=("networking")
            ;;
    esac

    if [[ "$local_dns_mode" == "pihole" ]]; then
        effective_profiles+=("pihole")
    fi

    printf '%s\n' "${effective_profiles[@]}" | awk 'NF && !seen[$0]++'
}

catalog_sum_resources() {
    local effective_profiles_csv="$1"
    local selected_services_csv="${2:-}"
    local total_memory=0
    local total_disk=0
    local profile
    local service

    IFS=',' read -r -a effective_profiles <<< "$effective_profiles_csv"
    IFS=',' read -r -a selected_services <<< "$selected_services_csv"

    for profile in "${effective_profiles[@]}"; do
        [[ -z "$profile" ]] && continue
        total_memory=$((total_memory + $(catalog_profile_field "$profile" "memory_gb" "0")))
        total_disk=$((total_disk + $(catalog_profile_field "$profile" "disk_gb" "0")))
    done

    for service in "${selected_services[@]}"; do
        [[ -z "$service" ]] && continue
        total_memory=$((total_memory + $(catalog_service_field "$service" "resource_memory_gb" "0")))
        total_disk=$((total_disk + $(catalog_service_field "$service" "resource_disk_gb" "0")))
    done

    printf '%s %s\n' "$total_memory" "$total_disk"
}

catalog_service_url() {
    local service="$1"
    local access_mode="$2"
    local base_domain="$3"
    local lab_domain="$4"
    local host_ip="$5"
    local subdomain port

    subdomain="$(catalog_service_field "$service" "subdomain" "$service")"
    port="$(catalog_service_field "$service" "ip_port" "")"

    case "$access_mode" in
        tunnel)
            [[ -n "$base_domain" ]] && printf 'https://%s.%s\n' "$subdomain" "$base_domain"
            ;;
        local)
            [[ -n "$lab_domain" ]] && printf 'https://%s.%s\n' "$subdomain" "$lab_domain"
            ;;
        *)
            [[ -n "$host_ip" && -n "$port" ]] && printf 'http://%s:%s\n' "$host_ip" "$port"
            ;;
    esac
}

catalog_service_followup_url() {
    local service="$1"
    local access_mode="$2"
    local base_domain="$3"
    local lab_domain="$4"
    local host_ip="$5"
    local first_run_path url

    url="$(catalog_service_url "$service" "$access_mode" "$base_domain" "$lab_domain" "$host_ip")"
    first_run_path="$(catalog_service_field "$service" "first_run_path" "")"

    if [[ -n "$url" && -n "$first_run_path" ]]; then
        printf '%s%s\n' "$url" "$first_run_path"
    else
        printf '%s\n' "$url"
    fi
}

catalog_manual_followups_json() {
    local services_csv="$1"
    local access_mode="$2"
    local base_domain="$3"
    local lab_domain="$4"
    local host_ip="$5"
    local first=true
    local service mode note url
    local -a services=()

    IFS=',' read -r -a services <<< "$services_csv"
    printf '['
    for service in "${services[@]}"; do
        [[ -z "$service" ]] && continue
        mode="$(catalog_service_field "$service" "first_run_mode" "manual")"
        if [[ "$mode" == "none" ]]; then
            continue
        fi
        note="$(catalog_service_field "$service" "first_run_note" "")"
        url="$(catalog_service_followup_url "$service" "$access_mode" "$base_domain" "$lab_domain" "$host_ip")"

        if [[ "$first" != true ]]; then
            printf ','
        fi
        jq -nc \
            --arg service "$service" \
            --arg display_name "$(catalog_service_field "$service" "display_name" "$service")" \
            --arg mode "$mode" \
            --arg url "$url" \
            --arg note "$note" \
            '{service:$service, display_name:$display_name, mode:$mode, url:$url, note:$note}'
        first=false
    done
    printf ']'
}

export -f service_catalog_file
export -f catalog_requirements_ok catalog_service_ids catalog_profile_ids
export -f catalog_profile_field catalog_service_exists catalog_service_field
export -f catalog_service_activation_profiles catalog_service_support_containers
export -f catalog_service_required_directories catalog_services_for_activation_profiles
export -f catalog_selectable_service_ids catalog_expand_base_profiles
export -f catalog_build_effective_profiles catalog_sum_resources
export -f catalog_service_url catalog_service_followup_url catalog_manual_followups_json
