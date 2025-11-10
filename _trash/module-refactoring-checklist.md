# Coder Template Module Refactoring Checklist

This checklist tracks the creation of GitHub issues for analyzing and refactoring each shared template module to reduce UI flickering and improve maintainability.

## Shared Template Modules (_trash/shared-template-modules/)

- [x] module-init-shell.tf (0 params, no deps) - Issue #23
- [x] module-code-server.tf (0 params, depends on agent) - Issue #24
- [x] module-debug-domain.tf (0 params) - Issue #25
- [x] module-docker.tf (1 param) - Issue #26
- [x] module-metadata.tf (1 param) - Issue #27
- [x] module-traefik-local.tf (2 params) - Issue #30
- [x] module-git.tf (3 params - includes flickering "Clone Repo") - Issue #29
- [x] module-preview-link.tf (3 params) - Issue #31
- [x] module-setup-server.tf (3 params) - Issue #32
- [x] module-ssh.tf (4 params) - Issue #33
- [ ] module-agent.tf (0 params, heavy deps)

## Node Template Modules (config/coder/templates/node-template/)

- [x] module-node-version.tf (Node.js version selection) - Issue #37
- [x] module-node-tooling.tf (npm/yarn/pnpm tooling) - Issue #38
- [x] module-node-modules.tf (node_modules persistence) - Issue #39
- [x] module-node-server.tf (DEPRECATED) - Issue #40
- [x] module-setup-server-impl.tf (Node-specific server impl) - Issue #41
- [x] module-agent.tf (Node template agent config) - Issue #42

## Issue Creation Progress

Total: 17/17 issues created - COMPLETE!

## Issues Created

- #23 - module-init-shell.tf (0 params, no deps)
- #24 - module-code-server.tf (0 params, depends on agent)
- #25 - module-debug-domain.tf (0 params)
- #26 - module-docker.tf (1 param - enable_docker)
- #27 - module-metadata.tf (1 param - metadata_blocks multi-select)
- #29 - module-git.tf (3 params - THE FLICKERING MODULE)
- #30 - module-traefik-local.tf (2 params - conditional param visibility)
- #31 - module-preview-link.tf (3 params - conditional params)
- #32 - module-setup-server.tf (3 params - shared)
- #33 - module-ssh.tf (4 params - heavy conditionals)
- #34 - module-agent.tf (0 params, 12 deps - shared orchestrator)
- #37 - node-template/module-node-version.tf (6 params, 3 unused)
- #38 - node-template/module-node-tooling.tf (0 local params)
- #39 - node-template/module-node-modules.tf (0 local, uses mutable)
- #40 - node-template/module-node-server.tf (DEPRECATED)
- #41 - node-template/module-setup-server-impl.tf (0 local, uses 2 mutable)
- #42 - node-template/module-agent.tf (0 local, 17 deps, 5 TERNARY OPS)
- #30 - module-traefik-local.tf (2 params - conditional param visibility)
- #31 - module-preview-link.tf (3 params - mutually exclusive conditionals)
- #32 - module-setup-server.tf (3 params - complex list parsing)
- #33 - module-ssh.tf (4 params - CASCADING CONDITIONALS, MAX COMPLEXITY)

---
*Generated: 2025-11-10*
*Purpose: Track incremental testing to identify UI flickering root cause*
