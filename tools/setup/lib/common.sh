#!/bin/bash
# Common library functions for WeekendStack setup
# Provides logging, prompts, validation helpers

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Logging functions — ALL write to stderr so they don't corrupt $() captures
log_info() {
    echo -e "  ${BLUE}ℹ${NC} $*" >&2
}

log_success() {
    echo -e "  ${GREEN}✓${NC} $*" >&2
}

log_warn() {
    echo -e "  ${YELLOW}⚠${NC} $*" >&2
}

log_error() {
    echo -e "  ${RED}✗${NC} $*" >&2
}

log_header() {
    echo "" >&2
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "${BOLD}${CYAN}  $*${NC}" >&2
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
}

log_step() {
    echo -e "  ${CYAN}→${NC} $*" >&2
}

clear_screen() {
    if [[ -e /dev/tty ]] && (: >/dev/tty) 2>/dev/null; then
        clear >/dev/tty 2>/dev/null || true
    elif [[ -t 1 ]]; then
        clear 2>/dev/null || true
    fi
}

screen_title() {
    local title="$1"
    local subtitle="${2:-}"
    local clear_first="${3:-true}"

    if [[ "$clear_first" == "true" ]]; then
        clear_screen
    fi

    log_header "$title"

    if [[ -n "$subtitle" ]]; then
        echo "  $subtitle" >&2
        echo "" >&2
    fi
}

screen_section() {
    local title="$1"
    local body="${2:-}"

    echo -e "${BOLD}$title${NC}" >&2
    if [[ -n "$body" ]]; then
        echo "  $body" >&2
    fi
    echo "" >&2
}

# Progress indicator
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# User prompt functions
non_interactive_mode_enabled() {
    [[ "${NON_INTERACTIVE_MODE:-false}" == "true" ]]
}

mktemp_in_dir() {
    local target_dir="$1"
    local prefix="${2:-weekendstack}"

    mkdir -p "$target_dir"
    mktemp "${target_dir}/.${prefix}.XXXXXX"
}

replace_file_safely() {
    local source_file="$1"
    local target_file="$2"

    if mv "$source_file" "$target_file" 2>/dev/null; then
        return 0
    fi

    cat "$source_file" > "$target_file"
    rm -f "$source_file"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    if non_interactive_mode_enabled || [[ ! -e /dev/tty ]] || ! (: </dev/tty) 2>/dev/null; then
        response="$default"
    else
        read -r -p "$(echo -e ${CYAN}?${NC}) $prompt" response </dev/tty
    fi
    response=${response,,} # to lowercase
    
    if [[ -z "$response" ]]; then
        response="$default"
    fi
    
    [[ "$response" == "y" || "$response" == "yes" ]]
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local response
    
    if [[ -n "$default" ]]; then
        prompt="$prompt [$default]: "
    else
        prompt="$prompt: "
    fi
    
    if non_interactive_mode_enabled || [[ ! -e /dev/tty ]] || ! (: </dev/tty) 2>/dev/null; then
        response="$default"
    else
        read -r -p "$(echo -e ${CYAN}?${NC}) $prompt" response </dev/tty
    fi
    
    if [[ -z "$response" && -n "$default" ]]; then
        echo "$default"
    else
        echo "$response"
    fi
}

prompt_password() {
    local prompt="$1"
    local allow_empty="${2:-no}"  # pass "yes" to allow blank (triggers auto-generate)
    local password
    local confirm
    
    while true; do
        read -r -s -p "$(echo -e ${CYAN}?${NC}) $prompt: " password </dev/tty
        echo "" >&2  # advance terminal line; >&2 so it's not captured by $(...)
        
        if [[ -z "$password" ]]; then
            if [[ "$allow_empty" == "yes" ]]; then
                return 0
            fi
            log_error "Password cannot be empty"
            continue
        fi
        
        read -r -s -p "$(echo -e ${CYAN}?${NC}) Confirm password: " confirm </dev/tty
        echo "" >&2  # advance terminal line
        
        if [[ "$password" == "$confirm" ]]; then
            echo "$password"
            return 0
        else
            log_error "Passwords do not match. Please try again."
        fi
    done
}

prompt_select() {
    local prompt="$1"
    shift
    local options=("$@")
    local choice
    
    echo -e "${CYAN}?${NC} $prompt" >&2
    for i in "${!options[@]}"; do
        echo "  $((i+1))) ${options[$i]}" >&2
    done
    
    while true; do
        if non_interactive_mode_enabled || [[ ! -e /dev/tty ]] || ! (: </dev/tty) 2>/dev/null; then
            choice="1"
        else
            read -r -p "$(echo -e ${CYAN}→${NC}) Select [1-${#options[@]}]: " choice </dev/tty
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
            echo "$((choice-1))"
            return 0
        else
            log_error "Invalid selection. Please enter a number between 1 and ${#options[@]}"
        fi
    done
}

prompt_menu_choice() {
    local prompt="$1"
    local default="${2:-}"
    shift 2
    local options=("$@")
    local choice
    local default_prompt

    if [[ ${#options[@]} -eq 0 ]]; then
        log_error "prompt_menu_choice requires at least one option"
        return 1
    fi

    echo -e "${CYAN}?${NC} $prompt" >&2
    for i in "${!options[@]}"; do
        echo "  $((i + 1))) ${options[$i]}" >&2
    done

    if [[ -n "$default" ]]; then
        default_prompt="[$default]"
    else
        default_prompt="[1-${#options[@]}]"
    fi

    while true; do
        if non_interactive_mode_enabled; then
            choice="$default"
        elif [[ -e /dev/tty ]] && (: </dev/tty) 2>/dev/null; then
            read -r -p "$(echo -e ${CYAN}→${NC}) Select ${default_prompt}: " choice </dev/tty
        else
            choice="$default"
        fi

        if [[ -z "$choice" && -n "$default" ]]; then
            choice="$default"
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
            echo "$choice"
            return 0
        fi

        log_error "Invalid selection. Please enter a number between 1 and ${#options[@]}"
    done
}

prompt_number_choice() {
    local prompt="$1"
    local default="${2:-}"
    local min="${3:-1}"
    local max="$4"
    local choice
    local default_prompt

    if [[ -z "$max" ]]; then
        log_error "prompt_number_choice requires a max value"
        return 1
    fi

    if [[ -n "$default" ]]; then
        default_prompt="[$default]"
    else
        default_prompt="[$min-$max]"
    fi

    while true; do
        if non_interactive_mode_enabled; then
            choice="$default"
        elif [[ -e /dev/tty ]] && (: </dev/tty) 2>/dev/null; then
            read -r -p "$(echo -e ${CYAN}→${NC}) $prompt ${default_prompt}: " choice </dev/tty
        else
            choice="$default"
        fi

        if [[ -z "$choice" && -n "$default" ]]; then
            choice="$default"
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= min && choice <= max)); then
            echo "$choice"
            return 0
        fi

        log_error "Invalid selection. Please enter a number between $min and $max"
    done
}

pause_for_enter() {
    local prompt="${1:-Press Enter to continue...}"

    if non_interactive_mode_enabled; then
        return 0
    fi

    if [[ -e /dev/tty ]] && (: </dev/tty) 2>/dev/null; then
        read -r -p "  $prompt" _pause </dev/tty
    fi
}

prompt_multiselect() {
    local prompt="$1"
    shift
    local options=("$@")
    local selected=()
    local i
    
    # Initialize all as unselected
    for i in "${!options[@]}"; do
        selected[$i]=0
    done
    
    echo -e "${CYAN}?${NC} $prompt" >&2
    echo "  (Space to toggle, Enter when done, 'a' for all, 'n' for none)" >&2
    
    local current=0
    while true; do
        # Display options
        for i in "${!options[@]}"; do
            if [[ $i -eq $current ]]; then
                echo -ne "  ${CYAN}>${NC} " >&2
            else
                echo -ne "    " >&2
            fi
            
            if [[ ${selected[$i]} -eq 1 ]]; then
                echo -e "[${GREEN}✓${NC}] ${options[$i]}" >&2
            else
                echo -e "[ ] ${options[$i]}" >&2
            fi
        done
        
        # Read input
        read -rsn1 key </dev/tty
        
        case "$key" in
            $'\x20') # Space - toggle
                if [[ ${selected[$current]} -eq 1 ]]; then
                    selected[$current]=0
                else
                    selected[$current]=1
                fi
                ;;
            $'\x1b') # Escape sequence
                read -rsn2 key </dev/tty
                case "$key" in
                    '[A') # Up arrow
                        ((current > 0)) && ((current--))
                        ;;
                    '[B') # Down arrow
                        ((current < ${#options[@]}-1)) && ((current++))
                        ;;
                esac
                ;;
            'a'|'A') # Select all
                for i in "${!options[@]}"; do
                    selected[$i]=1
                done
                ;;
            'n'|'N') # Select none
                for i in "${!options[@]}"; do
                    selected[$i]=0
                done
                ;;
            '') # Enter - done
                # Move cursor down past the options
                for i in "${!options[@]}"; do
                    echo "" >&2
                done
                break
                ;;
        esac
        
        # Move cursor back up
        for i in "${!options[@]}"; do
            echo -ne "\033[1A\033[2K" >&2
        done
    done
    
    # Return selected indices
    local result=()
    for i in "${!selected[@]}"; do
        if [[ ${selected[$i]} -eq 1 ]]; then
            result+=("$i")
        fi
    done
    
    echo "${result[@]}"
}

# Validation functions
validate_ip() {
    local ip="$1"
    local regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    
    if [[ ! $ip =~ $regex ]]; then
        return 1
    fi
    
    local IFS='.'
    local -a octets=($ip)
    
    for octet in "${octets[@]}"; do
        if ((octet > 255)); then
            return 1
        fi
    done
    
    return 0
}

validate_domain() {
    local domain="$1"
    local regex="^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$"
    
    [[ $domain =~ $regex ]]
}

validate_email() {
    local email="$1"
    local regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    
    [[ $email =~ $regex ]]
}

shared_admin_username_rules_text() {
    cat <<'EOF'
Use 3-32 characters, start with a lowercase letter, and use only lowercase letters, numbers, hyphens, or underscores.
If Gitea is enabled, avoid reserved names like admin.
EOF
}

validate_shared_admin_username() {
    local username="$1"
    local gitea_enabled="${2:-false}"
    local normalized_username

    SHARED_ADMIN_USERNAME_ERROR=""

    if [[ -z "$username" ]]; then
        SHARED_ADMIN_USERNAME_ERROR="cannot be empty."
        return 1
    fi

    if [[ ! "$username" =~ ^[a-z][a-z0-9_-]{2,31}$ ]]; then
        SHARED_ADMIN_USERNAME_ERROR="must be 3-32 characters, start with a lowercase letter, and only use lowercase letters, numbers, hyphens, or underscores."
        return 1
    fi

    if [[ "$gitea_enabled" == "true" || "$gitea_enabled" == "yes" ]]; then
        normalized_username=$(printf '%s' "$username" | tr '[:upper:]' '[:lower:]')
        case "$normalized_username" in
            admin|administrator)
                SHARED_ADMIN_USERNAME_ERROR="cannot be '${username}' when Gitea is enabled because Gitea reserves that username."
                return 1
                ;;
        esac
    fi

    return 0
}

shared_admin_password_rules_text() {
    cat <<'EOF'
Use at least 12 characters with an uppercase letter, a lowercase letter, and a number.
Only use letters, numbers, and these symbols: . _ - @ % + = : !
Avoid spaces and characters that break .env parsing such as #, quotes, backslashes, backticks, or $.
Leave it blank to auto-generate a stronger password instead.
EOF
}

validate_shared_admin_password() {
    local password="$1"
    local allow_empty="${2:-false}"
    local normalized
    local unique_count

    SHARED_ADMIN_PASSWORD_ERROR=""

    if [[ -z "$password" ]]; then
        if [[ "$allow_empty" == "true" || "$allow_empty" == "yes" ]]; then
            return 0
        fi
        SHARED_ADMIN_PASSWORD_ERROR="cannot be empty."
        return 1
    fi

    if [[ ${#password} -lt 12 ]]; then
        SHARED_ADMIN_PASSWORD_ERROR="must be at least 12 characters."
        return 1
    fi

    if [[ "$password" =~ [[:space:]] ]]; then
        SHARED_ADMIN_PASSWORD_ERROR="cannot contain spaces."
        return 1
    fi

    if [[ ! "$password" =~ ^[A-Za-z0-9._@%+=:!-]+$ ]]; then
        SHARED_ADMIN_PASSWORD_ERROR="contains unsupported characters. Use letters, numbers, and only these symbols: . _ - @ % + = : !"
        return 1
    fi

    if [[ ! "$password" =~ [a-z] ]]; then
        SHARED_ADMIN_PASSWORD_ERROR="must include at least one lowercase letter."
        return 1
    fi

    if [[ ! "$password" =~ [A-Z] ]]; then
        SHARED_ADMIN_PASSWORD_ERROR="must include at least one uppercase letter."
        return 1
    fi

    if [[ ! "$password" =~ [0-9] ]]; then
        SHARED_ADMIN_PASSWORD_ERROR="must include at least one number."
        return 1
    fi

    normalized=$(printf '%s' "$password" | tr '[:upper:]' '[:lower:]')
    case "$normalized" in
        password|password123|password1234|admin|admin123|administrator|changeme|welcome|welcome123|test|test123|qwerty123|weekendstack)
            SHARED_ADMIN_PASSWORD_ERROR="is too weak. Choose a less predictable password or leave it blank to auto-generate one."
            return 1
            ;;
    esac

    unique_count=$(printf '%s' "$password" | fold -w1 | sort -u | wc -l | tr -d ' ')
    if [[ -n "$unique_count" ]] && (( unique_count < 6 )); then
        SHARED_ADMIN_PASSWORD_ERROR="needs more character variety to avoid weak repeated patterns."
        return 1
    fi

    return 0
}

random_chars() {
    local charset="$1"
    local length="$2"
    LC_ALL=C tr -dc "$charset" < /dev/urandom | head -c "$length"
}

generate_shared_admin_password() {
    local candidate
    local attempts=0

    while (( attempts < 20 )); do
        candidate="$(
            printf '%s%s%s%s' \
                "$(random_chars 'A-Z' 1)" \
                "$(random_chars 'a-z' 1)" \
                "$(random_chars '0-9' 1)" \
                "$(random_chars 'A-Za-z0-9._@%+=:!-' 21)"
        )"

        if validate_shared_admin_password "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi

        attempts=$((attempts + 1))
    done

    log_error "Failed to generate a valid shared admin password"
    return 1
}

validate_path() {
    local path="$1"
    local must_exist="${2:-false}"
    
    if [[ "$must_exist" == "true" && ! -e "$path" ]]; then
        return 1
    fi
    
    if [[ ! "$path" =~ ^/ && ! "$path" =~ ^\./ ]]; then
        return 1
    fi
    
    return 0
}

validate_port() {
    local port="$1"
    
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    if ((port < 1 || port > 65535)); then
        return 1
    fi
    
    return 0
}

# File operations
backup_file() {
    local file="$1"
    local timestamp root_dir backup_dir backup_path
    timestamp=$(date +%Y%m%d-%H%M%S)
    root_dir="${SCRIPT_DIR:-${PROJECT_ROOT:-$(pwd)}}"
    backup_dir="${root_dir}/_trash"
    
    if [[ ! -f "$file" ]]; then
        return 0
    fi
    
    mkdir -p "$backup_dir"
    backup_path="${backup_dir}/$(basename "$file").backup.$timestamp"

    if cat "$file" > "$backup_path"; then
        log_success "Created backup: $backup_path"
    else
        log_warn "Failed to create backup: $backup_path"
        return 1
    fi
}

# System detection
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

detect_init_system() {
    if [[ -f /run/systemd/system ]]; then
        echo "systemd"
    elif [[ -f /sbin/openrc ]]; then
        echo "openrc"
    else
        echo "unknown"
    fi
}

check_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1
}

check_port_available() {
    local port="$1"
    ! netstat -tuln 2>/dev/null | grep -q ":$port " && ! ss -tuln 2>/dev/null | grep -q ":$port "
}

get_env_value() {
    local var_name="$1"
    local env_file="${2:-${SCRIPT_DIR}/.env}"
    local raw_line

    [[ -f "$env_file" ]] || return 1

    raw_line=$(grep -m1 "^${var_name}=" "$env_file" 2>/dev/null) || return 1
    raw_line="${raw_line#*=}"
    raw_line=$(printf '%s' "$raw_line" | sed 's/[[:space:]]#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')

    if [[ ${#raw_line} -ge 2 ]]; then
        if [[ "${raw_line:0:1}" == '"' && "${raw_line: -1}" == '"' ]]; then
            raw_line="${raw_line:1:${#raw_line}-2}"
        elif [[ "${raw_line:0:1}" == "'" && "${raw_line: -1}" == "'" ]]; then
            raw_line="${raw_line:1:${#raw_line}-2}"
        fi
    fi

    printf '%s\n' "$raw_line"
}

normalize_access_mode() {
    local raw_mode="${1:-}"
    local normalized
    normalized=$(printf '%s' "$raw_mode" | tr '[:upper:]' '[:lower:]')

    case "$normalized" in
        tunnel|cloudflare|both)
            echo "tunnel"
            ;;
        local|pihole)
            echo "local"
            ;;
        ip|"")
            echo "ip"
            ;;
        *)
            echo "ip"
            ;;
    esac
}

has_tunnel_access_mode() {
    local raw_mode="${1:-}"
    local normalized
    normalized=$(printf '%s' "$raw_mode" | tr '[:upper:]' '[:lower:]')

    case "$normalized" in
        tunnel|cloudflare|both)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

has_local_domain_access_mode() {
    local raw_mode="${1:-}"
    local normalized
    normalized=$(printf '%s' "$raw_mode" | tr '[:upper:]' '[:lower:]')

    case "$normalized" in
        local|pihole|both)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Progress tracking
progress_bar() {
    local current="$1"
    local total="$2"
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    
    printf "\r["
    printf "%${filled}s" '' | tr ' ' '='
    printf "%${empty}s" '' | tr ' ' ' '
    printf "] %3d%% (%d/%d)" "$percentage" "$current" "$total"
}

# Error handling
set_error_trap() {
    set -eE
    trap 'error_handler $? $LINENO' ERR
}

error_handler() {
    local exit_code=$1
    local line_number=$2
    log_error "Error occurred in script at line $line_number (exit code: $exit_code)"
}

# Cleanup handler
cleanup_handlers=()

add_cleanup_handler() {
    cleanup_handlers+=("$1")
}

run_cleanup_handlers() {
    for handler in "${cleanup_handlers[@]:-}"; do
        eval "$handler" || true
    done
}

trap run_cleanup_handlers EXIT

# Export functions
export -f log_info log_success log_warn log_error log_header log_step
export -f clear_screen screen_title screen_section
export -f non_interactive_mode_enabled prompt_yes_no prompt_input prompt_password prompt_select prompt_multiselect prompt_menu_choice prompt_number_choice pause_for_enter
export -f validate_ip validate_domain validate_email validate_path validate_port
export -f backup_file detect_os detect_init_system check_command check_port_available get_env_value
export -f normalize_access_mode has_tunnel_access_mode has_local_domain_access_mode
export -f mktemp_in_dir replace_file_safely
export -f progress_bar set_error_trap error_handler
export -f add_cleanup_handler run_cleanup_handlers
