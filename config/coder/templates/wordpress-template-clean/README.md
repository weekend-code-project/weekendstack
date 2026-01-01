# Docker Template (Minimal Baseline)

This template now mirrors the flicker-testing baseline. It intentionally ships with zero template-level parameters and relies on shared parameter glue being overlaid during `push-template-versioned.sh` execution.

It provisions:
- A privileged Docker workspace container (ubuntu-based)
- The core Coder agent
- A persistent home volume with metadata labels

## Why this reset?

The previous docker template had diverged significantly from the test harness, which made it hard to compare behaviors. By cloning the test-template layout, we ensure the production template benefits from the same low-flicker defaults before reintroducing modules one-by-one.

## Usage

1. Iterate on the shared parameter files in `config/coder/template-modules/params/`
2. Push the template with `./config/coder/scripts/push-template-versioned.sh docker-template`
3. Observe workspace UI for flickering as modules are re-enabled
4. Document findings per module/issue before adding the next parameter file
