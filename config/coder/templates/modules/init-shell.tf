# =============================================================================
# MODULE: Init Shell
# =============================================================================
# DESCRIPTION:
#   Initializes the user's home directory with default skeleton files on first
#   workspace startup. Creates a marker file (~/.init_done) to prevent 
#   re-initialization on subsequent starts.
#
# DEPENDENCIES:
#   - None (should always run first)
#
# PARAMETERS:
#   - None
#
# CONFIGURATION:
#   - None (always enabled, always runs)
#
# ENVIRONMENT VARIABLES:
#   - None required
#
# USAGE:
#   startup_script = local.init_shell
#
#   # Or as part of composition:
#   startup_script = join("\n", [
#     local.init_shell,
#     local.other_module,
#   ])
#
# OUTPUTS:
#   - local.init_shell (string): Bash script segment
#
# NOTES:
#   - This module should ALWAYS be the first module in the startup script
#   - Idempotent: Safe to run multiple times (checks for marker file)
#   - Copies files from /etc/skel which contains default user files
# =============================================================================

locals {
  init_shell = <<-EOT
    #!/bin/bash
    # Initialize home directory with skeleton files
    set -e
    
    if [ ! -f ~/.init_done ]; then
      echo "[INIT] First startup detected, initializing home directory..."
      cp -rT /etc/skel ~ || true
      touch ~/.init_done
      echo "[INIT] ✓ Home directory initialized"
    else
      echo "[INIT] Home directory already initialized, skipping..."
    fi
  EOT
}
