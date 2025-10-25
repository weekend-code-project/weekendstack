# =============================================================================
# MODULE: Init Shell
# =============================================================================
# DESCRIPTION:
#   Initializes the home directory structure for a new workspace.
#   Creates necessary directories and sets up the environment.
#
# USAGE:
#   This module outputs a shell script that should be included in the
#   coder_agent startup_script.
#
# OUTPUTS:
#   - setup_script: Shell script to initialize home directory
# =============================================================================

output "setup_script" {
  description = "Shell script to initialize home directory structure"
  value       = <<-EOT
    #!/bin/bash
    # Initialize home directory with skeleton files
    set -e
    
    if [ ! -f ~/.init_done ]; then
      echo "[INIT] First startup detected, initializing home directory..."
      cp -rT /etc/skel ~ || true
      
      # Create standard directories
      mkdir -p ~/workspace
      mkdir -p ~/.config
      mkdir -p ~/.local/bin
      
      # Ensure proper permissions
      chmod 755 ~/workspace
      
      touch ~/.init_done
      echo "[INIT] ✅ Home directory initialized"
    else
      echo "[INIT] Home directory already initialized"
    fi
  EOT
}
