# =============================================================================
# MODULE: Install Node.js
# =============================================================================
# Installs the specified major version of Node.js via NodeSource.

locals {
  install_node = <<-EOT
    echo "[NODE] Installing Node.js v${data.coder_parameter.node_version.value}..."
    curl -fsSL https://deb.nodesource.com/setup_${data.coder_parameter.node_version.value}.x | sudo -E bash -
    sudo apt-get install -y nodejs
    echo "[NODE] Node: $(node -v 2>/dev/null || echo not installed)"
    echo "[NODE] NPM:  $(npm -v 2>/dev/null || echo not installed)"
  EOT
}
