# Adding A New Service

WeekendStack now treats [tools/env/mappings/service-metadata.json](/Volumes/workspace/utm/ravenbrain-workspace-scratch/weekendstack-agent-setup/tools/env/mappings/service-metadata.json) as the canonical service catalog. New services should be added there first so plan/apply/doctor/repair, summaries, and hardware validation all see the same data.

## Quick Start

Run the scaffolder:

```bash
./tools/setup/scaffold-service.sh \
  --id my-service \
  --display-name "My Service" \
  --description "What it does" \
  --profile productivity \
  --template productivity/my-service.env.example \
  --compose-file compose/docker-compose.productivity.yml \
  --activation-profile my-service \
  --subdomain my-service \
  --port 1234 \
  --selectable
```

This creates:
- a catalog entry
- an env template stub
- a compose snippet stub
- a baseline unit test

## Required Catalog Fields

Every service entry must define:
- `display_name`
- `description`
- `template`
- `profile`
- `compose_file`

Add these when applicable:
- `activation_profiles`
  - use when the compose profile differs from the base profile
- `selectable_service`
  - set `true` for optional extras like `paperclip` or `gitea`
- `subdomain`
  - required for correct tunnel and `.lab` URLs
- `ip_port`
  - required for good Local IP summaries/state output
- `first_run_mode`
  - one of `none`, `manual`, `installer-url`, `random-password-log`
- `first_run_path`
  - required with `installer-url`
- `required_directories`
  - relative paths under the repo root that setup/repair must ensure
- `resource_memory_gb` / `resource_disk_gb`
  - use for optional services that materially change hardware requirements

## Compose Registration Checklist

1. Add the service to the correct `compose/docker-compose.*.yml`.
2. Make sure the service’s `profiles:` match `activation_profiles`.
3. Add health checks where possible.
4. Add bind mounts only after deciding whether they belong under `files/` or `data/`.
5. If the service needs a generated password or first-run installer, set `first_run_mode` correctly.

## Validation Checklist

Before merging:

```bash
bash tools/test/unit/test_service_catalog.sh
bash tools/test/unit/test_setup_engine_config.sh
bash tools/test/unit/test_setup_engine_plan.sh
```

Then run at least one real flow:

```bash
./setup.sh --plan --config weekendstack.config.json
./setup.sh --apply --config weekendstack.config.json
./setup.sh --doctor
```

## Decision Rules

- If the service is optional inside a broader profile, make it a `selectable_service`.
- If it changes hardware requirements, record resource overrides in the catalog.
- If it needs manual browser onboarding, do not hide that. Encode it in `first_run_mode`.
- If it needs special cleanup protection, add preserve rules before enabling auto-cleanup.
