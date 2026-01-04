# Debug Template - Flickering Investigation

## Purpose
This template is designed to systematically identify which module or Terraform pattern causes the parameter flickering bug in Coder's settings UI.

## Symptoms
- SSH checkbox toggles on/off rapidly
- Server startup command field toggles between custom command and default
- Other parameters may flash or change unexpectedly

## Hypothesis
The flickering is caused by one or more of:
1. **Conditional module loading** - `count = parameter.value ? 1 : 0` pattern
2. **Parameter styling.disabled** - Dynamic disabled state based on other parameters
3. **Circular dependencies** - Modules outputting metadata that feeds back into parameters

## Testing Phases

### Phase 0: Baseline ✅ Expected: NO FLICKERING
- Minimal template with zero user parameters
- Just container + agent + code-server
- **Files**: main.tf, variables.tf only
- **Purpose**: Establish clean baseline

### Phase 1: Static Modules (Low Risk)
- Add init-shell, metadata (basic), docker (boolean toggle)
- **Files**: agent-params.tf, metadata-params.tf, docker-params.tf
- **Purpose**: Test simple parameters without conditionals
- **Expected**: NO flickering - these are simple boolean/multi-select

### Phase 2: SSH Module (HIGH RISK ⚠️)
- Add SSH with **shared version** (has `count = ssh_enable ? 1 : 0`)
- **Files**: ssh-params.tf (copy from template-modules/params/)
- **Purpose**: Test if conditional module count causes flickering
- **Expected**: Flickering LIKELY starts here

### Phase 3: Setup Server Module (HIGH RISK ⚠️)
- Add setup-server with `styling.disabled` on startup_command
- **Files**: setup-server-params.tf (copy from template-modules/params/)
- **Purpose**: Test if disabled styling causes flickering
- **Expected**: If not in Phase 2, flickering LIKELY starts here

### Phase 4: Git Modules (Medium Risk)
- Add git_identity, git_integration, github_cli, gitea_cli
- **Files**: git-params.tf
- **Purpose**: Test conditional git modules
- **Expected**: May contribute to flickering if has circular deps

### Phase 5: Advanced Modules (Medium Risk)
- Add node-tooling, node-modules-persistence, preview-link
- **Files**: node-params.tf, node-modules-persistence-params.tf, preview-params.tf
- **Purpose**: Complete feature parity with vite-template
- **Expected**: Additional flickering if metadata circular dependency exists

## Testing Procedure

For each phase:
1. Add the phase's param files to debug-template/
2. Update main.tf with phase marker comment
3. Push template: `./scripts/push-template-versioned.sh debug-template`
4. Create a new workspace from the template
5. Open Settings → Parameters
6. **WATCH FOR**: Checkboxes toggling, text fields changing values
7. If flickering appears, the LAST ADDED module is the culprit
8. Document findings below

## Findings Log

### Phase 0 Test Results
- Date:
- Tester:
- Flickering: YES / NO
- Notes:

### Phase 1 Test Results
- Date:
- Tester:
- Flickering: YES / NO
- Notes:

### Phase 2 Test Results (SSH Module)
- Date:
- Tester:
- Flickering: YES / NO
- SSH checkbox stable: YES / NO
- SSH password field stable: YES / NO
- Notes:

### Phase 3 Test Results (Setup Server Module)
- Date:
- Tester:
- Flickering: YES / NO
- Use custom command toggle stable: YES / NO
- Startup command field stable: YES / NO
- Notes:

### Phase 4 Test Results (Git Modules)
- Date:
- Tester:
- Flickering: YES / NO
- Notes:

### Phase 5 Test Results (Advanced Modules)
- Date:
- Tester:
- Flickering: YES / NO
- Notes:

## Root Cause (To Be Determined)

Once identified, document here:
- **Culprit Module**:
- **Specific Terraform Pattern**:
- **Why it causes flickering**:
- **Proposed Fix**:

## Fix Validation

After implementing fix:
- [ ] Fix applied to debug-template
- [ ] Flickering eliminated in debug-template
- [ ] Fix applied to shared params (template-modules/params/)
- [ ] Fix applied to node-template
- [ ] Fix applied to vite-template
- [ ] Fix applied to wordpress-template
- [ ] All templates tested and verified
