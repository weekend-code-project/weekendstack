# Test Module Template (POC)

## Purpose

This is a **proof-of-concept template** to test whether Coder templates can reference external Terraform modules using standard Terraform module syntax.

## What Makes This Different

### Current Approach (modular-docker)
```
modular-docker/main.tf
  ├── (modules get bundled/copied during push)
  └── All .tf files merged into one root module
```

### This POC Approach
```
test-module-template/main.tf
  └── module "workspace" {
        source = "../test-modules/docker-workspace"
      }
```

## Testing Steps

### 1. Initialize Terraform
```bash
cd /mnt/workspace/wcp-coder/config/coder/templates/test-module-template
terraform init
```

**Expected:** Terraform should find the module at `../test-modules/docker-workspace`

### 2. Validate Configuration
```bash
terraform validate
```

**Expected:** No errors (though Coder-specific resources won't be fully validated)

### 3. Push to Coder
```bash
coder templates push test-poc --directory .
```

**Expected:** Template uploads successfully

### 4. Create Workspace
```bash
coder create test-workspace --template test-poc
```

**Expected:** Workspace provisions and starts

## Success Criteria

- ✅ `terraform init` finds the module
- ✅ No errors during push
- ✅ Template appears in Coder UI
- ✅ Can create workspace from template
- ✅ Workspace container starts
- ✅ VS Code accessible

## What This Proves

If successful, this proves:
1. Coder supports standard Terraform module references
2. We can refactor existing flat modules into proper modules
3. No custom bundling logic needed in push script
4. Templates become cleaner and more maintainable

## What's Included

This minimal template includes:
- Basic Docker workspace (agent + container)
- Persistent home volume
- VS Code Server (code-server)
- Git identity configuration
- Resource monitoring
- Dynamic parameters for image/CPU/memory

## Next Steps After POC

If this works:
1. Refactor existing `modules/*.tf` into proper modules by domain
2. Create module structure:
   - `modules/base/` - Core agent, container, volume
   - `modules/git/` - Git clone, identity, SSH
   - `modules/node/` - Node installation, node_modules persistence
   - `modules/traefik/` - Routing and authentication
3. Update `modular-docker` to use module composition
4. Remove bundling from push script
