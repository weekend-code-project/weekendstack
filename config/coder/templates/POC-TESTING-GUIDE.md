# POC Testing Guide: Module-Based Templates

## 🎯 What We Created

A complete proof-of-concept with:
1. **Proper Terraform module** at `test-modules/docker-workspace/`
2. **Template that references it** at `test-module-template/`

## 📁 Structure

```
config/coder/templates/
├── test-modules/                          # NEW: Module repository
│   └── docker-workspace/                  # NEW: Proper Terraform module
│       ├── main.tf                        # Module implementation
│       ├── variables.tf                   # Module inputs
│       ├── outputs.tf                     # Module outputs
│       └── README.md                      # Module documentation
│
└── test-module-template/                  # NEW: Template using module
    ├── main.tf                            # References module via source = "../test-modules/..."
    └── README.md                          # Testing instructions
```

## 🧪 Testing Steps

### Step 1: Validate Structure
```bash
cd /mnt/workspace/wcp-coder/config/coder/templates/test-module-template
terraform init
```

**Expected:** Terraform should find and initialize the module at `../test-modules/docker-workspace`

### Step 2: Push to Coder
```bash
cd /mnt/workspace/wcp-coder/config/coder/templates/test-module-template
coder templates push test-poc --directory .
```

**What happens:**
- Terraform runs `init` to resolve the module
- Module source `../test-modules/docker-workspace` is followed
- Template is bundled and uploaded

### Step 3: Create Test Workspace
```bash
coder create my-test-workspace --template test-poc
```

### Step 4: Verify Workspace
```bash
coder ssh my-test-workspace
```

Check:
- ✅ Workspace starts
- ✅ Docker container running
- ✅ VS Code accessible
- ✅ Git configured

## 🔍 What This Tests

### ✅ If Successful
Proves that:
1. Coder supports standard Terraform module references
2. No custom bundling logic needed
3. Modules can be organized separately from templates
4. Can refactor existing flat modules into proper modules

### ❌ If It Fails

**Scenario A: Module not found during init**
```
Error: Module not found
```
→ Coder doesn't follow relative module paths
→ Need to keep bundling approach or use remote module sources

**Scenario B: Module found but push fails**
```
Error: Failed to upload template
```
→ Coder's push process may not handle modules correctly
→ Check Coder logs for details

**Scenario C: Push succeeds but workspace fails**
```
Error: Resource provisioning failed
```
→ Bug in module logic (not in module reference itself)
→ Check workspace logs: `coder logs my-test-workspace`

## 📊 Comparison: Current vs POC

### Current Setup (modular-docker)
```hcl
# main.tf has nothing
# Modules are bundled during push:
# - push-templates.sh copies modules/*.tf into template root
# - All .tf files become one flat root module
```

**Pros:**
- ✅ Works today
- ✅ Simple mental model

**Cons:**
- ❌ Not true modules (just file copying)
- ❌ Duplication across templates
- ❌ Custom push script logic
- ❌ Hard to version modules separately

### POC Setup (test-module-template)
```hcl
# main.tf
module "workspace" {
  source = "../test-modules/docker-workspace"
  
  workspace_name = data.coder_workspace.me.name
  # ... pass other variables
}
```

**Pros:**
- ✅ True Terraform modules
- ✅ Explicit inputs/outputs
- ✅ No bundling needed
- ✅ Can version modules independently
- ✅ Standard Terraform practices

**Cons:**
- ⚠️ Requires refactoring existing modules
- ⚠️ More upfront work

## 🎬 Next Steps Based on Results

### If POC Succeeds ✅

1. **Plan module structure:**
   ```
   test-modules/
   ├── base/          # Agent, container, volume
   ├── git/           # Git clone, identity, SSH
   ├── docker/        # Docker-in-Docker setup
   ├── node/          # Node installation & config
   └── traefik/       # Routing & authentication
   ```

2. **Refactor one module at a time:**
   - Start with simplest (e.g., `git`)
   - Convert to proper module with variables/outputs
   - Test in isolation

3. **Update existing templates:**
   - Modify `modular-docker/main.tf` to use modules
   - Remove bundling logic from push script

4. **Retire old modules folder:**
   - Archive `modules/*.tf` files
   - Update documentation

### If POC Fails ❌

**Option 1: Keep current approach**
- Improve push script
- Better documentation
- Accept duplication

**Option 2: Use remote modules**
- Push modules to Git repo
- Reference via `source = "git::https://..."`
- Templates pull from remote

**Option 3: Hybrid approach**
- Keep base modules flat (bundled)
- Use proper modules for complex features only
- Best of both worlds

## 📝 Notes

- **No changes to existing setup**: This POC is completely isolated
- **Safe to test**: Won't affect your current templates
- **Easy to remove**: Just delete the two new directories
- **Manual push only**: Not using your push script for this test

## 🐛 Troubleshooting

### Can't find Coder CLI
```bash
which coder
# If empty, check Docker or install Coder CLI
```

### Module path issues
The module source path is **relative to the template directory**:
```
test-module-template/main.tf
  └── source = "../test-modules/docker-workspace"
      └── Points to: test-modules/docker-workspace/
```

### Terraform not installed locally
That's fine! Coder will run Terraform on its server during push.
You can skip local `terraform init` and go straight to `coder templates push`.

## 📚 References

- [Terraform Module Sources](https://www.terraform.io/language/modules/sources)
- [Coder Templates Docs](https://coder.com/docs/templates)
- Your existing push script: `config/coder/scripts/push-templates.sh`
