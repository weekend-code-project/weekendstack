#!/bin/bash
# Certificate helper for local HTTPS setup
# Handles cert generation and OS-specific trust installation

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

generate_certificates() {
    local stack_dir="${SCRIPT_DIR}/.."
    
    log_header "Local HTTPS Certificate Generation"
    
    echo "Generating self-signed CA and wildcard certificate for local HTTPS..."
    echo "This enables https://service.lab access on your local network."
    echo ""
    
    # Check if certificates already exist
    if [[ -f "$stack_dir/config/traefik/certs/ca-cert.pem" ]]; then
        log_info "Certificates already exist"
        if ! prompt_yes_no "Regenerate certificates?" "n"; then
            return 0
        fi
    fi
    
    log_step "Running cert-generator init container..."
    
    # Run cert-generator service
    if docker compose --profile=setup up cert-generator 2>/dev/null; then
        log_success "Certificates generated successfully"
    else
        log_error "Failed to generate certificates"
        return 1
    fi
    
    # Verify certificate files exist
    local cert_dir="$stack_dir/config/traefik/certs"
    local required_files=("ca-cert.pem" "ca-key.pem" "cert.pem" "key.pem")
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$cert_dir/$file" ]]; then
            log_error "Missing certificate file: $file"
            return 1
        fi
    done
    
    log_success "All certificate files created"
    echo ""
    echo "Certificate files:"
    echo "  CA Certificate: $cert_dir/ca-cert.pem"
    echo "  CA Key:         $cert_dir/ca-key.pem"
    echo "  Server Cert:    $cert_dir/cert.pem"
    echo "  Server Key:     $cert_dir/key.pem"
    echo ""
}

install_ca_certificate() {
    local stack_dir="${SCRIPT_DIR}/.."
    local ca_cert="$stack_dir/config/traefik/certs/ca-cert.pem"
    
    if [[ ! -f "$ca_cert" ]]; then
        log_error "CA certificate not found. Run cert generation first."
        return 1
    fi
    
    log_header "CA Certificate Trust Installation"
    
    echo "To avoid browser security warnings, you need to trust the CA certificate."
    echo ""
    
    local os_type=$(detect_os)
    
    case "$os_type" in
        ubuntu|debian)
            install_ca_debian "$ca_cert"
            ;;
        fedora|rhel|centos)
            install_ca_rhel "$ca_cert"
            ;;
        arch)
            install_ca_arch "$ca_cert"
            ;;
        macos)
            install_ca_macos "$ca_cert"
            ;;
        *)
            install_ca_manual "$ca_cert"
            ;;
    esac
}

install_ca_debian() {
    local ca_cert="$1"
    
    log_info "Detected Debian/Ubuntu system"
    echo ""
    echo "To install the CA certificate system-wide:"
    echo ""
    echo "  sudo cp $ca_cert /usr/local/share/ca-certificates/weekendstack-ca.crt"
    echo "  sudo update-ca-certificates"
    echo ""
    
    if prompt_yes_no "Install CA certificate now?" "y"; then
        if sudo cp "$ca_cert" /usr/local/share/ca-certificates/weekendstack-ca.crt 2>/dev/null; then
            if sudo update-ca-certificates 2>/dev/null; then
                log_success "CA certificate installed system-wide"
                log_info "Browsers using system store (Chrome, Chromium) will trust certificates"
            else
                log_error "Failed to update CA certificates"
                return 1
            fi
        else
            log_error "Failed to copy CA certificate (check sudo access)"
            return 1
        fi
    else
        log_info "Skipped automatic installation"
    fi
    
    install_ca_firefox_linux "$ca_cert"
}

install_ca_rhel() {
    local ca_cert="$1"
    
    log_info "Detected RHEL/Fedora/CentOS system"
    echo ""
    echo "To install the CA certificate system-wide:"
    echo ""
    echo "  sudo cp $ca_cert /etc/pki/ca-trust/source/anchors/weekendstack-ca.crt"
    echo "  sudo update-ca-trust"
    echo ""
    
    if prompt_yes_no "Install CA certificate now?" "y"; then
        if sudo cp "$ca_cert" /etc/pki/ca-trust/source/anchors/weekendstack-ca.crt 2>/dev/null; then
            if sudo update-ca-trust 2>/dev/null; then
                log_success "CA certificate installed system-wide"
            else
                log_error "Failed to update CA trust"
                return 1
            fi
        else
            log_error "Failed to copy CA certificate"
            return 1
        fi
    else
        log_info "Skipped automatic installation"
    fi
    
    install_ca_firefox_linux "$ca_cert"
}

install_ca_arch() {
    local ca_cert="$1"
    
    log_info "Detected Arch Linux system"
    echo ""
    echo "To install the CA certificate system-wide:"
    echo ""
    echo "  sudo trust anchor --store $ca_cert"
    echo ""
    
    if prompt_yes_no "Install CA certificate now?" "y"; then
        if sudo trust anchor --store "$ca_cert" 2>/dev/null; then
            log_success "CA certificate installed system-wide"
        else
            log_error "Failed to install CA certificate"
            return 1
        fi
    else
        log_info "Skipped automatic installation"
    fi
    
    install_ca_firefox_linux "$ca_cert"
}

install_ca_macos() {
    local ca_cert="$1"
    
    log_info "Detected macOS system"
    echo ""
    echo "To install the CA certificate in macOS:"
    echo ""
    echo "  sudo security add-trusted-cert -d -r trustRoot \\"
    echo "    -k /Library/Keychains/System.keychain $ca_cert"
    echo ""
    
    if prompt_yes_no "Install CA certificate now?" "y"; then
        if sudo security add-trusted-cert -d -r trustRoot \
            -k /Library/Keychains/System.keychain "$ca_cert" 2>/dev/null; then
            log_success "CA certificate installed in System keychain"
            log_info "You may need to restart your browser"
        else
            log_error "Failed to install CA certificate"
            return 1
        fi
    else
        log_info "Skipped automatic installation"
        echo ""
        echo "Manual installation:"
        echo "1. Double-click: $ca_cert"
        echo "2. Add to 'System' keychain"
        echo "3. Open Keychain Access, find 'WeekendStack CA'"
        echo "4. Double-click → Trust → Always Trust"
    fi
}

install_ca_firefox_linux() {
    local ca_cert="$1"
    
    echo ""
    log_info "Firefox uses its own certificate store"
    echo ""
    
    if ! check_command certutil; then
        echo "Firefox certificate import requires: libnss3-tools"
        echo "Install with: sudo apt install libnss3-tools"
        echo ""
        return 0
    fi
    
    if prompt_yes_no "Import CA into Firefox certificate store?" "n"; then
        local firefox_dirs=(
            "$HOME/.mozilla/firefox"
            "$HOME/snap/firefox/common/.mozilla/firefox"
        )
        
        for firefox_dir in "${firefox_dirs[@]}"; do
            if [[ -d "$firefox_dir" ]]; then
                for profile in "$firefox_dir"/*.*/; do
                    if [[ -d "$profile" ]]; then
                        log_step "Importing to Firefox profile: $(basename "$profile")"
                        certutil -A -n "WeekendStack CA" -t "TCu,Cu,Tu" \
                            -i "$ca_cert" -d "sql:$profile" 2>/dev/null && \
                            log_success "Imported to $(basename "$profile")" || \
                            log_warn "Failed to import to $(basename "$profile")"
                    fi
                done
            fi
        done
    fi
}

install_ca_manual() {
    local ca_cert="$1"
    
    log_warn "Automatic installation not available for your OS"
    echo ""
    echo "CA Certificate location:"
    echo "  $ca_cert"
    echo ""
    echo "Manual installation instructions:"
    echo ""
    echo "Chrome/Chromium:"
    echo "  Settings → Privacy → Security → Manage certificates"
    echo "  → Authorities → Import → Select ca-cert.pem → Trust for websites"
    echo ""
    echo "Firefox:"
    echo "  Settings → Privacy & Security → View Certificates"
    echo "  → Authorities → Import → Select ca-cert.pem → Trust for websites"
    echo ""
    echo "Edge:"
    echo "  Settings → Privacy → Security → Manage certificates"
    echo "  → Trusted Root → Import → Select ca-cert.pem"
    echo ""
}

verify_certificate_trust() {
    local stack_dir="${SCRIPT_DIR}/.."
    
    if [[ ! -f "$stack_dir/.env" ]]; then
        return 0
    fi
    
    local lab_domain=$(grep "^LAB_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2)
    
    if [[ -z "$lab_domain" ]]; then
        lab_domain="lab"
    fi
    
    echo ""
    log_header "Certificate Trust Verification"
    
    echo "After installing the CA certificate:"
    echo ""
    echo "1. Restart your browser"
    echo "2. Start the stack: ./setup.sh --start"
    echo "3. Visit: https://home.$lab_domain"
    echo "4. Verify: No security warning appears"
    echo ""
    
    log_info "If you still see warnings, the CA may not be trusted"
    log_info "Check browser certificate settings or review manual instructions"
}

setup_certificates() {
    if ! generate_certificates; then
        log_error "Certificate generation failed"
        return 1
    fi
    
    echo ""
    if prompt_yes_no "Install CA certificate for HTTPS trust?" "y"; then
        install_ca_certificate
        verify_certificate_trust
    else
        log_warn "Skipped CA installation - browsers will show security warnings"
        log_info "You can install the CA later from: config/traefik/certs/ca-cert.pem"
    fi
    
    return 0
}

# Export functions
export -f generate_certificates install_ca_certificate
export -f install_ca_debian install_ca_rhel install_ca_arch install_ca_macos
export -f install_ca_firefox_linux install_ca_manual
export -f verify_certificate_trust setup_certificates
