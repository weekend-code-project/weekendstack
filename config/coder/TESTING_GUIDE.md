# 🧪 Coder Template Flickering Debug Guide

## ⚠️ Important: Cleanup Complete

**Date**: 2026-01-04  
**Branch**: `cleanup/template-system-standardization`

Before proceeding with flickering tests, we completed a system-wide cleanup:

- ✅ All module paths standardized to `template-modules/modules`
- ✅ All `?ref=` patterns use `PLACEHOLDER` (substituted by push script)
- ✅ All module READMEs updated with correct examples
- ✅ Overlay precedence documented in `template-modules/params/README.md`
- ✅ Archive directory documented with clear "DO NOT USE" warnings
- ✅ Validation script created: `scripts/validate-module-refs.sh`

This ensures consistent, reliable testing going forward.

---

## Quick Start

We've created a systematic testing framework to identify which Terraform module/pattern causes the parameter flickering bug in Coder's UI.

### Current Status

- ✅ **Phase 0 (Baseline)** - PUSHED as debug-template v1
  - Zero user parameters
  - Minimal agent + code-server
  - **Expected**: NO flickering

### Next Steps

1. **Test Phase 0** (Manual - YOU DO THIS)
   - Open Coder UI
   - Create workspace from `debug-template`
   - Go to Settings → Parameters tab
   - Watch for any flickering/re-rendering
   - Document results in [README.md](templates/debug-template/README.md)

2. **Move to Phase 1** (After Phase 0 confirmed clean)
   - Run: `./scripts/test-debug-phases.sh 1`
   - Adds simple parameters (metadata multi-select, docker boolean)
   - Test again for flickering

3. **Continue through phases** until flickering appears
   - Phase 2: SSH module (HIGH RISK - conditional count)
   - Phase 3: Setup Server (HIGH RISK - styling.disabled)
   - Phase 4: Git modules
   - Phase 5: Advanced modules

## The Problem

### Symptoms
- SSH checkbox toggles on/off rapidly
- Server startup command field toggles between values
- Other parameters may flash or re-render unexpectedly

### Root Cause (Hypothesis)
One or more of these Terraform patterns:

1. **Conditional Module Loading**
   ```hcl
   module "ssh" {
     count = data.coder_parameter.ssh_enable.value ? 1 : 0
     ...
   }
   ```
   This forces Terraform to re-evaluate the entire plan when the parameter changes.

2. **Dynamic Parameter Styling**
   ```hcl
   data "coder_parameter" "startup_command" {
     styling = jsonencode({
       disabled = !data.coder_parameter.use_custom_command.value
     })
   }
   ```
   This creates a dependency loop that triggers re-renders.

3. **Circular Dependencies**
   ```hcl
   # Agent module outputs metadata
   module "agent" {
     metadata_blocks = module.metadata.metadata_blocks
   }
   
   # Metadata module references modules that haven't loaded yet
   module "metadata" {
     custom_blocks = [module.ssh[0].metadata_blocks]  # ssh may not exist!
   }
   ```

## Testing Framework

### Phase Progression

| Phase | Focus | Risk Level | Expected Outcome |
|-------|-------|------------|------------------|
| 0 | Baseline (zero params) | ✅ None | NO flickering |
| 1 | Static modules (simple boolean/multi-select) | ⚠️ Low | NO flickering |
| 2 | SSH module (conditional count) | 🔴 **HIGH** | **Flickering likely starts** |
| 3 | Setup Server (styling.disabled) | 🔴 **HIGH** | Flickering if not in Phase 2 |
| 4 | Git modules (conditional count) | ⚠️ Medium | May contribute |
| 5 | Advanced (node, preview) | ⚠️ Medium | May contribute |

### Scripts Available

#### `./scripts/test-debug-phases.sh <phase>`
Pushes the debug template for a specific phase with helpful instructions.

**Example:**
```bash
./scripts/test-debug-phases.sh 0    # Phase 0 (baseline)
./scripts/test-debug-phases.sh 2    # Phase 2 (SSH - high risk)
```

## Manual Testing Procedure

For EACH phase:

1. **Push the template**
   ```bash
   cd /opt/stacks/weekendstack
   ./config/coder/scripts/test-debug-phases.sh <phase-number>
   ```

2. **Create/Update workspace**
   - Go to Coder UI (https://coder.weekendcodeproject.dev)
   - Create new workspace from `debug-template` OR
   - Update existing debug workspace to latest version

3. **Test in Settings UI**
   - Wait for workspace to start
   - Click Settings icon (gear)
   - Go to **Parameters** tab
   - **WATCH CAREFULLY** for:
     - ✗ Checkboxes toggling on/off repeatedly
     - ✗ Text fields changing values
     - ✗ Dropdowns or other inputs re-rendering
     - ✗ Visual flickering

4. **Document Results**
   - Edit `templates/debug-template/README.md`
   - Find "Phase X Test Results" section
   - Fill in:
     - Date
     - Flickering: YES / NO
     - Specific observations
     - Notes on which fields flicker

5. **If flickering appears:**
   - ⚠️ **STOP** - Don't proceed to next phase
   - The LAST ADDED module is the culprit
   - Document findings thoroughly
   - Analyze that module's Terraform code
   - Create a fix

6. **If NO flickering:**
   - ✅ Move to next phase
   - Continue testing

## Phase Details

### Phase 0: Baseline ✅ COMPLETE
**Files:** main.tf, variables.tf, placeholder param files

**What's included:**
- Basic workspace container
- Inline coder_agent with hardcoded metadata
- code-server module (zero parameters)
- NO user parameters at all

**Purpose:** Establish clean baseline

**Status:** PUSHED as v1

**Your action:** Test it!

---

### Phase 1: Static Modules (Pending)
**Files to add:**
- `metadata-params.tf` - Multi-select parameter
- `docker-params.tf` - Simple boolean toggle

**What's being tested:**
- Multi-select parameter (list of metadata blocks)
- Boolean parameter (enable Docker)
- NO conditional module loading yet

**Expected:** NO flickering (simple parameters don't cause issues)

**How to set up:**
Replace placeholder files with Phase 1 configs (we'll provide these)

---

### Phase 2: SSH Module 🔴 HIGH RISK
**File to add:**
- `ssh-params.tf` - Copy from `template-modules/params/ssh-params.tf`

**What's being tested:**
```hcl
module "ssh" {
  count = data.coder_parameter.ssh_enable.value ? 1 : 0
  ...
}
```

**Why it's risky:**
- Conditional module loading based on parameter
- Terraform must re-plan when parameter changes
- This is THE most likely culprit

**Expected:** **Flickering LIKELY starts here**

**What to watch:**
- SSH Enable checkbox - Does it toggle?
- SSH Password field - Does it appear/disappear?

---

### Phase 3: Setup Server Module 🔴 HIGH RISK
**File to add:**
- `setup-server-params.tf` - Copy from `template-modules/params/setup-server-params.tf`

**What's being tested:**
```hcl
data "coder_parameter" "startup_command" {
  styling = jsonencode({
    disabled = !data.coder_parameter.use_custom_command.value
  })
}
```

**Why it's risky:**
- Parameter with dynamic disabled state
- Creates dependency on another parameter's value
- May trigger re-evaluation loop

**Expected:** Flickering likely if not in Phase 2

**What to watch:**
- "Use Custom Command" toggle
- "Startup Command" text field - Does it change values?

---

### Phase 4 & 5: Additional Modules ⚠️ Medium Risk
Git modules, node modules, preview-link, etc.

May contribute to flickering but less likely to be primary cause.

## What To Do When You Find The Culprit

1. **Document the exact Terraform pattern** that causes it
2. **Analyze why** it causes Terraform to re-evaluate
3. **Design a fix** - Examples:
   - Remove `count` conditional, always load module
   - Remove `styling.disabled`, make field always visible
   - Restructure dependencies to avoid circular refs
4. **Test the fix** in debug-template
5. **Apply fix** to all templates and shared params
6. **Verify** fix works across all templates

## Known Workarounds (Already Tried)

Looking at `node-template` and `vite-template`, you've already tried:

### SSH Module Workaround
```hcl
# OVERRIDE NOTE: Removes conditional patterns to prevent UI flickering

# Module: SSH (ALWAYS loaded - no count conditional to prevent flickering)
module "ssh" {
  # No count! Always loads
  source = "..."
  ssh_enable_default = data.coder_parameter.ssh_enable.value
}
```

**Result:** Does this actually fix it? Let's test systematically.

### Setup Server Workaround
```hcl
# OVERRIDE NOTE: This file overrides the shared setup-server-params.tf
# to provide a Vite-specific default startup command.

# Removed styling.disabled from startup_command parameter
```

**Result:** Does this fix it? Let's verify.

### Metadata Workaround
```hcl
# OVERRIDE NOTE: Simplified metadata to isolate parameter flickering
# Only includes basic built-in metadata options, no custom module metadata

locals {
  all_custom_metadata = []  # Empty - no references to conditional modules
}
```

**Result:** Prevents circular dependencies, but does it eliminate ALL flickering?

## Questions To Answer

Through this systematic testing, we'll definitively answer:

1. ✅ Does Phase 0 (zero params) have NO flickering?
2. ❓ Does Phase 1 (simple params) introduce flickering?
3. ❓ Does Phase 2 (SSH with count) introduce flickering?
4. ❓ Does Phase 3 (setup-server with styling.disabled) introduce flickering?
5. ❓ Can we reproduce the flickering in isolation?
6. ❓ Does removing `count` fix SSH flickering?
7. ❓ Does removing `styling.disabled` fix server command flickering?
8. ❓ Can we create a PERMANENT fix that works for all templates?

## Success Criteria

✅ We'll know we've succeeded when:
1. We can reliably reproduce the flickering in debug-template
2. We identify the exact Terraform pattern causing it
3. We implement a fix that eliminates flickering
4. The fix works across all templates (node, vite, wordpress)
5. We document the pattern to avoid in future modules

## Ready To Test?

Phase 0 is pushed and waiting for you!

```bash
# Step 1: Create workspace from debug-template in Coder UI
# Step 2: Go to Settings → Parameters
# Step 3: Watch for flickering
# Step 4: Document in templates/debug-template/README.md
# Step 5: Report back - flickering YES or NO?
```

Once you confirm Phase 0 results, I'll prepare Phase 1 files for you to test next.

---

**Questions? Issues?** Update the README.md with your findings and let's iterate!
