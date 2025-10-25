# =============================================================================
# MODULE OUTPUTS: Docker Workspace
# =============================================================================

output "agent_token" {
  description = "The Coder agent token for this workspace"
  value       = coder_agent.main.token
  sensitive   = true
}

output "agent_id" {
  description = "The Coder agent ID"
  value       = coder_agent.main.id
}

output "container_id" {
  description = "Docker container ID (empty if workspace stopped)"
  value       = length(docker_container.workspace) > 0 ? docker_container.workspace[0].id : ""
}

output "home_volume_name" {
  description = "Name of the home directory volume"
  value       = docker_volume.home_volume.name
}
