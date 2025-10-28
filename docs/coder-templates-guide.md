# Coder Templates and Modules Guide

This guide provides comprehensive documentation on how Coder templates and modules work in this project, including how to create, modify, and deploy them.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Module System](#module-system)
- [Template Structure](#template-structure)
- [Creating a New Module](#creating-a-new-module)
- [Wiring Up Modules](#wiring-up-modules)
- [Push Script Usage](#push-script-usage)
- [Parameter System](#parameter-system)
- [Testing and Debugging](#testing-and-debugging)
- [Best Practices](#best-practices)

---

## Overview

### What is Coder?

Coder is a platform for creating cloud development environments (CDEs). It uses Terraform templates to define and provision workspaces.

### Project Structure

```
config/coder/
├── scripts/
│   ├── push-template-versioned.sh    # Auto-versioning push script
│   ├── push-templates.sh             # Batch push script
│   ├── cleanup-coder.sh              # Template cleanup
│   └── backup-templates.sh           # Template backup
└── templates/
    ├── git-modules/                  # Reusable modules (git-based)
    │   ├── agent/                    # Coder agent
    │   ├── init-shell/               # Shell initialization
    │   ├── git-integration/          # Git cloning
    │   ├── git-identity/             # Git config (name/email)
    │   ├── ssh-integration/          # SSH server
    │   ├── docker-integration/       # Docker-in-Docker
    │   ├── code-server/              # VS Code Server
    │   ├── preview-link/             # Preview URLs
    │   ├── metadata/                 # Workspace metadata
    │   ├── routing-labels-test/      # Traefik routing labels
    │   ├── setup-server/             # Server setup
    │   ├── workspace-auth/           # Password protection
    │   ├── password-protection/      # Auth middleware
    │   ├── github-cli/               # (empty - needs implementation)
    │   └── validation/               # Parameter validation
    └── v0-1-0-test/                  # Main template
        ├── main.tf                   # Template orchestration
        ├── metadata-params.tf        # Metadata parameters
        └── .template_versions.json   # Version tracking
```

---

## Architecture

### Git-Based Module System

This project uses a **git-based module system** where modules are stored in a git repository and referenced via git URLs with version tags.

**Benefits:**
- Version control for modules
- Easy rollback to previous versions
- Share modules across multiple templates
- Centralized module management

**Module Source Format:**
```hcl
module "example" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/example?ref=v0.1.0"
}
```

### Module Version: v0.1.0

All modules currently reference `ref=v0.1.0`, which is a git tag/branch in the repository.

**To update module version:**
1. Make changes to modules
2. Commit and push to the branch
3. Templates will pull latest changes when rebuilt

---

## Module System

### What is a Module?

A module is a reusable Terraform configuration that encapsulates specific functionality (e.g., SSH server, Git integration, VS Code).

### Module Structure

Each module follows this structure:

```
module-name/
├── main.tf          # Core logic
├── variables.tf     # Input variables
├── outputs.tf       # Output values (optional)
└── README.md        # Documentation
```

### Module Anatomy

#### main.tf
```hcl
# =============================================================================
# MODULE: Example Module
# =============================================================================
# DESCRIPTION:
#   Brief description of what this module does
#
# ARCHITECTURE:
#   - Key architectural decisions
#   - Important implementation details
#
# DEPENDENCIES:
#   - Required modules or resources
#
# OUTPUTS:
#   - What this module exports
#
# =============================================================================

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">=2.4.0"
    }
  }
}

# Variables
variable "agent_id" {
  description = "Coder agent ID"
  type        = string
}

variable "enable_feature" {
  description = "Enable this feature"
  type        = bool
  default     = false
}

# Resources
resource "coder_script" "example" {
  count    = var.enable_feature ? 1 : 0
  agent_id = var.agent_id
  
  display_name = "Example Script"
  icon         = "/icon/example.svg"
  
  script = <<-EOT
    #!/bin/bash
    echo "Running example script..."
  EOT
}

# Outputs
output "example_id" {
  value = try(coder_script.example[0].id, "")
}
```

#### variables.tf
```hcl
variable "agent_id" {
  description = "Coder agent ID from the agent module"
  type        = string
}

variable "enable_feature" {
  description = "Whether to enable this feature"
  type        = bool
  default     = false
}

variable "custom_setting" {
  description = "Custom configuration setting"
  type        = string
  default     = "default-value"
}
```

---

## Template Structure

### Main Template (v0-1-0-test)

The main template orchestrates all modules and defines the workspace.

#### main.tf Structure

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.4.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

# 1. Workspace Data Sources
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# 2. Parameters (from metadata-params.tf and other param files)
# See Parameter System section below

# 3. Locals
locals {
  workspace_name = data.coder_workspace.me.name
  owner_username = data.coder_workspace_owner.me.name
}

# 4. Docker Provider
provider "docker" {
  host = "unix:///var/run/docker.sock"
}

# 5. Docker Resources
resource "docker_image" "workspace" {
  name = "codercom/enterprise-base:ubuntu"
}

resource "docker_container" "workspace" {
  image = docker_image.workspace.image_id
  name  = "coder-${local.owner_username}-${local.workspace_name}"
  
  # Environment variables
  env = [
    "CODER_WORKSPACE_NAME=${local.workspace_name}",
  ]
  
  # Volumes
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home.name
  }
  
  # Labels for Traefik routing
  labels {
    label = "traefik.enable"
    value = "true"
  }
}

resource "docker_volume" "home" {
  name = "coder-${local.owner_username}-${local.workspace_name}-home"
}

# 6. Modules

# Agent (REQUIRED - must be first)
module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/coder-agent?ref=v0.1.0"
  
  container_id = docker_container.workspace.id
  
  depends_on = [
    docker_container.workspace
  ]
}

# Init Shell
module "init_shell" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/init-shell?ref=v0.1.0"
  
  agent_id           = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  init_script        = <<-EOT
    #!/bin/bash
    echo "Custom init script"
  EOT
}

# Git Integration
module "git_integration" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/git-integration?ref=v0.1.0"
  
  agent_id              = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  repo_url              = data.coder_parameter.repo_url.value
  repo_branch           = data.coder_parameter.repo_branch.value
}

# More modules...
```

---

## Creating a New Module

### Step 1: Create Module Directory

```bash
mkdir -p config/coder/templates/git-modules/my-module
cd config/coder/templates/git-modules/my-module
```

### Step 2: Create main.tf

```hcl
# =============================================================================
# MODULE: My Module
# =============================================================================
# DESCRIPTION:
#   Describe what your module does
#
# =============================================================================

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">=2.4.0"
    }
  }
}

variable "agent_id" {
  description = "Coder agent ID"
  type        = string
}

variable "enable_my_feature" {
  description = "Enable my feature"
  type        = bool
  default     = false
}

resource "coder_script" "my_script" {
  count    = var.enable_my_feature ? 1 : 0
  agent_id = var.agent_id
  
  display_name = "My Feature"
  icon         = "/icon/feature.svg"
  script       = file("${path.module}/scripts/setup.sh")
  run_on_start = true
}

output "my_output" {
  value = var.enable_my_feature ? "enabled" : "disabled"
}
```

### Step 3: Create variables.tf

```hcl
variable "agent_id" {
  description = "Coder agent ID from the agent module"
  type        = string
}

variable "enable_my_feature" {
  description = "Whether to enable this feature"
  type        = bool
  default     = false
}
```

### Step 4: Create README.md

```markdown
# My Module

## Description
Brief description of the module.

## Usage
\`\`\`hcl
module "my_module" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/my-module?ref=v0.1.0"
  
  agent_id          = module.agent.agent_id
  enable_my_feature = true
}
\`\`\`

## Variables
- `agent_id` - Coder agent ID (required)
- `enable_my_feature` - Enable feature (default: false)

## Outputs
- `my_output` - Status of the feature
```

### Step 5: Commit and Push

```bash
git add config/coder/templates/git-modules/my-module/
git commit -m "feat: add my-module for feature X"
git push origin v0.1.0
```

---

## Wiring Up Modules

### Step 1: Add Parameters (if needed)

Create or modify parameter files in the template (e.g., `my-params.tf`):

```hcl
data "coder_parameter" "enable_my_feature" {
  name         = "enable_my_feature"
  display_name = "Enable My Feature"
  description  = "Enable my awesome feature"
  type         = "bool"
  default      = "false"
  mutable      = true
  order        = 100
}
```

### Step 2: Add Module to main.tf

```hcl
module "my_module" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/my-module?ref=v0.1.0"
  
  agent_id          = module.agent.agent_id
  enable_my_feature = data.coder_parameter.enable_my_feature.value
  
  depends_on = [
    module.agent,
    module.init_shell  # If your module depends on init_shell
  ]
}
```

### Step 3: Test Locally

Comment out the module initially to test without enabling:

```hcl
# module "my_module" {
#   source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/my-module?ref=v0.1.0"
#   
#   agent_id          = module.agent.agent_id
#   enable_my_feature = data.coder_parameter.enable_my_feature.value
# }
```

### Step 4: Push Template

```bash
cd /mnt/workspace/wcp-coder
./config/coder/scripts/push-template-versioned.sh v0-1-0-test
```

---

## Push Script Usage

### push-template-versioned.sh

This script automatically handles version management and conflict resolution.

**Location:** `config/coder/scripts/push-template-versioned.sh`

**Features:**
- Auto-increments version on conflicts
- Retries up to 5 times
- Updates `.template_versions.json`
- Prevents manual version conflicts

**Usage:**

```bash
# Basic usage
./config/coder/scripts/push-template-versioned.sh v0-1-0-test

# What it does:
# 1. Reads current version from .template_versions.json
# 2. Pushes template with that version
# 3. If "already exists" error, increments and retries
# 4. Updates .template_versions.json on success
```

**How it works:**

```bash
#!/bin/bash
TEMPLATE_NAME="$1"
VERSION_FILE=".template_versions.json"
MAX_RETRIES=5

# Read current version
VERSION=$(jq -r ".${TEMPLATE_NAME} // 1" "$VERSION_FILE")

# Retry loop
for i in $(seq 1 $MAX_RETRIES); do
  # Try to push
  OUTPUT=$(coder templates push "$TEMPLATE_NAME" \
    --directory "config/coder/templates/${TEMPLATE_NAME}" \
    --name "$TEMPLATE_NAME" \
    --version "v$VERSION" 2>&1)
  
  if [ $? -eq 0 ]; then
    # Success - update version file
    jq ".${TEMPLATE_NAME} = $((VERSION + 1))" "$VERSION_FILE" > tmp.json
    mv tmp.json "$VERSION_FILE"
    echo "✅ Pushed v$VERSION"
    exit 0
  fi
  
  # Check for version conflict
  if echo "$OUTPUT" | grep -q "already exists"; then
    VERSION=$((VERSION + 1))
    echo "Version exists, trying v$VERSION..."
    continue
  else
    # Other error
    echo "$OUTPUT"
    exit 1
  fi
done

echo "❌ Failed after $MAX_RETRIES attempts"
exit 1
```

**Version Tracking:**

`.template_versions.json`:
```json
{
  "v0-1-0-test": 37
}
```

This tracks the next version to use for each template.

---

## Parameter System

### Parameter Types

Coder supports several parameter types:

```hcl
# String
data "coder_parameter" "my_string" {
  type    = "string"
  default = "value"
}

# Number
data "coder_parameter" "my_number" {
  type    = "number"
  default = "8080"
}

# Boolean
data "coder_parameter" "my_bool" {
  type    = "bool"
  default = "true"
}

# List of strings (multi-select)
data "coder_parameter" "my_list" {
  type      = "list(string)"
  default   = jsonencode(["option1", "option2"])
}
```

### Multi-Select Parameters

**Critical: Use `form_type` for checkboxes**

```hcl
data "coder_parameter" "features" {
  name         = "features"
  display_name = "Features to Enable"
  description  = "Select features"
  type         = "list(string)"
  mutable      = true
  order        = 10
  
  # IMPORTANT: This makes checkboxes instead of radio buttons
  form_type    = "multi-select"
  
  # Default value must be JSON encoded
  default = jsonencode(["feature1", "feature2"])
  
  # Options must use plain string values (NOT jsonencode)
  option {
    name        = "Feature 1"
    description = "Description of feature 1"
    value       = "feature1"  # Plain string!
  }
  
  option {
    name        = "Feature 2"
    description = "Description of feature 2"
    value       = "feature2"  # Plain string!
  }
}
```

### Using Multi-Select Values

```hcl
# Parse the JSON array
locals {
  selected_features = jsondecode(data.coder_parameter.features.value)
}

# Use in module
module "feature_handler" {
  source = "..."
  
  enabled_features = local.selected_features
}
```

**Common Mistake:**
```hcl
# ❌ WRONG - Do not use jsonencode for option values
option {
  value = jsonencode(["feature1"])  # This creates nested arrays!
}

# ✅ CORRECT - Use plain strings
option {
  value = "feature1"
}
```

### Dynamic Options

Use `locals` and `dynamic` blocks for DRY code:

```hcl
locals {
  feature_options = {
    cpu = {
      name        = "CPU Usage"
      description = "Display CPU usage"
    }
    ram = {
      name        = "RAM Usage"
      description = "Display RAM usage"
    }
  }
}

data "coder_parameter" "features" {
  name      = "features"
  type      = "list(string)"
  form_type = "multi-select"
  
  dynamic "option" {
    for_each = local.feature_options
    content {
      name        = option.value.name
      description = option.value.description
      value       = option.key  # Key becomes the value
    }
  }
}
```

### Parameter Visibility

Control parameter visibility with `count`:

```hcl
data "coder_parameter" "ssh_port" {
  name  = "ssh_port"
  type  = "string"
  
  # Only show when SSH is enabled AND manual mode
  count = (
    data.coder_parameter.ssh_enable.value && 
    data.coder_parameter.ssh_port_mode.value == "manual"
  ) ? 1 : 0
}

# Access conditional parameter with try()
locals {
  ssh_port = try(data.coder_parameter.ssh_port[0].value, "")
}
```

---

## Testing and Debugging

### Local Testing

1. **Check Terraform syntax:**
```bash
cd config/coder/templates/v0-1-0-test
terraform fmt
terraform validate
```

2. **Push template:**
```bash
./config/coder/scripts/push-template-versioned.sh v0-1-0-test
```

3. **Create test workspace:**
- Go to Coder UI: http://coder:7080
- Create new workspace from template
- Monitor startup logs

### Debugging Tips

1. **Add debug metadata blocks:**
```hcl
resource "coder_metadata" "debug" {
  resource_id = module.agent.agent_id
  
  item {
    key   = "debug_value"
    value = data.coder_parameter.my_param.value
  }
}
```

2. **Check module output:**
```hcl
output "debug_info" {
  value = {
    param_value = data.coder_parameter.my_param.value
    module_out  = module.my_module.my_output
  }
}
```

3. **Use coder_script for debugging:**
```hcl
resource "coder_script" "debug" {
  agent_id     = module.agent.agent_id
  display_name = "Debug Info"
  
  script = <<-EOT
    echo "=== DEBUG INFO ==="
    echo "Parameter: ${data.coder_parameter.my_param.value}"
    env | grep CODER_
  EOT
}
```

4. **Check Coder logs:**
```bash
docker logs coder -f
```

### Common Issues

**Issue: Module not found**
```
Error: Failed to download module
```
**Solution:** 
- Verify git URL is correct
- Ensure ref=v0.1.0 branch/tag exists
- Check module path in URL
- Try: `git ls-remote https://github.com/weekend-code-project/weekendstack.git`

**Issue: Nested array in multi-select**
```
Selected value: [["option1"]]
```
**Solution:** Use plain string values in options, not `jsonencode(["option1"])`

**Issue: jsondecode EOF error**
```
Error: EOF
```
**Solution:** Handle empty selections:
```hcl
locals {
  values = data.coder_parameter.my_param.value != "" ? jsondecode(data.coder_parameter.my_param.value) : []
}
```

**Issue: Version already exists**
```
Error: version v35 already exists
```
**Solution:** 
- Use push-template-versioned.sh (auto-handles this)
- Or manually increment version in command

---

## Best Practices

### Module Design

1. **Single Responsibility:** Each module should do one thing well
2. **Configurable:** Use variables for all configurable aspects
3. **Documented:** Include comprehensive README.md
4. **Tested:** Test module independently before integrating
5. **Conditional:** Use `count` for optional features

### Template Organization

1. **Separate parameter files:** Keep parameters organized by topic
   - `metadata-params.tf` - Metadata block selections
   - `git-params.tf` - Git configuration
   - `ssh-params.tf` - SSH settings
   
2. **Comment unused modules:** Keep them in code but commented out
```hcl
# TODO: Enable when ready
# module "my_module" {
#   source = "..."
# }
```

3. **Use locals for complex logic:**
```hcl
locals {
  should_enable_feature = (
    data.coder_parameter.enable_feature.value &&
    data.coder_workspace.me.start_count > 0
  )
}
```

4. **Explicit dependencies:**
```hcl
module "my_module" {
  source = "..."
  
  depends_on = [
    module.agent,
    module.init_shell
  ]
}
```

### Version Control

1. **Commit module changes first:**
```bash
git add config/coder/templates/git-modules/my-module/
git commit -m "feat: add my-module"
git push origin v0.1.0
```

2. **Then commit template changes:**
```bash
git add config/coder/templates/v0-1-0-test/
git commit -m "feat: integrate my-module into template"
git push origin v0.1.0
```

3. **Use semantic commit messages:**
- `feat:` - New features
- `fix:` - Bug fixes
- `chore:` - Maintenance tasks
- `docs:` - Documentation

### Push Script Best Practices

1. **Always use push-template-versioned.sh** for rapid iteration
2. **Check version file** after successful push
3. **Don't manually edit** `.template_versions.json` unless needed
4. **Commit version file** after major milestones

### Parameter Best Practices

1. **Provide defaults** for all parameters
2. **Use descriptions** to guide users
3. **Set appropriate order** values (10, 20, 30, ...)
4. **Make parameters mutable** when users might want to change them
5. **Use validation** for complex parameters:
```hcl
data "coder_parameter" "port" {
  type = "number"
  
  validation {
    condition     = data.coder_parameter.port.value >= 1024 && data.coder_parameter.port.value <= 65535
    error_message = "Port must be between 1024 and 65535"
  }
}
```

---

## Quick Reference

### Create New Module
```bash
mkdir -p config/coder/templates/git-modules/MODULE_NAME
cd config/coder/templates/git-modules/MODULE_NAME
# Create main.tf, variables.tf, README.md
git add .
git commit -m "feat: add MODULE_NAME"
git push origin v0.1.0
```

### Add Module to Template
```hcl
module "MODULE_NAME" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/MODULE_NAME?ref=v0.1.0"
  
  agent_id = module.agent.agent_id
  # ... other variables
}
```

### Push Template
```bash
./config/coder/scripts/push-template-versioned.sh v0-1-0-test
```

### Test Workspace
1. Open Coder UI: http://coder:7080
2. Create new workspace
3. Monitor startup logs
4. Verify functionality

---

## Additional Resources

- **Coder Documentation:** https://coder.com/docs
- **Terraform Documentation:** https://www.terraform.io/docs
- **Coder Provider:** https://registry.terraform.io/providers/coder/coder/latest/docs
- **Project Repository:** https://github.com/weekend-code-project/weekendstack

---

## Change Log

- **2025-10-28:** Initial documentation created
- Multi-select parameter implementation documented
- Push script with auto-retry documented
- Git-based module system documented
