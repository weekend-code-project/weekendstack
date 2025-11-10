# =============================================================================
# Coder Agent - Minimal Configuration
# =============================================================================
# This creates the Coder agent that runs inside the workspace container.

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/coder-agent?ref=v0.1.2-test-base"
  
  # Required architecture info
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  
  # Git identity (using workspace owner info)
  git_author_name  = data.coder_workspace_owner.me.name
  git_author_email = data.coder_workspace_owner.me.email
  
  # Access URL for agent connection
  coder_access_url = data.coder_workspace.me.access_url
  
  # No additional environment variables
  env_vars = []
  
  # No additional metadata blocks
  metadata_blocks = []
  
  # Minimal startup script - just bash basics
  startup_script = <<-EOT
    #!/bin/bash
    set -e
    echo '[WORKSPACE] 🚀 Starting workspace ${data.coder_workspace.me.name}'
    echo '[WORKSPACE] ✅ Workspace ready!'
  EOT
}
