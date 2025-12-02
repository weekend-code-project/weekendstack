# Node.js Template

This template provides a full-featured Node.js development environment.

## Features
- **Node.js**: Configurable version (LTS, 22, 20, 18)
- **Package Managers**: npm, pnpm, yarn
- **Tooling**: TypeScript, ESLint (optional)
- **Docker**: Docker-in-Docker support
- **Git**: Full integration with GitHub/Gitea
- **Web IDE**: VS Code Server

## Parameters
- **Node Version**: Select the Node.js version to install
- **Package Manager**: Choose your preferred package manager
- **Install TypeScript**: Toggle TypeScript installation
- **Install ESLint**: Toggle ESLint installation

The previous docker template had diverged significantly from the test harness, which made it hard to compare behaviors. By cloning the test-template layout, we ensure the production template benefits from the same low-flicker defaults before reintroducing modules one-by-one.

## Usage

1. Iterate on the shared parameter files in `config/coder/template-modules/params/`
2. Push the template with `./config/coder/scripts/push-template-versioned.sh docker-template`
3. Observe workspace UI for flickering as modules are re-enabled
4. Document findings per module/issue before adding the next parameter file
