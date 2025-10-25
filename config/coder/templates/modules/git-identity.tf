# =============================================================================
# MODULE: Git Identity
# =============================================================================
# Configures Git with the workspace owner's name and email for commits and
# marks the workspace folder as safe.

locals {
  git_identity = <<-EOT
    git config --global user.name "${coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)}"
    git config --global user.email "${data.coder_workspace_owner.me.email}"
    git config --global --add safe.directory /home/coder/workspace
  EOT
}
