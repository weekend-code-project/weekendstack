# Test Git Module Template (POC)

## Purpose

Test whether Coder templates can reference Terraform modules from **Git sources** (specifically from the same repository).

## Module Source

```hcl
module "workspace" {
  source = "git::https://github.com/jessefreeman/wcp-coder.git//config/coder/templates/modules/docker-workspace-git?ref=work/cleanup-templates-20251025"
  # ...
}
```

## Key Differences from Previous POC

| Aspect | Local Path POC | Git Source POC |
|--------|----------------|----------------|
| **Source** | `source = "../test-modules/docker-workspace"` | `source = "git::https://github.com/..."` |
| **Resolution** | Relative filesystem path | Git clone + subdirectory |
| **Coder Support** | ❌ Fails (path isolation) | ✅ Should work (standard Terraform) |
| **Version Control** | N/A | `?ref=branch` or `?ref=v1.0.0` |

## Testing Steps

### 1. Commit and Push Module
```bash
cd /mnt/workspace/wcp-coder
git add config/coder/templates/modules/docker-workspace-git
git commit -m "Add docker-workspace-git module for POC"
git push origin work/cleanup-templates-20251025
```

### 2. Push Template to Coder
```bash
# From inside Coder container
docker exec coder coder templates push test-git-poc --directory /tmp/test-git-module-template --yes
```

### 3. Create Test Workspace
```bash
docker exec coder coder create my-git-test --template test-git-poc
```

## Repository Access

**Question: Does the repo need to be public?**

- ✅ **If public**: Works immediately, no authentication needed
- ⚠️ **If private**: Coder server needs Git credentials (SSH key or token)

For POC testing, **making the repo temporarily public** is easiest.

## Expected Outcome

If successful:
- ✅ `terraform init` fetches module from Git
- ✅ Template pushes without errors
- ✅ Can create workspace
- ✅ Workspace provisions correctly

This proves Git-based modules work with Coder!

## After POC Success

Can then:
1. Refactor other modules to proper structure
2. Reference them via Git in templates
3. Use version tags (`?ref=v1.0.0`) for stability
4. Keep everything in same repo or split as needed
