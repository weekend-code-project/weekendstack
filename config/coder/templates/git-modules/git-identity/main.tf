# =============================================================================
# MODULE: Git Identity
# =============================================================================
# DESCRIPTION:
#   Configures Git with the workspace owner's name and email for commits and
#   marks the workspace folder as safe.
#
# USAGE:
#   This module outputs a shell script that should be included in the
#   coder_agent startup_script.
#
# OUTPUTS:
#   - setup_script: Shell script to configure git identity
# =============================================================================

output "setup_script" {
  description = "Shell script to configure git identity"
  value       = <<-EOT
    echo "[GIT-IDENTITY] Configuring Git identity..."
    git config --global user.name "${var.git_author_name}"
    git config --global user.email "${var.git_author_email}"
    git config --global --add safe.directory /home/coder/workspace
    echo "[GIT-IDENTITY] ✅ Git identity configured"
  EOT
}
