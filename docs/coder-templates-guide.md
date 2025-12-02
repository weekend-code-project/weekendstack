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
├── template-modules/
│   ├── modules/                      # Git-addressable Terraform modules (agent, docker, ssh, etc.)
│   └── params/                       # Shared parameter glue overlaid into templates at push time
└── templates/
  ├── docker-template/              # Production template (v82 baseline)
  ├── node-template/                # Node-focused variant (under investigation)
  └── test-template/                # Zero-parameter baseline for flicker work
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
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/example?ref=v0.1.0"
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

### Shared Parameter Files

The `config/coder/template-modules/params/` directory contains `*-params.tf` files that define reusable Coder parameters plus the corresponding module invocations (via `module "xyz" { ... }`). During a template push, `push-template-versioned.sh` copies any missing shared parameter files into the template's working directory unless the template ships its own override. This keeps templates lightweight while guaranteeing consistent parameter definitions across Docker, SSH, metadata, etc.

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
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent-module?ref=v0.1.0"
  
  container_id = docker_container.workspace.id
  
  depends_on = [
    docker_container.workspace
  ]
}

# Init Shell
module "init_shell" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/init-shell-module?ref=v0.1.0"
  
  agent_id           = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  init_script        = <<-EOT
    #!/bin/bash
    echo "Custom init script"
  EOT
}

# Git Integration
module "git_integration" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/git-integration-module?ref=v0.1.0"
  
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
mkdir -p config/coder/template-modules/modules/my-module
cd config/coder/template-modules/modules/my-module
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
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/my-module?ref=v0.1.0"
  
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
git add config/coder/template-modules/modules/my-module/
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
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/my-module?ref=v0.1.0"
  
  agent_id          = module.agent.agent_id
  enable_my_feature = data.coder_parameter.enable_my_feature.value
  
  depends_on = [
    module.agent,
    module.init_shell  # If your module depends on init_shell
  ]
}
```

### Step 3: Push and Test

Push the template to Coder (it will validate Terraform automatically):

```bash
cd /mnt/workspace/wcp-coder
./config/coder/scripts/push-template-versioned.sh docker-template
```

The push script will:
- Copy template to Coder container
- Run Terraform validation automatically
- Report any syntax or configuration errors
- Create new template version if successful

Then test by creating a workspace in the Coder UI.

**Optional:** Comment out the module initially if you want to test incrementally:

```hcl
# module "my_module" {
#   source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/my-module?ref=v0.1.0"
#   
#   agent_id          = module.agent.agent_id
#   enable_my_feature = data.coder_parameter.enable_my_feature.value
# }
```

---

## Push Script Usage

### push-template-versioned.sh

This script automatically handles version management, conflict resolution, environment variable injection, and triggers Coder's built-in Terraform validation.

**Location:** `config/coder/scripts/push-template-versioned.sh`

**Features:**
- Auto-increments version on conflicts
- Retries up to 5 times
- Updates `.template_versions.json`
- Prevents manual version conflicts
- Detects the active Git ref (tag > main > branch) and substitutes module `?ref=` query params inside the staging directory only
- Overlays shared parameter files from `template-modules/params/` unless the template ships its own override
- **Injects BASE_DOMAIN from .env into templates** (via sed)
- **Injects HOST_IP defaults for host binding variables**
- **Passes TF_VAR_base_domain to Terraform** (for parameter descriptions)
- Coder automatically validates Terraform during push

**How BASE_DOMAIN Works:**

The script uses a two-step approach to make templates portable:

1. **Build-time injection (sed)**: Replaces `default = "localhost"` in `variables.tf` with actual domain from `.env`
2. **Runtime environment (TF_VAR)**: Passes domain to Terraform for string interpolation in parameter descriptions

This allows the same template code to work on any domain without hardcoded values.

**Usage:**

```bash
# Basic usage - automatically injects BASE_DOMAIN from .env
./config/coder/scripts/push-template-versioned.sh docker-template

# What it does:
# 1. Loads .env file to get BASE_DOMAIN
# 2. Reads current version from .template_versions.json
# 3. Copies template to temp directory
# 4. Overlays shared parameter files (if the template doesn't provide an override)
# 5. Rewrites git module `?ref=` values to the detected ref, updates base_domain/host_ip defaults
# 6. Copies modified template to Coder container
# 7. Passes -e TF_VAR_base_domain to docker exec for Terraform interpolation
# 8. Pushes template with that version
# 9. If "already exists" error, increments and retries
# 10. Updates .template_versions.json on success
```

**Environment Variable Loading:**

The script safely loads variables from `.env`:

```bash
# Skips comments and blank lines
# Only exports valid variable assignments (KEY=VALUE)
# Handles complex values with special characters
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        export "$line"
    fi
done < "$ENV_FILE"
```

**BASE_DOMAIN Injection:**

```bash
# Function that runs during template staging
substitute_base_domain() {
    local domain="${BASE_DOMAIN:-localhost}"
    # Find variables.tf with base_domain variable
    # Replace: default = "localhost" → default = "weekendcodeproject.dev"
    sed -i "/variable \"base_domain\"/,/^}/ s|default[[:space:]]*=[[:space:]]*\"[^\"]*\"|default = \"$domain\"|" "$file"
}

# Passed to Terraform during template push
docker exec -e TF_VAR_base_domain=${BASE_DOMAIN:-localhost} coder ...
```

**Why Both sed AND TF_VAR?**

- **sed substitution**: Changes the default value in git-committed files → Users see correct domain in UI
- **TF_VAR environment**: Allows `${var.base_domain}` interpolation in parameter descriptions → Shows actual domain in help text
- **docker exec doesn't inherit**: Container environment variables don't pass to `docker exec` commands, must be explicit

**Important:** The git repository stores `default = "localhost"` as a placeholder. The actual domain is injected during every push from your `.env` file.

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

## Shared Parameter Glue

### Overview

Shared parameter files are Terraform snippets (named `*-params.tf`) that define consistent `data "coder_parameter"` blocks plus their companion module calls. They are kept outside of individual templates so that we can fix flickering bugs once and have every template benefit automatically.

**Location:** `config/coder/template-modules/params/`

**Pattern:** During the push process, any shared `*-params.tf` file that does **not** already exist inside the template directory is copied into the temp staging folder. If a template needs to override the defaults, simply add a file with the same name locally; the push script will respect the local copy.

### How It Works

```bash
# During template push:
overlay_shared_params() {
  # Copy *-params.tf files from template-modules/params/
  # into the template's staging directory (unless overridden)
}
```

### Shared Parameter Files Available

- `agent-params.tf`: Core agent metadata aggregation and startup script wiring
- `docker-params.tf`: Docker-in-Docker toggle and module invocation
- `git-params.tf`: Git identity + cloning switches
- `metadata-params.tf`: Resource metadata for UI display
- `setup-server-params.tf`: Optional HTTP server port exposure
- `ssh-params.tf`: SSH toggle, password, and port configuration
- `traefik-params.tf`: Preview link + routing labels
- Additional experimental params live beside these files for iterative testing

### Base Domain System

The base domain system makes templates portable across different installations:

**In Git (placeholder):**
```hcl
# templates/docker-template/variables.tf
variable "base_domain" {
  type    = string
  default = "localhost"  # Placeholder - replaced during push
}
```

**During Push (injected):**
```bash
# .env file
BASE_DOMAIN=weekendcodeproject.dev

# Push script replaces placeholder
sed -i 's/default = "localhost"/default = "weekendcodeproject.dev"/'
```

**In UI (user sees):**
```hcl
# Shared module creates conditional parameter
data "coder_parameter" "traefik_base_domain" {
  count   = preview_mode == "traefik" ? 1 : 0
  name    = "traefik_base_domain"
  default = var.base_domain  # Shows weekendcodeproject.dev
}
```

**Why This Approach:**

1. **No hardcoded domains** - Works on any installation
2. **Single source of truth** - Change `.env`, re-push templates
3. **User override** - Optional parameter lets users customize per-workspace
4. **Git-friendly** - No domain-specific values committed to git

### Conditional Parameters

Show parameters only when relevant:

```hcl
# Show base domain input only when Traefik mode selected
data "coder_parameter" "traefik_base_domain" {
  count        = data.coder_parameter.preview_link_mode.value == "traefik" ? 1 : 0
  display_name = "Base Domain"
  default      = var.base_domain
  order        = 24
}

# Show custom URL input only when Custom mode selected  
data "coder_parameter" "custom_preview_url" {
  count = data.coder_parameter.preview_link_mode.value == "custom" ? 1 : 0
  order = 25
}
```

Access conditional parameters safely:

```hcl
module "preview_link" {
  base_domain = try(
    data.coder_parameter.traefik_base_domain[0].value,  # User override
    local.actual_base_domain                             # Default from template
  )
}
```

### Template-Specific Overrides

If a template needs custom behavior:

```bash
# Create module-preview-link.tf in template directory
# It will NOT be overwritten by shared version
```

This allows per-template customization while keeping most logic shared.

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

> **Note:** You do **NOT** need to run `terraform fmt` or `terraform validate` manually. 
> Coder automatically validates and processes all Terraform files when you push a template.
> The push command will fail with clear error messages if there are any Terraform syntax errors.

**Testing Workflow:**

1. **Push template:**
```bash
./config/coder/scripts/push-template-versioned.sh docker-template
```

2. **Monitor push output:**
   - Coder will automatically validate Terraform syntax
   - Check for any errors in the output
   - If successful, template is immediately available

3. **Create test workspace:**
   - Go to Coder UI: http://coder:7080
   - Create new workspace from template
   - Monitor startup logs in the Coder UI

**Optional: Local Terraform validation** (only if you want to check syntax before pushing):
```bash
cd config/coder/templates/docker-template
terraform fmt    # Format files
terraform init   # Initialize (downloads providers)
terraform validate  # Validate syntax
```

However, this requires Terraform installed locally and is **not necessary** for normal development.

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

**Issue: Base domain showing "localhost" instead of actual domain**
```
Parameter shows: localhost
Expected: weekendcodeproject.dev
```
**Solution:**
- Check `.env` file has `BASE_DOMAIN=your-domain.com`
- Verify push script is loading .env (check logs for "Loading environment")
- Delete old workspaces and create new ones from latest template version
- Old workspaces cache parameter values - use `coder delete workspace --orphan` for broken old versions

**Issue: Can't delete old workspace - Terraform errors**
```
Error: Missing required argument
Error: Unsupported argument
```
**Solution:**
- Template structure changed between versions
- Use `--orphan` flag to skip Terraform: `coder delete workspace --yes --orphan`
- This deletes workspace metadata without running Terraform plan

**Issue: TF_VAR environment variables not working**
```
Parameter shows default value instead of TF_VAR value
```
**Solution:**
- `docker exec` doesn't inherit container environment variables
- Must explicitly pass: `docker exec -e TF_VAR_name=value`
- Push script handles this automatically for `TF_VAR_base_domain`

**Issue: Parameter description shows `${var.base_domain}` literally**
```
Description text: "Domain is: ${var.base_domain}"
Expected: "Domain is: weekendcodeproject.dev"
```
**Solution:**
- TF_VAR must be passed during template push for Terraform interpolation
- Check push script passes `-e TF_VAR_base_domain=${BASE_DOMAIN}`
- Terraform evaluates `${}` expressions at template parse time, not workspace create time

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

### Module Execution Order

**Critical:** The order that modules run in the workspace startup is determined by **the order you concatenate their scripts** in the agent's `startup_script`, NOT by Terraform dependencies.

**How it works:**

```hcl
module "agent" {
  source = "..."
  
  startup_script = join("\n", [
    "#!/bin/bash",
    "set -e",
    module.init_shell.setup_script,    # ← Runs FIRST
    module.git_identity.setup_script,  # ← Runs SECOND
    module.docker.setup_script,        # ← Runs THIRD
    module.ssh.setup_script,           # ← Runs FOURTH
  ])
}
```

This creates a **single bash script** that executes sequentially from top to bottom.

**Best practices:**

1. **init_shell MUST be first** - Creates workspace directories that other modules need
2. **git_identity before git_integration** - Sets up Git config before cloning repos
3. **docker setup before docker-dependent modules** - Installs Docker before trying to use it
4. **ssh setup near the end** - SSH server doesn't need to block other initialization

**What NOT to do:**

```hcl
# ❌ BAD - Using coder_script resources in modules
resource "coder_script" "my_script" {
  agent_id     = var.agent_id
  run_on_start = true
  script       = "..."  # These run in PARALLEL with no guaranteed order!
}
```

**Why Terraform dependencies don't control runtime order:**

- `depends_on` ensures Terraform evaluates modules in order at **plan time**
- It does NOT control when bash scripts run at **workspace startup**
- The startup script is one long bash file that runs sequentially

**Verification:**

To check execution order in a running workspace:
```bash
# View the actual startup script
cat /tmp/coder-startup-script.log

# Or check the agent logs
journalctl -u coder-agent
```

### Version Control

1. **Commit module changes first:**
```bash
git add config/coder/template-modules/modules/my-module/
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
mkdir -p config/coder/template-modules/modules/MODULE_NAME
cd config/coder/template-modules/modules/MODULE_NAME
# Create main.tf, variables.tf, README.md
git add .
git commit -m "feat: add MODULE_NAME"
git push origin v0.1.0
```

### Add Module to Template
```hcl
module "MODULE_NAME" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/MODULE_NAME?ref=v0.1.0"
  
  agent_id = module.agent.agent_id
  # ... other variables
}
```

### Push Template
```bash
# Coder automatically validates Terraform when pushing
./config/coder/scripts/push-template-versioned.sh docker-template
```

### Test Workspace
1. Open Coder UI: http://coder:7080
2. Create new workspace from template
3. Monitor startup logs in Coder UI
4. Verify functionality

### Common Workflow
```bash
# 1. Make changes to template or modules
vim config/coder/templates/docker-template/main.tf

# 2. Commit changes to git
git add .
git commit -m "feat: enable init-shell module"
git push origin v0.1.0

# 3. Push to Coder (validates Terraform automatically)
./config/coder/scripts/push-template-versioned.sh docker-template

# 4. Test in Coder UI
# No local Terraform commands needed!
```

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
