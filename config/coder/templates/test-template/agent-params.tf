# =============================================================================
# Coder Agent - Test Template Configuration
# =============================================================================
# This creates the Coder agent that runs inside the workspace container.
# Updated to work with config-based module system.

# Collect custom metadata blocks from modules
# This local is referenced by the overlaid metadata-params.tf
# Only include blocks that user explicitly selected
locals {
  # Decode selected metadata blocks
  selected_blocks = try(jsondecode(data.coder_parameter.metadata_blocks.value), [])
  
  # Only include server_ports if user selected it AND module exists
  server_metadata = contains(local.selected_blocks, "server_ports") ? try(module.setup_server[0].metadata_blocks, []) : []
  
  # Only include ssh_port if user selected it AND SSH is actually enabled
  ssh_metadata = contains(local.selected_blocks, "ssh_port") && data.coder_parameter.ssh_enable.value ? try(module.ssh[0].metadata_blocks, []) : []
  
  # Combine only the selected custom blocks
  selected_custom_metadata = concat(
    local.server_metadata,
    local.ssh_metadata
  )
  
  # Conditional log messages for disabled features
  ssh_disabled_log = data.coder_parameter.ssh_enable.value ? "" : "echo '[SSH] SSH server disabled'"
  server_disabled_log = data.coder_parameter.startup_command.value != "" ? "" : "echo '[SETUP-SERVER] No server command configured - skipping server setup'"
}

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent-module?ref=PLACEHOLDER"
  
  # Required architecture info
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  
  # Git identity (using workspace owner info)
  git_author_name  = data.coder_workspace_owner.me.name
  git_author_email = data.coder_workspace_owner.me.email
  
  # Access URL for agent connection
  coder_access_url = "http://host.docker.internal:7080"
  
  # No additional environment variables for Phase 1
  env_vars = {}
  
  # PHASE 4: Metadata blocks from metadata module (which includes all_custom_metadata)
  metadata_blocks = try(module.metadata.metadata_blocks, [])
  
  # Minimal startup script for Phase 1
  # Modules will add their scripts as they're enabled in modules.txt
  startup_script = join("\n", [
    "#!/bin/bash",
    "echo '[WORKSPACE] Starting workspace ${data.coder_workspace.me.name}'",
    "",
    "# Phase 1: init-shell (always included)",
    try(module.init_shell.setup_script, ""),
    "",
    "# Phase 4: SSH and server modules",
    local.ssh_disabled_log,
    try(module.ssh[0].ssh_copy_script, ""),
    try(module.ssh[0].ssh_setup_script, ""),
    "",
    "# Phase 5: Traefik auth and server setup",
    try(module.traefik[0].auth_setup_script, ""),
    "",
    local.server_disabled_log,
    try(module.setup_server[0].setup_server_script, ""),
    "",
    "echo '[WORKSPACE] Workspace ready!'"
  ])
}
