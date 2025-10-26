# Minimal test module - just one variable and one output

variable "workspace_name" {
  description = "Name of the workspace"
  type        = string
}

output "test_output" {
  description = "Test output"
  value       = "Hello from ${var.workspace_name}"
}
