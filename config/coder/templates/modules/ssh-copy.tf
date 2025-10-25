# =============================================================================
# MODULE: SSH Copy Keys
# =============================================================================
# Copies SSH keys from a mounted host directory into the workspace for Git.

locals {
  ssh_copy = <<-EOT
    if [ -d "/mnt/host-ssh" ]; then
      echo "[SSH COPY] Installing SSH keys from /mnt/host-ssh..."
      mkdir -p ~/.ssh
      chmod 700 ~/.ssh
      if [ -f "/mnt/host-ssh/id_ed25519" ]; then
        cp /mnt/host-ssh/id_ed25519 ~/.ssh/id_ed25519
        chmod 600 ~/.ssh/id_ed25519
      fi
      if [ -f "/mnt/host-ssh/id_ed25519.pub" ]; then
        cp /mnt/host-ssh/id_ed25519.pub ~/.ssh/id_ed25519.pub
        chmod 644 ~/.ssh/id_ed25519.pub
      fi
      touch ~/.ssh/known_hosts
      chmod 644 ~/.ssh/known_hosts
      ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
      echo "[SSH COPY] Keys installed."
    fi
  EOT
}
