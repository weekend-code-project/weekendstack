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

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

log_header() {
    echo ""
    echo -e "${BOLD}${CYAN}=== $* ===${NC}"
    echo ""
}

log_step() {
    echo -e "${CYAN}→${NC} $*"
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
prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -r -p "$(echo -e ${CYAN}?${NC}) $prompt" response
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
    
    read -r -p "$(echo -e ${CYAN}?${NC}) $prompt" response
    
    if [[ -z "$response" && -n "$default" ]]; then
        echo "$default"
    else
        echo "$response"
    fi
}

prompt_password() {
    local prompt="$1"
    local password
    local confirm
    
    while true; do
        read -r -s -p "$(echo -e ${CYAN}?${NC}) $prompt: " password
        echo ""
        
        if [[ -z "$password" ]]; then
            log_error "Password cannot be empty"
            continue
        fi
        
        read -r -s -p "$(echo -e ${CYAN}?${NC}) Confirm password: " confirm
        echo ""
        
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
    
    echo -e "${CYAN}?${NC} $prompt"
    for i in "${!options[@]}"; do
        echo "  $((i+1))) ${options[$i]}"
    done
    
    while true; do
        read -r -p "$(echo -e ${CYAN}→${NC}) Select [1-${#options[@]}]: " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
            echo "$((choice-1))"
            return 0
        else
            log_error "Invalid selection. Please enter a number between 1 and ${#options[@]}"
        fi
    done
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
    
    echo -e "${CYAN}?${NC} $prompt"
    echo "  (Space to toggle, Enter when done, 'a' for all, 'n' for none)"
    
    local current=0
    while true; do
        # Display options
        for i in "${!options[@]}"; do
            if [[ $i -eq $current ]]; then
                echo -ne "  ${CYAN}>${NC} "
            else
                echo -ne "    "
            fi
            
            if [[ ${selected[$i]} -eq 1 ]]; then
                echo -e "[${GREEN}✓${NC}] ${options[$i]}"
            else
                echo -e "[ ] ${options[$i]}"
            fi
        done
        
        # Read input
        read -rsn1 key
        
        case "$key" in
            $'\x20') # Space - toggle
                if [[ ${selected[$current]} -eq 1 ]]; then
                    selected[$current]=0
                else
                    selected[$current]=1
                fi
                ;;
            $'\x1b') # Escape sequence
                read -rsn2 key
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
                    echo ""
                done
                break
                ;;
        esac
        
        # Move cursor back up
        for i in "${!options[@]}"; do
            echo -ne "\033[1A\033[2K"
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
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_dir="${SCRIPT_DIR}/../_trash"
    
    if [[ ! -f "$file" ]]; then
        return 0
    fi
    
    mkdir -p "$backup_dir"
    local backup_path="${backup_dir}/$(basename "$file").backup.$timestamp"
    
    cp "$file" "$backup_path"
    log_success "Created backup: $backup_path"
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
    for handler in "${cleanup_handlers[@]}"; do
        eval "$handler" || true
    done
}

trap run_cleanup_handlers EXIT

# Export functions
export -f log_info log_success log_warn log_error log_header log_step
export -f prompt_yes_no prompt_input prompt_password prompt_select prompt_multiselect
export -f validate_ip validate_domain validate_email validate_path validate_port
export -f backup_file detect_os detect_init_system check_command check_port_available
export -f progress_bar set_error_trap error_handler
export -f add_cleanup_handler run_cleanup_handlers
