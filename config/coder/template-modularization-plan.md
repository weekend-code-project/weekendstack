# Coder Template Modularization & Auto-Ref Plan (v0.1.1 Workstream)

## 1. Goals

**Original v0.1.1 Goals** (deferred until flickering issue resolved):
- Centralize reusable per-template Terraform module glue (`module-*.tf` files currently in `config/coder/templates/docker-template/`) into a shared location so multiple specialized templates can consume them without duplication.
- Preserve existing git-based reusable modules in `config/coder/template-modules/modules/` (unchanged).
- Introduce automatic Git ref resolution for git module sources (tag > main > current branch) during push, without committing moving refs.
- Maintain existing template versioning semantics (incremental v1, v2...) while enabling branch-aware module sourcing.
- Enable iterative development on a new branch `v0.1.1` and merge back to `main` when complete.

**Current Immediate Goals** (test-params-incrementally branch):
- **Identify and fix UI flickering** in Coder workspace templates (checkboxes toggling, fields disappearing during updates)
- Test modules incrementally starting from zero-parameter baseline to isolate flickering root cause
- Document findings for each module in GitHub issues (#23-#42)
- Fix identified bugs (unused parameters, unnecessary conditionals, ternary operators)
- Establish best practices for Terraform patterns that prevent UI flickering

## 2. Scope

**Current Scope** (test-params-incrementally branch):

In Scope:
- Incremental testing of all 17 modules to identify UI flickering patterns
- Creating comprehensive GitHub issues (#23-#42) documenting each module with full ASCII parameter dependency diagrams
- Testing modules one-by-one from simplest (0 params) to most complex (5 ternary operators)
- Fixing bugs: unused parameters, missing module inputs, conditional logic that causes re-evaluation
- Documenting flickering risk factors: ternary operators, conditional count, mutable parameters
- Establishing clean test-template baseline (v1 with zero parameters)

Out of Scope (for current flickering investigation):
- Full modularization architecture (deferred to v0.1.1 workstream)
- Automatic Git ref resolution
- Shared module overlay system
- Refactoring git modules themselves
- Changing Coder resource semantics

**Original v0.1.1 Scope** (deferred):

In Scope:
- Creating new shared folder for template-level Terraform composition files (the `module-*.tf` group) separate from any single template.
- Adjusting push workflow to inject or overlay these shared files into each template prior to pushing.
- Adding ephemeral substitution of `?ref=` in git module sources based on current Git context.
- Documentation updates (this plan, plus updates to `docs/coder-templates-guide.md`).
- Non-breaking incremental branch-based rollout.

Out of Scope (for v0.1.1 workstream):
- Refactoring the git modules themselves.
- Changing Coder resource semantics (e.g., `coder_agent`, `docker_container`).
- Introducing complex templating engines beyond simple variable substitution.

## 3. Current State Summary

**As of December 2, 2025** (test-params-incrementally branch):

- `config/coder/template-modules/modules/` now contains the curated git-based modules (migrated from the historical `templates/git-modules/` path)
- Shared parameter overlays live in `config/coder/template-modules/params/` and are injected automatically by the push script when a template omits a local override
- Test-template v1 remains the zero-parameter baseline and now references modules via the new path with `?ref=PLACEHOLDER` or `?ref=v0.1.0` values for substitution
- 17 comprehensive GitHub issues created (#23-#34 shared, #37-#42 node) with full ASCII diagrams and flickering notes
- Module-refactoring-checklist.md committed tracking all issues (17/17 complete)
- Push script enhancements landed: sed bug fix (line 259), shared param overlay, base_domain/host_ip substitution, retry logic, and git ref detection/validation
- Agent module interface fixed (env_vars type, output names) and now references shared metadata locals collected inside `agent-params.tf`
- Docker template currently holds the stable production build (v82); test-template is the active flicker lab environment

**Module Locations**:
- Reusable git modules: `config/coder/template-modules/modules/` (referenced with `?ref=v0.1.0` in-repo, substituted during push)
- Archived historical shared glue: `_trash/shared-template-modules/` (kept for diffing/reference only)
- Shared parameter definitions: `config/coder/template-modules/params/`
- Node-specific modules: `config/coder/templates/node-template/` (6 files documented in issues)
- Test template: `config/coder/templates/test-template/` (minimal baseline, zero parameters)
- Docker template: `config/coder/templates/docker-template/` (stable at v82)

**Known Issues**:
- UI flickering during workspace updates (checkboxes toggle, fields disappear)
- "Clone Repo" checkbox in module-git.tf known to flicker
- Multiple modules define parameters but don't use them (bugs documented in issues)
- Ternary operators in module calls likely cause Terraform re-evaluation
- Conditional count on parameters causes visibility toggling (very high flickering risk)

**Original State** (before flickering investigation):
- Reusable git modules live under `config/coder/templates/git-modules/` and are referenced with a hard-coded `?ref=v0.1.0`.
- Template-specific composition glue (e.g., `module-agent.tf`, `module-traefik-local.tf`, etc.) resides inside the `docker-template` directory.
- Push script (`config/coder/scripts/push-template-versioned.sh`) copies a single template folder to the Coder container and pushes with incremental versions (v1, v2...).
- Hard-coded refs make branch/tag switching manual.

## 4. Target Architecture
```
config/coder/
│
├── template-modules/
│   ├── modules/                      # Git-addressable Terraform modules (agent, docker, metadata, etc.)
│   └── params/                       # Shared parameter glue copied into templates during push
│
├── templates/
│   ├── docker-template/              # Production template (v82)
│   ├── node-template/                # Node-specific variant under investigation
│   └── test-template/                # Zero-parameter baseline for flicker testing
│
├── scripts/
│   ├── push-template-versioned.sh    # Auto-ref substitution, shared param overlay, retry logic
│   └── push-templates.sh             # Batch push helper (legacy)
│
└── template-modularization-plan.md   # This plan
```

### Overlay Mechanics
- During push, the script constructs a temp directory: `TEMP_DIR/<template-name>/`.
- It copies the base template files.
- It overlays (copies) all `*-params.tf` files from `template-modules/params/` into that temp template directory unless a template supplies an override file with the same name (override precedence: template-local > shared).
- Optional: per-template exclusion list still future work (consider `.shared-modules-ignore`).

### Ref Placeholder Strategy
- Terraform sources live under `git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/<module>?ref=<sentinel>`.
- Refs remain `v0.1.0` (or `PLACEHOLDER`) inside the repo. `push-template-versioned.sh` rewrites those refs inside the temp directory only, using the detected Git ref and URL-encoded output.
- Result: no moving-ref commits; pushes always resolve to the active branch/tag while the repo stays deterministic.

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

## 7. Task Breakdown - Incremental Module Addition (test-params-incrementally branch)

**Current Status**: Shared modules now live in `template-modules/modules/` (tracked in git). `_trash/shared-template-modules/` remains as an archive for comparison, but the active templates reference the new location. Test template v1 is pushed and stable, awaiting incremental parameter/module reintroduction while tracking flickering.

**Strategy**: Enable modules/parameters one-by-one using the tracked files under `template-modules/params/`, referencing `_trash/shared-template-modules/` only when a historical variant is needed for comparison. Each addition should be validated for UI flickering before moving on.

### Module Addition Order (by Testing Priority)

| Priority | Module File | Issue | Params | Dependencies | Flickering Risk | Notes |
|----------|-------------|-------|--------|--------------|-----------------|-------|
| 1 | module-init-shell.tf | #23 | 0 | None | LOW | Simplest baseline, no UI |
| 1 | module-debug-domain.tf | #25 | 0 | None | LOW | Local only, no parameters |
| 2 | module-code-server.tf | #24 | 0 | agent | LOW | Needs agent module, no params |
| 3 | module-docker.tf | #26 | 1 | None | MEDIUM | First boolean switch test, unused param bug |
| 4 | module-metadata.tf | #27 | 1 | None | MEDIUM-HIGH | Multi-select, mutable param |
| 5 | module-setup-server.tf | #32 | 3 | None | MEDIUM | String/list params, mutable |
| 6 | module-preview-link.tf | #31 | 3 | agent, traefik | HIGH | Conditional params (count-based) |
| 7 | module-ssh.tf | #33 | 4 | None | VERY HIGH | Heavy conditionals, count-based visibility |
| 8 | module-traefik-local.tf | #30 | 2 | None | VERY HIGH | Conditional count on workspace_secret |
| 9 | (node modules) | #37-42 | varies | varies | varies | Test after shared modules stable |
| 10 | module-git.tf | #29 | 3 | None | **CRITICAL** | **KNOWN FLICKERING MODULE** - Clone Repo checkbox |
| 11 | module-agent.tf | #34 | 0 | ALL (12 deps) | **MAXIMUM** | Central orchestrator, 5 ternary ops - test LAST |

### Incremental Testing Workflow

For each module (in priority order):

1. **Stage params**: Edit or copy the relevant `*-params.tf` under `template-modules/params/` (use `_trash/shared-template-modules/` as historical reference only).
2. **Update template**: Ensure module is called/integrated in `main.tf` or `agent-params.tf` as needed.
3. **Push to Coder**: `./push-template-versioned.sh test-template`
4. **Test workspace**: 
   - Create new workspace OR update existing workspace
   - **Observe for flickering**: Watch for checkboxes toggling, fields disappearing, form re-rendering
   - Test parameter interactions (change values, observe behavior)
5. **Document results**: Add findings to GitHub issue
6. **Commit progress**: `git commit -am "test-template: Added module-X (Issue #N) - [PASS/FAIL flickering test]"`

### Known Issues to Fix During Migration

| Module | Issue # | Bug | Fix Required |
|--------|---------|-----|--------------|
| module-docker.tf | #26 | `enable_docker` param defined but not used | Actually use parameter or remove it |
| module-git.tf | #29 | `install_github_cli` param defined but not used | Pass to module or remove param |
| module-node-version.tf | #37 | 3 params not passed to module (typescript, eslint, node_modules_paths) | Pass to module or remove params |
| module-agent.tf (shared) | #34 | 5 ternary operators in startup_script | Consider refactoring to reduce re-evaluation |
| module-agent.tf (node) | #42 | 5 ternary operators in startup_script | Consider refactoring to reduce re-evaluation |

### Success Criteria

- [ ] All 11 shared modules added incrementally without introducing flickering
- [ ] Flickering root cause identified (specific parameter pattern or module)
- [ ] Unused parameters fixed or removed
- [ ] Ternary operators refactored if identified as flickering cause
- [ ] Test-template reaches feature parity with docker-template
- [ ] Documentation updated with flickering prevention best practices

### Original Task Breakdown (v0.1.1 workstream - deferred)

| ID | Task | Description | Acceptance Criteria |
|----|------|-------------|---------------------|
| 1 | Create branch | Create `v0.1.1` branch for workstream | Branch exists locally & remotely |
| 2 | Establish shared folder | Add `template-modules/` & move module-*.tf from docker-template | Files relocated; docker-template still functional after overlay |
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
