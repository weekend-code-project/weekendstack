# =============================================================================
# MODULE: Coder User Setup
# =============================================================================
# DESCRIPTION:
#   Creates the coder user and sets up the environment for Docker images
#   that don't include a coder user (like node:20-bullseye).
#   This MUST run before any SSH/Git modules that use ~/
#
# USAGE:
#   Include this module output FIRST in the coder_agent startup_script
#
# OUTPUTS:
#   - setup_script: Shell script to create coder user if needed
# =============================================================================

output "setup_script" {
  description = "Shell script to setup coder user for images without it"
  value       = <<-EOT
    #!/bin/bash
    # Setup coder user if running as root in a non-Coder image
    set -e
    
    echo "[USER-SETUP] Checking user context..."
    
    if [ "$(id -u)" = "0" ]; then
      echo "[USER-SETUP] Running as root, checking if coder user exists..."
      
      if ! id -u coder >/dev/null 2>&1; then
        echo "[USER-SETUP] Creating coder user..."
        
        # Create coder user with home directory
        useradd -m -s /bin/bash -u 1000 coder
        
        # Add to sudo group if it exists
        if getent group sudo >/dev/null; then
          usermod -aG sudo coder
        fi
        
        # Allow passwordless sudo for coder
        echo "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder
        chmod 440 /etc/sudoers.d/coder
        
        # Create workspace directory
        mkdir -p /home/coder/workspace
        chown -R coder:coder /home/coder
        
        # Create .persist directory for SSH host keys
        mkdir -p /home/coder/.persist
        chown -R coder:coder /home/coder/.persist
        
        echo "[USER-SETUP] ✓ Coder user created (uid=1000)"
      else
        echo "[USER-SETUP] Coder user already exists"
      fi
      
      echo ""  # Line break after module
      
      # CRITICAL: Switch to coder user for all subsequent operations
      # Export HOME so ~ resolves correctly
      export HOME=/home/coder
      export USER=coder
      cd /home/coder
      
      echo "[USER-SETUP] Switched context to coder user (HOME=$HOME)"
    else
      echo "[USER-SETUP] Already running as non-root user ($(whoami))"
    fi
  EOT
}
