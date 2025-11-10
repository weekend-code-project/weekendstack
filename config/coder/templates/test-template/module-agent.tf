# =============================================================================
# Coder Agent - Minimal Configuration
# =============================================================================
# This creates the Coder agent that runs inside the workspace container.

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/coder-agent?ref=v0.1.2-test-base"
  
  workspace_id   = data.coder_workspace.me.id
  workspace_name = data.coder_workspace.me.name
  owner_name     = data.coder_workspace_owner.me.name
  
  # Minimal startup script - just bash basics
  startup_script = <<-EOT
    #!/bin/bash
    set -e
    echo '[WORKSPACE] 🚀 Starting workspace ${data.coder_workspace.me.name}'
    echo '[WORKSPACE] ✅ Workspace ready!'
  EOT
}
