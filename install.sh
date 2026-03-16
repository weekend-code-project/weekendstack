#!/usr/bin/env bash
# =============================================================================
# WeekendStack — Remote Bootstrap Installer
#
# Usage (one-liner):
#   curl -fsSL https://raw.githubusercontent.com/weekend-code-project/weekendstack/main/install.sh | sudo bash
#
# Or download and run:
#   curl -fsSL https://raw.githubusercontent.com/weekend-code-project/weekendstack/main/install.sh -o install.sh
#   sudo bash install.sh [FLAGS]
#
# Any flags are forwarded to setup.sh (e.g. --quick, --skip-cloudflare)
# =============================================================================

REPO_URL="https://github.com/weekend-code-project/weekendstack.git"
INSTALL_DIR_NAME="weekendstack"

# ---------------------------------------------------------------------------
# Colour helpers (graceful degradation when terminal has no colour support)
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
    RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
    CYAN=$(tput setaf 6); BOLD=$(tput bold); NC=$(tput sgr0)
else
    RED=""; GREEN=""; YELLOW=""; CYAN=""; BOLD=""; NC=""
fi

info()    { echo "${CYAN}[install]${NC} $*"; }
success() { echo "${GREEN}[install]${NC} $*"; }
warn()    { echo "${YELLOW}[install]${NC} $*"; }
error()   { echo "${RED}[install] ERROR:${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# OS check — Debian/Ubuntu only
# ---------------------------------------------------------------------------
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        die "Cannot detect OS. This installer requires Ubuntu or Debian."
    fi
    # shellcheck source=/dev/null
    . /etc/os-release
    case "${ID:-}${ID_LIKE:-}" in
        *debian*|*ubuntu*) ;;
        *) die "Unsupported OS: ${PRETTY_NAME:-unknown}. This installer requires Ubuntu or a Debian-based distro." ;;
    esac
    info "OS detected: ${PRETTY_NAME:-Linux}"
}

# ---------------------------------------------------------------------------
# Root / sudo detection
# ---------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This installer must be run as root or via sudo.\n\nRun: sudo bash $0"
    fi
}

# ---------------------------------------------------------------------------
# Resolve the actual (non-root) user who invoked sudo
# ---------------------------------------------------------------------------
resolve_user() {
    CALLING_USER="${SUDO_USER:-}"

    # Piped install: SUDO_USER may be empty if root invoked the pipe directly.
    # Try logname as a fallback, then just use root.
    if [[ -z "$CALLING_USER" ]]; then
        CALLING_USER="$(logname 2>/dev/null || true)"
    fi

    if [[ -z "$CALLING_USER" ]] || [[ "$CALLING_USER" == "root" ]]; then
        CALLING_USER="root"
        CALLING_HOME="/root"
    else
        CALLING_HOME="$(getent passwd "$CALLING_USER" | cut -d: -f6)"
        if [[ -z "$CALLING_HOME" ]]; then
            CALLING_HOME="/home/$CALLING_USER"
        fi
    fi

    INSTALL_DIR="${CALLING_HOME}/${INSTALL_DIR_NAME}"
    info "Installing for user: ${BOLD}${CALLING_USER}${NC}"
    info "Install directory:   ${BOLD}${INSTALL_DIR}${NC}"
}

# ---------------------------------------------------------------------------
# System packages
# ---------------------------------------------------------------------------
install_system_deps() {
    info "Updating package list..."
    apt-get update -qq

    local pkgs_needed=()
    for pkg in curl git ca-certificates gnupg lsb-release; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            pkgs_needed+=("$pkg")
        fi
    done

    if [[ ${#pkgs_needed[@]} -gt 0 ]]; then
        info "Installing system packages: ${pkgs_needed[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs_needed[@]}"
    else
        success "System packages already present"
    fi
}

# ---------------------------------------------------------------------------
# Docker install (via get.docker.com convenience script)
# ---------------------------------------------------------------------------
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+' | head -n1)
        success "Docker already installed (v${docker_version})"
        return 0
    fi

    info "Docker not found — installing via get.docker.com..."
    local tmp_script
    tmp_script=$(mktemp /tmp/get-docker-XXXXXX.sh)
    if ! curl -fsSL https://get.docker.com -o "$tmp_script"; then
        rm -f "$tmp_script"
        die "Failed to download Docker install script from get.docker.com"
    fi
    sh "$tmp_script"
    rm -f "$tmp_script"

    if ! command -v docker >/dev/null 2>&1; then
        die "Docker installation failed. Install manually: https://docs.docker.com/get-docker/"
    fi

    success "Docker installed successfully"

    # Enable and start Docker service
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable docker --quiet 2>/dev/null || true
        systemctl start docker  --quiet 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Add the calling user to the docker group so they don't need sudo for docker
# ---------------------------------------------------------------------------
add_user_to_docker_group() {
    if [[ "$CALLING_USER" == "root" ]]; then
        return 0  # root always has docker access
    fi

    if groups "$CALLING_USER" 2>/dev/null | grep -qw docker; then
        success "User ${CALLING_USER} is already in the docker group"
    else
        info "Adding ${CALLING_USER} to the docker group..."
        usermod -aG docker "$CALLING_USER"
        warn "Docker group membership takes effect on next login."
        warn "After setup completes, log out and back in (or run: newgrp docker)"
    fi
}

# ---------------------------------------------------------------------------
# Clone / update the repo
# ---------------------------------------------------------------------------
clone_or_update_repo() {
    if [[ -d "${INSTALL_DIR}/.git" ]]; then
        info "Repository already exists at ${INSTALL_DIR} — pulling latest changes..."
        # Run git as the calling user to preserve credentials / ownership
        if [[ "$CALLING_USER" == "root" ]]; then
            git -C "$INSTALL_DIR" pull --ff-only 2>&1 | sed 's/^/  /'
        else
            su -s /bin/bash -c "git -C '$INSTALL_DIR' pull --ff-only 2>&1 | sed 's/^/  /'" "$CALLING_USER"
        fi
        success "Repository updated"
    else
        info "Cloning WeekendStack into ${INSTALL_DIR}..."
        if [[ "$CALLING_USER" == "root" ]]; then
            git clone "$REPO_URL" "$INSTALL_DIR"
        else
            # Create parent dir with correct ownership first
            mkdir -p "$CALLING_HOME"
            su -s /bin/bash -c "git clone '$REPO_URL' '$INSTALL_DIR'" "$CALLING_USER"
        fi
        success "Repository cloned"
    fi

    # Ensure ownership is correct after any root git operations
    chown -R "${CALLING_USER}:${CALLING_USER}" "$INSTALL_DIR" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Make scripts executable
# ---------------------------------------------------------------------------
make_executable() {
    chmod +x "${INSTALL_DIR}/setup.sh" 2>/dev/null || true
    chmod +x "${INSTALL_DIR}/uninstall.sh" 2>/dev/null || true
    find "${INSTALL_DIR}/tools" -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Print post-install summary
# ---------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo "${BOLD}${GREEN}║                                                                  ║${NC}"
    echo "${BOLD}${GREEN}║            WeekendStack successfully bootstrapped!               ║${NC}"
    echo "${BOLD}${GREEN}║                                                                  ║${NC}"
    echo "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Installed to: ${BOLD}${INSTALL_DIR}${NC}"
    echo ""
    if [[ "$CALLING_USER" != "root" ]]; then
        echo "  ${YELLOW}Note:${NC} You were added to the 'docker' group."
        echo "  After setup completes, log out and back in so Docker works"
        echo "  without sudo. Or run ${BOLD}newgrp docker${NC} in the current shell."
        echo ""
    fi
    echo "  ${BOLD}What's next:${NC}"
    echo "  The interactive setup wizard is launching now."
    echo "  It will guide you through profile selection, credentials,"
    echo "  Cloudflare Tunnel (optional), and starting all services."
    echo ""
    echo "  Once complete, open a browser and navigate to:"
    echo "    ${CYAN}http://${CALLING_HOME##*/}.local:8098${NC}  (Glance dashboard)"
    echo "    ${CYAN}http://HOST_IP:8098${NC}                    (from another device)"
    echo ""
    echo "  Press ${BOLD}Ctrl+C${NC} at any time to pause setup — re-run with:"
    echo "    ${BOLD}cd ${INSTALL_DIR} && bash setup.sh${NC}"
    echo ""
    echo "──────────────────────────────────────────────────────────────────"
    echo ""
}

# ---------------------------------------------------------------------------
# Launch setup.sh as the calling user
# ---------------------------------------------------------------------------
launch_setup() {
    local setup_script="${INSTALL_DIR}/setup.sh"

    if [[ ! -f "$setup_script" ]]; then
        die "setup.sh not found at ${setup_script}. The clone may have failed."
    fi

    # Forward any flags that were passed to install.sh (e.g. --quick)
    local setup_args=("$@")

    info "Launching setup wizard..."
    echo ""

    if [[ "$CALLING_USER" == "root" ]]; then
        cd "$INSTALL_DIR" && bash setup.sh "${setup_args[@]}"
    else
        # Run setup as the actual user — they need Docker access, interactive
        # TTY, and correct $HOME for tool paths.
        # Use 'su' with a login-style shell to get proper environment.
        local args_str=""
        if [[ ${#setup_args[@]} -gt 0 ]]; then
            args_str=" $(printf '%q ' "${setup_args[@]}")"
        fi
        su -s /bin/bash -l "$CALLING_USER" -c "cd '$INSTALL_DIR' && bash setup.sh${args_str}"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo "${BOLD}${CYAN}══════════════════════════════════════════════════════════════════${NC}"
    echo "${BOLD}${CYAN}  WeekendStack Remote Installer${NC}"
    echo "${BOLD}${CYAN}══════════════════════════════════════════════════════════════════${NC}"
    echo ""

    check_os
    check_root
    resolve_user
    install_system_deps
    install_docker
    add_user_to_docker_group
    clone_or_update_repo
    make_executable
    print_summary

    # Pass through any flags supplied to install.sh → setup.sh
    launch_setup "$@"
}

main "$@"
