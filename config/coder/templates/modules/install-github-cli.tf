# =============================================================================
# MODULE: Install GitHub CLI
# =============================================================================
# Installs GitHub CLI (gh) if not present and configures SSH as protocol.

data "coder_parameter" "install_github_cli" {
  name         = "install_github_cli"
  display_name = "Install GitHub CLI"
  description  = "Install the GitHub CLI (gh) during startup. Turn off to speed up workspace creation."
  type         = "bool"
  default      = false
  mutable      = true
  order        = 35
}

locals {
  install_github_cli = <<-BASH
    if [ "${data.coder_parameter.install_github_cli.value}" != "true" ]; then
      echo "[GH] Skipping GitHub CLI install (install_github_cli=false)"
    else
      if command -v gh >/dev/null 2>&1; then
        echo "[GH] GitHub CLI already installed"
      else
        echo "[GH] Installing GitHub CLI..."
        export DEBIAN_FRONTEND=noninteractive
        if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
          echo "[GH] Skipping GitHub CLI install: need root or sudo"
        else
          SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
          $SUDO apt-get -yq update
          $SUDO apt-get -yq install curl ca-certificates gnupg
          curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | $SUDO dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
          $SUDO chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
          $SUDO apt-get -yq update
          $SUDO apt-get -yq install gh
          echo "[GH] GitHub CLI installed. Run 'gh auth login' to authenticate."
        fi
      fi
      gh config set git_protocol ssh >/dev/null 2>&1 || true
    fi
  BASH
}
