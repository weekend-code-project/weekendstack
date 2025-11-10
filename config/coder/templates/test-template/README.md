# Test Template - Minimal Baseline

This is a minimal test template with no parameters. It creates a basic workspace with:
- Docker container (ubuntu-based)
- Coder agent
- Persistent home volume

## Purpose

This template is used to test adding parameters one at a time to identify which parameter causes UI flickering during workspace updates.

## Usage

1. Start with this baseline (no parameters)
2. Add one parameter module at a time from `_trash/shared-template-modules/`
3. Test each addition for flickering
4. Identify the problematic parameter(s)
