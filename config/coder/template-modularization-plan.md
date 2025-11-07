# Coder Template Modularization & Auto-Ref Plan (v0.1.1 Workstream)

## 1. Goals
- Centralize reusable per-template Terraform module glue (`module-*.tf` files currently in `config/coder/templates/docker-template/`) into a shared location so multiple specialized templates can consume them without duplication.
- Preserve existing git-based reusable modules in `config/coder/templates/git-modules/` (unchanged).
- Introduce automatic Git ref resolution for git module sources (tag > main > current branch) during push, without committing moving refs.
- Maintain existing template versioning semantics (incremental v1, v2...) while enabling branch-aware module sourcing.
- Enable iterative development on a new branch `v0.1.1` and merge back to `main` when complete.

## 2. Scope
In Scope:
- Creating new shared folder for template-level Terraform composition files (the `module-*.tf` group) separate from any single template.
- Adjusting push workflow to inject or overlay these shared files into each template prior to pushing.
- Adding ephemeral substitution of `?ref=` in git module sources based on current Git context.
- Documentation updates (this plan, plus updates to `docs/coder-templates-guide.md`).
- Non-breaking incremental branch-based rollout.

Out of Scope (for this workstream):
- Refactoring the git modules themselves.
- Changing Coder resource semantics (e.g., `coder_agent`, `docker_container`).
- Introducing complex templating engines beyond simple variable substitution.

## 3. Current State Summary
- Reusable git modules live under `config/coder/templates/git-modules/` and are referenced with a hard-coded `?ref=v0.1.0`.
- Template-specific composition glue (e.g., `module-agent.tf`, `module-traefik-local.tf`, etc.) resides inside the `docker-template` directory.
- Push script (`config/coder/scripts/push-template-versioned.sh`) copies a single template folder to the Coder container and pushes with incremental versions (v1, v2...).
- Hard-coded refs make branch/tag switching manual.

## 4. Target Architecture
```
config/coder/
│
├── shared-template-modules/          # NEW: central home for module-*.tf glue
│   ├── README.md                      # Purpose & usage
│   ├── module-agent.tf
│   ├── module-docker.tf
│   ├── module-git.tf
│   ├── module-init-shell.tf
│   ├── module-metadata.tf
│   ├── module-preview-link.tf
│   ├── module-setup-server.tf
│   ├── module-ssh.tf
│   ├── module-traefik-local.tf
│   └── (future additional module-*.tf)
│
├── templates/
│   ├── docker-template/               # Now slimmer: main.tf, variables.tf, resources.tf, minimal README
│   ├── <specialized-template-A>/
│   ├── <specialized-template-B>/
│   └── git-modules/                  # (unchanged)
│
├── scripts/
│   ├── push-template-versioned.sh    # Enhanced with auto-ref & shared module overlay
│   └── push-templates.sh             # (optionally updated later)
│
└── template-modularization-plan.md   # This plan
```

### Overlay Mechanics
- During push, the script constructs a temp directory: `TEMP_DIR/<template-name>/`.
- It copies the base template files.
- It then overlays (copies) all `*.tf` from `shared-template-modules/` into that temp template directory unless a template supplies an override file with the same name (override precedence: template-local > shared).
- Optional: allow per-template exclusion via a `.shared-modules-ignore` file listing filenames to skip.

### Ref Placeholder Strategy
- Shared and template files use a placeholder token instead of a static ref, e.g.:
  `source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/ssh-integration?ref={{GIT_REF}}"`
- Push script resolves `{{GIT_REF}}` based on Git context and performs in-place substitution only inside the temp push directory.
- Repository stays with placeholder tokens to avoid noisy commits when switching branches.

## 5. Auto-Ref Resolution Policy
Priority order:
1. If HEAD is exactly on a lightweight or annotated tag matching pattern `v*` (e.g., `v0.1.1`) → use that tag.
2. Else if current branch name is `main` → use `main`.
3. Else use current branch name.
4. If branch name contains slashes or special characters → URL-encode for query string.
5. Validate the ref exists on remote (`git ls-remote origin <ref>`). If missing:
   - Fallback: `main` OR abort (configurable via env `REF_FALLBACK=main` / `REF_REQUIRED=true`).
6. Allow override via environment variable `REF_OVERRIDE` or CLI flag `--ref` for emergency/hotfix.

## 6. Push Script Enhancement Overview
Add the following responsibilities to `push-template-versioned.sh`:
- Detect Git ref (implement function `detect_git_ref`).
- Validate remote ref (function `validate_remote_ref`).
- Prepare temp directory and overlay shared modules (function `overlay_shared_modules`).
- Substitute placeholders `{{GIT_REF}}` (function `substitute_git_ref`).
- Optionally record resolved ref in a metadata file: `TEMP_DIR/<template-name>/.resolved_ref` and echo to output.
- Keep existing version auto-increment logic.
- Preserve retry semantics for duplicate version detection.
- Provide a dry-run mode (`--dry-run`) to show planned ref and file list without pushing.
- Logging improvements: show chosen ref, fallback actions, count of shared modules applied.

## 7. Task Breakdown
| ID | Task | Description | Acceptance Criteria |
|----|------|-------------|---------------------|
| 1 | Create branch | Create `v0.1.1` branch for workstream | Branch exists locally & remotely |
| 2 | Establish shared folder | Add `shared-template-modules/` & move module-*.tf from docker-template | Files relocated; docker-template still functional after overlay |
| 3 | Introduce placeholders | Replace hard-coded `?ref=v0.1.0` with `?ref={{GIT_REF}}` in all relevant tf files | No lingering hard-coded refs except in git-modules README examples |
| 4 | Update push script (detection) | Add git ref detection & validation (dry-run) | Dry-run outputs correct ref for tag/branch/main |
| 5 | Update push script (overlay) | Implement overlay logic with override precedence and optional ignore file | Pushed template includes shared files; per-template override works |
| 6 | Update push script (substitution) | Implement placeholder substitution only in temp directory | Pushed template module sources show actual ref; repo still shows placeholders |
| 7 | Add optional flags | Support `--ref`, `--dry-run`, `--fallback <ref>` | Flags parsed and documented |
| 8 | Documentation updates | Update `coder-templates-guide.md` + new README in shared folder | Docs explain auto-ref & overlay clearly |
| 9 | Testing matrix | Execute tests across tag, main, feature branch scenarios | Evidence captured in notes/logs |
| 10 | Release & merge | Tag `v0.1.1` (optional), merge to `main`, update examples to use `main` | Main reflects new architecture |

## 8. Testing Matrix
| Scenario | Git State | Expected Resolved Ref | Notes |
|----------|----------|-----------------------|-------|
| Feature Branch | branch `feat-x` | `feat-x` | Ensure remote branch exists or fallback triggers |
| Main Branch | `main` | `main` | Standard development flow |
| Tagged Release | tag `v0.1.1` checked out | `v0.1.1` | Highest priority resolution |
| Missing Remote Branch | local branch w/o remote | fallback (`main`) or abort | Verify override and fallback behavior |
| Override Flag | any state + `--ref v0.2.0` | `v0.2.0` | Skips detection | 
| Override Env | `REF_OVERRIDE=v0.2.1` | `v0.2.1` | Precedence over detection |

## 9. Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|-----------|
| Placeholder missed in a file | Module uses stale ref | Add grep validation step pre-push; fail if no `{{GIT_REF}}` found in expected sources |
| Remote ref validation false negative | Blocks push | Allow manual override `--ref`; log detailed failure reason |
| Terraform caching artifacts between refs | Inconsistent module loading | Encourage `coder templates rebuild` or workspace recreation when switching branches |
| Branch names with slashes | Bad URL in source | URL-encode ref component before substitution |
| Overwritten local overrides | Loss of custom template behavior | Precedence rule: do not copy shared file if template already has filename |

## 10. Rollout Steps
1. Create `v0.1.1` branch.
2. Add new shared folder; move module glue files; commit.
3. Replace refs with placeholders across moved files and any remaining template references.
4. Implement push script enhancements incrementally (detection -> overlay -> substitution -> flags).
5. Update documentation.
6. Perform test matrix scenarios (record logs in a development notes file or commit lightweight test results).
7. Optional: tag `v0.1.1` to lock in release demonstration.
8. Merge `v0.1.1` into `main`.
9. Announce new usage: templates now auto-resolve refs; examples in README show `?ref={{GIT_REF}}` pattern.

## 11. Acceptance Criteria Summary
- Shared folder operational & documented.
- Push script supports auto-ref, overlay, dry-run, override.
- Placeholders fully adopted; no hard-coded stale refs outside module docs.
- Successful pushes from tag, main, and feature branch produce correct `?ref` values.
- Documentation updated and committed.

## 12. Follow-Up (Future Enhancements)
- Add lint script to verify placeholder compliance and warn on accidental hard-coded refs.
- Multi-template batch push script update.
- Optional caching layer for resolved ref to show in workspace metadata.
- Introduce semantic version detection to auto-bump tag numbers or enforce tag format.

---
Prepared: 2025-11-07
Workstream Branch: `v0.1.1`
