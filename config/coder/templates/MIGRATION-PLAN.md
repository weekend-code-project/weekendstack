# Migration Plan: Git-Based Module System

## Overview
Migrating from bundled flat module files to git-based Terraform modules that Coder can pull directly from the GitHub repository.

## Current State
- **Repository**: `weekend-code-project/weekendstack`
- **Branch**: `v0.1.0`
- **Current System**: Flat `.tf` files in `modules/` directory, bundled by `push-templates.sh`
- **Target System**: Proper Terraform modules in git, referenced via `git::https://` syntax

## Module Inventory (23 modules)

### Core Infrastructure (Priority 1)
1. ✅ `coder-agent.tf` - Agent configuration and startup orchestration
2. ✅ `docker-resources.tf` - Docker volume and container
3. ✅ `init-shell.tf` - Home directory initialization
4. ✅ `code-server.tf` - VS Code Server app

### Git Integration (Priority 2)
5. ✅ `git-identity.tf` - Git configuration
6. ✅ `git-params.tf` - Git parameters
7. ✅ `git-clone.tf` - Repository cloning

### SSH Integration (Priority 2)
8. ✅ `ssh-params.tf` - SSH parameters
9. ✅ `ssh-copy.tf` - SSH key copying
10. ✅ `ssh-setup.tf` - SSH configuration

### Docker-in-Docker (Priority 3)
11. ✅ `install-docker.tf` - Docker engine installation
12. ✅ `docker-config.tf` - Docker daemon configuration

### Node.js (Priority 3)
13. ✅ `node-params.tf` - Node parameters
14. ✅ `install-node.tf` - Node.js installation
15. ✅ `node-modules-persistence.tf` - node_modules persistence

### Traefik Integration (Priority 4)
16. ✅ `traefik-routing.tf` - Traefik routing labels
17. ✅ `traefik-auth.tf` - Traefik authentication

### Additional Tools (Priority 4)
18. ✅ `install-github-cli.tf` - GitHub CLI installation
19. ✅ `setup-server.tf` - Default web server
20. ✅ `preview-app.tf` - Preview app configuration

### Utilities (Priority 5)
21. ✅ `metadata-blocks.tf` - Resource monitoring
22. ✅ `validation.tf` - Workspace validation

### Sub-modules
23. ✅ `docker-workspace-git/` - Already a proper module (reference implementation)

## Migration Strategy

### Phase 1: Directory Structure Setup
```
config/coder/templates/
├── git-modules/                    # NEW: Git-based modules
│   ├── agent/                      # Core agent module
│   ├── docker-workspace/           # Docker resources module
│   ├── git-integration/            # Git setup module
│   ├── ssh-integration/            # SSH setup module
│   ├── docker-in-docker/           # Docker installation
│   ├── nodejs/                     # Node.js setup
│   ├── traefik/                    # Traefik integration
│   ├── tools/                      # Additional tools
│   └── utilities/                  # Metadata, validation
├── v0.1.0-test/                    # NEW: Test template
└── modular-docker-v2/              # NEW: Final template
```

### Phase 2: Module Conversion Pattern
Each module follows this structure:
```
git-modules/<module-name>/
├── main.tf           # Resources and logic
├── variables.tf      # Inputs
├── outputs.tf        # Outputs (if any)
└── README.md         # Documentation
```

### Phase 3: Incremental Migration & Testing
1. **Create test template** (`v0.1.0-test`)
2. **Migrate one module at a time**:
   - Convert to proper module structure
   - Add to test template
   - Push template to Coder
   - Create test workspace
   - Verify functionality
3. **Move to next module**
4. **Repeat until all modules migrated**

### Phase 4: Final Template Creation
Once all modules tested individually:
1. Create `modular-docker-v2` template
2. Include all migrated modules
3. Comprehensive testing
4. Document usage

## Module Source Syntax

Git-based modules will be referenced as:
```hcl
module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/agent?ref=v0.1.0"
  
  workspace_name = data.coder_workspace.me.name
  # ... other variables
}
```

## Benefits of Git-Based Approach

1. **Version Control**: Pin to specific branches/tags
2. **No Bundling**: Remove custom push script logic
3. **Reusability**: Share modules across templates
4. **Standard Practice**: Follow Terraform conventions
5. **Independent Updates**: Update modules without touching templates
6. **Better Testing**: Test modules in isolation
7. **Documentation**: Clear interfaces via variables/outputs

## Testing Workflow

```bash
# 1. Commit changes to git
git add config/coder/templates/git-modules/
git commit -m "Add <module-name> git-based module"
git push origin v0.1.0

# 2. Update test template to use new module
# Edit v0.1.0-test/main.tf

# 3. Push to Coder
cd config/coder/templates/v0.1.0-test
coder templates push v0-1-0-test --directory .

# 4. Test workspace
coder create test-workspace --template v0-1-0-test
coder ssh test-workspace
# Verify functionality

# 5. If successful, move to next module
# If issues, debug and iterate
```

## Module Dependencies

Key dependencies to handle:

```
coder-agent (core)
  ├── uses: init-shell, git-identity, ssh-copy, install-docker, etc.
  └── provides: agent resource for other modules

docker-resources
  ├── depends on: coder-agent
  └── provides: container and volume

code-server
  ├── depends on: coder-agent
  └── provides: VS Code app

traefik-routing
  ├── depends on: nothing
  └── provides: labels for docker-resources
```

## Risk Mitigation

- ✅ **No changes to existing setup** until migration complete
- ✅ **Incremental approach** - test each module individually
- ✅ **Git versioning** - can rollback at any point
- ✅ **Separate test template** - won't affect current templates
- ✅ **Branch isolation** - working in v0.1.0 branch

## Success Criteria

- [ ] All 23 modules converted to git-based format
- [ ] Test template successfully creates workspaces
- [ ] All features working (Docker, Git, SSH, Node, Traefik)
- [ ] Documentation complete
- [ ] Final template pushed to Coder
- [ ] Old bundling script no longer needed

## Timeline

- **Phase 1**: ~30 minutes (directory structure)
- **Phase 2-3**: ~3-4 hours (module conversion and testing)
- **Phase 4**: ~1 hour (final template and validation)
- **Total**: ~4-5 hours

## Next Steps

1. Create `git-modules/` directory structure
2. Start with simplest module (git-identity)
3. Test early and often
4. Document any issues encountered
5. Iterate until all modules migrated
