# Coder Template System: Module Migration Plan

**Updated:** 2026-02-25
**Status:** Active — core modules migrated and verified, continuing with CLI tools & Node.js

---

## Architecture Overview

```
config/coder/
├── modules/                          # v2 modules (LIVE)
│   ├── feature/                      # Terraform modules called from templates
│   │   ├── code-server/         ✅   # Web IDE
│   │   ├── git-config/          ✅   # Git identity + repo cloning (with retry)
│   │   ├── ssh-server/          ✅   # SSH server with deterministic port
│   │   └── traefik-routing/     ✅   # External preview + Traefik labels + auth
│   ├── platform/                     # (empty — .gitkeep)
│   └── step/                         # (empty — .gitkeep)
├── templates/
│   ├── base/                         # Minimal template (code-server + traefik)
│   └── new-modular-template/         # Extended template (all modules)
├── scripts/
│   ├── push-template.sh              # Builds temp dir, copies modules, pushes to Coder
│   ├── deploy-all-templates.sh       # Iterates templates, calls push-template.sh
│   └── lib/                          # coder-api.sh, get-template-info.sh
└── helpers/
    └── startup-lib.sh                # Shared logging/idempotency helpers

_trash/coder-v1/template-modules/     # Legacy modules (SOURCE for migration)
├── modules/                          # 20 module directories
└── params/                           # 7 param files (glue that wired modules to templates)
```

### How It Works

1. **Templates** live in `config/coder/templates/<name>/` with `main.tf` + `variables.tf`
2. Templates reference modules via `source = "./modules/feature/<name>"`
3. `push-template.sh` copies the template to a temp dir, then copies referenced modules from `config/coder/modules/` into it
4. Variables (`base_domain`, `host_ip`) are substituted from `.env`
5. The assembled directory is pushed to Coder via `docker exec coder coder templates push`

### Current Template Design (new-modular-template)

The `new-modular-template/main.tf` is a **monolithic template** — it defines:
- Coder agent inline (not a module)
- Docker container inline (not a module)
- Docker image + volume inline
- `coder_script` for startup command inline
- `coder_app` for local preview inline
- Calls `code-server` module for web IDE
- Calls `traefik-routing` module for external preview + auth

The legacy v1 system tried to modularize *everything* (agent, container, metadata, etc.) which created complex interdependencies. The v2 approach keeps the agent and container inline in the template and only extracts **features** as modules.

---

## Full Audit: Legacy Modules → v2 Status

### Already Migrated (in v2)

| Legacy Module | v2 Location | Notes |
|---|---|---|
| `code-server-module` | `modules/feature/code-server/` | Simplified: removed `workspace_start_count` (not needed when module is unconditional) |
| `traefik-routing-module` | `modules/feature/traefik-routing/` | Rewritten: auth via `coder_script` + labels instead of separate auth module |
| `password-protection-module` | merged into `traefik-routing` | Auth setup is now a `coder_script` inside the routing module |
| `workspace-auth-module` | merged into `traefik-routing` | Duplicate of password-protection-module |
| `routing-labels-test-module` | merged into `traefik-routing` | Labels are now generated inside the routing module |
| `git-identity-module` | merged into `modules/feature/git-config/` | Git identity (user.name/email) + safe.directory + OAuth credential helper |
| `git-integration-module` | merged into `modules/feature/git-config/` | Repo cloning with SSH/HTTPS auto-detection, retry logic, mirror-clone approach |
| `ssh-module` | `modules/feature/ssh-server/` | SSH server with deterministic port, persistent host keys, known_hosts, flock-based apt serialization |
| `init-shell-module` | merged into template `coder_script.startup` | First-run home init is now inline in the template's startup script |

### Not Needed (functionality is inline in template)

| Legacy Module | Why Not Needed |
|---|---|
| `coder-agent-module` | Agent is defined inline in each template's `main.tf` — extracting it adds complexity without benefit (every template needs different `env`, `metadata`, `display_apps`) |
| `docker-module` | Docker-in-Docker setup. Only needed for container-dev templates. Can be added later if needed |
| `metadata-module` | Resource monitoring metadata is defined inline in agent block. The v1 "selectable metadata" via multi-select parameter caused flickering issues |
| `preview-link-module` | Local preview `coder_app` is defined inline. The v1 module had 3 modes (internal/traefik/custom) which was overcomplicated |

### Need to Migrate (ordered by priority)

| # | Legacy Module | v2 Target | Complexity | Why Needed |
|---|---|---|---|---|
| 1 | `github-cli-module` | `modules/feature/github-cli/` | Low | `gh` CLI installation |
| 2 | `gitea-cli-module` | `modules/feature/gitea-cli/` | Low | `tea` CLI installation |
| 3 | `node-version-module` | `modules/feature/node-version/` | Medium | NVM/Volta/fnm/n + Node.js version management |
| 4 | `node-tooling-module` | `modules/feature/node-tooling/` | Medium | Global npm packages (TypeScript, ESLint, etc.) |
| 5 | `node-modules-persistence-module` | `modules/feature/node-modules-persist/` | High | Bind-mount persistent node_modules across restarts |
| 6 | `coder-user-setup-module` | `modules/feature/user-setup/` | Low | Creates coder user for non-Coder base images (e.g., `node:20`) |
| 7 | `setup-server-module` | *Skip* | High | Overcomplicated — replaced by inline `coder_script` in template |

---

## Migration Strategy

### Approach: One Module at a Time

Each module migration follows this process:

1. **Read** the legacy module code and understand inputs/outputs
2. **Adapt** to v2 conventions (see below)
3. **Create** the module in `config/coder/modules/feature/<name>/`
4. **Wire** it into `new-modular-template/main.tf` (or create a test template)
5. **Push** with `push-template.sh --dry-run new-modular-template` to validate
6. **Test** by pushing for real and creating a workspace
7. **Confirm** it works before moving to the next module

### v2 Module Conventions

Every v2 feature module should follow these patterns:

```
modules/feature/<name>/
├── main.tf        # Resources, variables, outputs — all in one file
└── README.md      # Brief description, inputs, outputs
```

**Design Rules:**
- **Self-contained**: Each module is a Terraform module with `variable` inputs and `output` values
- **No cross-module dependencies**: Modules don't reference other modules. The template wires them together
- **`coder_script` for startup work**: Instead of outputting shell script strings that get composed in an agent `startup_script`, create `coder_script` resources that Coder runs independently. This eliminates script ordering bugs
- **No `count` based on parameters**: The template decides whether to include a module. If a module is included, it runs unconditionally. This avoids the v1 flickering issues
- **Variables use simple types**: `string`, `bool`, `number`, `list(string)`. No complex objects
- **Outputs expose only what templates need**: Labels map, URLs, IDs — not shell scripts

### Template Integration Pattern

```hcl
# In template main.tf:

module "git_identity" {
  source = "./modules/feature/git-identity"

  agent_id     = coder_agent.main.id
  author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  author_email = data.coder_workspace_owner.me.email
}
```

The push script handles copying `modules/feature/git-identity/` into the temp build directory automatically (it scans `source = "./modules/"` references).

---

## Migration Queue (Do These One at a Time)

### Round 1: Git & SSH — ✅ COMPLETE

All core modules for Git identity, repo cloning, and SSH server access are migrated and verified.

#### ✅ `git-config` (combines git-identity + git-integration)
- Git identity: `git config --global user.name/email`, safe.directory
- GitHub OAuth credential helper for HTTPS private repos
- Repo cloning: SSH and HTTPS URLs, mirror-clone approach
- **Coder native SSH auth**: Uses `$GIT_SSH_COMMAND` (`coder gitssh`) — no manual key generation
- **Retry logic**: Clone retries up to 3 times with increasing delays (handles `coder gitssh` startup timing)
- **Proper error handling**: Checks git's exit code directly (not grep on output)
- Tracks remote branches, initializes submodules

#### ✅ `ssh-server`
- OpenSSH server on deterministic port (23000-29999 based on workspace_id)
- Persistent host keys (survive workspace restarts)
- Known hosts for GitHub, GitLab, Bitbucket, Gitea
- **flock-based apt serialization** to prevent dpkg lock contention with parallel scripts
- Password auth with configurable password
- Git SSH auth delegated to Coder native `$GIT_SSH_COMMAND`

#### ✅ `init-shell` (merged into template startup script)
- First-run home directory initialization is inline in the template's `coder_script.startup`

### Round 2: CLI Tools — TODO

#### Migration 1: `github-cli`
**Legacy:** `github-cli-module` — outputs an install script
**v2 approach:** `coder_script` resource that installs `gh`
**Inputs:** `agent_id`

#### Migration 2: `gitea-cli`
**Legacy:** `gitea-cli-module` — outputs an install script
**v2 approach:** `coder_script` resource that installs `tea`
**Inputs:** `agent_id`

### Round 3: Node.js — TODO

#### Migration 3: `node-version`
**Legacy:** `node-version-module` — NVM/Volta/fnm/n install strategies
**v2 approach:** `coder_script` resource with simplified strategy
**Inputs:** `agent_id`, `node_version`, `install_strategy`, `package_manager`
**Simplification:** Consider defaulting to just NVM (most common) and dropping Volta/fnm/n unless requested

#### Migration 4: `node-tooling`
**Legacy:** `node-tooling-module` — global package installation
**v2 approach:** `coder_script` resource
**Inputs:** `agent_id`, `enable_typescript`, `enable_eslint`, `package_manager`
**Depends on:** node-version (must run after Node is installed)

#### Migration 5: `node-modules-persist`
**Legacy:** `node-modules-persistence-module` — bind-mount node_modules
**v2 approach:** `coder_script` + output for Docker volume/mount config
**Inputs:** `agent_id`, `node_modules_paths`, `workspace_folder`
**Complexity:** Highest — involves `mount --bind` and package manager detection. Consider deferring

### Round 4: Specialized — TODO

#### Migration 6: `user-setup`
**Legacy:** `coder-user-setup-module` — creates coder user for non-Coder images
**v2 approach:** `coder_script` that runs early in startup
**Inputs:** `agent_id`
**When needed:** Only for templates using base images like `node:20` instead of `codercom/enterprise-base`

---

## Key Differences: v1 → v2 Module Design

| Concern | v1 (Legacy) | v2 (New) |
|---------|-------------|----------|
| Script execution | Module outputs a shell string → composed into `startup_script` | Module creates a `coder_script` resource → Coder runs it independently |
| Script ordering | Manual: order matters in `join("\n", [...])` | Automatic: Coder manages `coder_script` execution |
| Conditional inclusion | `count = condition ? 1 : 0` on module → `try(module.x[0].output, "")` | Template simply includes or omits the `module` block |
| Parameter ownership | Params defined in shared `params/*.tf` files → copied to template | Params defined inline in the template's `main.tf` |
| Module interface | Outputs shell script strings | Creates Coder resources directly (scripts, apps, metadata) |
| Cross-module state | Modules output values consumed by agent module startup script | No cross-module state — each module is self-contained |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `coder_script` ordering can't be guaranteed | Use `start_blocks_login = true` for critical setup scripts (git, SSH) and `false` for optional ones |
| Module A breaks Module B during migration | Migrate one at a time; push + test after each; don't commit the next until current is verified |
| SSH module needs port output for Docker container | Module outputs the port; template uses it in `docker_container.ports` block |
| Node modules need NVM loaded first | `coder_script` for node-tooling should source NVM inline before installing packages |
| The `traefik_auth_dir` host mount may not exist | Already handled — the mount is in the template's container block, not in any module |

---

## Decision Log

| Date | Decision | Reason |
|------|----------|--------|
| 2026-01-11 | Keep agent + container inline in templates | Extracting to modules added complexity without benefit (v1 had this, caused issues) |
| 2026-01-11 | Use `coder_script` instead of composed startup strings | Eliminates script ordering bugs from v1 |
| 2026-01-11 | Traefik auth via labels + coder_script (not separate module) | Single module handles routing + auth together |
| 2026-02-19 | Defer cutover until all templates verified | Don't break clean install while migrating |
| 2026-02-24 | Migrate modules one-at-a-time with user verification | Past bulk migrations broke inter-module dependencies |
| 2026-02-24 | Drop `setup-server-module` — too complex, replaced by inline coder_script | v1 version had port mapping, HTML generation, wrapper scripts — all handled simpler inline |
| 2026-02-24 | Drop `metadata-module` — keep metadata inline | Multi-select parameter caused flickering; simpler to hardcode useful metrics |
| 2026-02-24 | Merge password/auth modules into traefik-routing | Three separate modules (password-protection, workspace-auth, routing-labels-test) all did overlapping work |
| 2026-02-25 | Use Coder native SSH keys (`$GIT_SSH_COMMAND` / `coder gitssh`) | Coder auto-generates per-user SSH key, injects via agent env. No manual key gen/mount needed |
| 2026-02-25 | Merge git-identity + git-integration into single `git-config` module | Both are git-related, run as one `coder_script`. Simpler than two separate modules |
| 2026-02-25 | Add clone retry logic (3 attempts with backoff) | `coder gitssh` has a startup timing issue — not ready on first attempt, succeeds on retry |
| 2026-02-25 | Remove SSH key generation/mounting from all modules | Coder's native `$GIT_SSH_COMMAND` handles auth. No per-workspace or shared host keys needed |
| 2026-02-25 | Use `flock` for apt serialization across parallel scripts | Prevents dpkg lock contention when ssh-server and traefik-routing both install packages |

---

## Next Steps

**Start with Migration 1: `github-cli`**

1. Create `config/coder/modules/feature/github-cli/main.tf`
2. Wire into `new-modular-template/main.tf` (optional, behind a parameter)
3. `push-template.sh --dry-run new-modular-template` to validate
4. Push and test
5. Confirm working → move to Migration 2: `gitea-cli`
