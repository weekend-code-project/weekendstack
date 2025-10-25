// metadata-blocks (inline version)
// This file is copied into the template root during the push process.
// It defines `local.metadata_blocks` directly so no external module
// directory is required. Other modules can continue to reference
// `local.metadata_blocks` unchanged.

locals {
  metadata_blocks = [
    {
      display_name = "CPU Usage"
      script       = "coder stat cpu"
      interval     = 10
      timeout      = 1
    },
    {
      display_name = "RAM Usage"
      script       = "coder stat mem"
      interval     = 10
      timeout      = 1
    },
    {
      display_name = "Disk Usage"
      script       = "coder stat disk --path $${HOME}"
      interval     = 60
      timeout      = 1
    },
    {
      display_name = "Architecture"
      script       = "uname -m"
      interval     = 60
      timeout      = 5
    },
    {
      display_name = "Ports"
      script       = "echo $PORTS"
      interval     = 60
      timeout      = 1
    },
    {
      display_name = "SSH Port"
      script       = "echo $${SSH_PORT}"
      interval     = 60
      timeout      = 1
    },
    {
      display_name = "Validation"
      script       = "test -f /var/tmp/validation_summary.txt && cat /var/tmp/validation_summary.txt || echo 'PENDING'"
      interval     = 30
      timeout      = 1
    }
  ]
}

