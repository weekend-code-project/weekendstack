#!/usr/bin/env python3
"""Generate docs/profile-matrix.md from docker compose service metadata."""

from __future__ import annotations

from collections import OrderedDict
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = REPO_ROOT / "docs/profile-matrix.md"

PROFILE_COLUMNS: Sequence[str] = (
    "default",
    "all",
    "gpu",
    "ai",
    "core",
    "dev",
    "development",
    "dev-tools",
    "gitlab",
    "proxy",
    "networking",
    "automation",
    "media",
    "monitoring",
    "personal",
    "productivity",
)

CATEGORY_MAP: "OrderedDict[str, str]" = OrderedDict(
    [
        ("docker-compose.ai.yml", "AI & ML"),
        ("docker-compose.core.yml", "Core"),
        ("docker-compose.dev.yml", "Development"),
        ("docker-compose.productivity.yml", "Productivity"),
        ("docker-compose.networking.yml", "Networking"),
        ("docker-compose.automation.yml", "Automation"),
        ("docker-compose.media.yml", "Media"),
        ("docker-compose.monitoring.yml", "Monitoring"),
        ("docker-compose.personal.yml", "Personal"),
    ]
)

CATEGORY_ORDER: Sequence[str] = (
    "AI & ML",
    "Core",
    "Development",
    "Productivity",
    "Networking",
    "Automation",
    "Media",
    "Monitoring",
    "Personal",
)

HEADER = """# Profile-Service Matrix

This matrix shows which Docker Compose profiles start each service in the Weekend Stack. Combine the columns to quickly decide which `docker compose --profile ...` flags you need without digging through every compose file.

> NOTE: Table auto-generated via `tools/generate_profile_matrix.py`. Edit compose files or this script rather than the table directly.

## Legend
- `default`: service has **no explicit profile** and is always part of the base selection (runs on `docker compose up` and whenever any profile is requested).
- Other columns match the profile names used across the compose files.
- `✓` means the service declares that profile.

<!-- PROFILE-MATRIX:START -->
"""

FOOTER = """
<!-- PROFILE-MATRIX:END -->

## Usage Patterns
- **Start everything (default + GPU)**: `docker compose up -d` uses the `x-default-profile` (`all` + `gpu`).
- **Skip GPU workloads**: `docker compose --profile all up -d` omits every `gpu`-only row.
- **Targeted groups**: chain profiles, e.g. `docker compose --profile dev --profile networking up -d` (Coder + Traefik) or `docker compose --profile productivity --profile personal up -d` (office + lifestyle).
- **Single-service helpers**: use custom names like `--profile gitlab` when you only need heavy services temporarily.
- **Always-on dependencies** (`default` column) follow their parent apps; consider adding profile tags later if you want those DB/Redis containers to stay dormant until requested.
"""


def load_compose_services() -> List[Tuple[str, str, List[str]]]:
    """Return (category, service, profiles) tuples discovered from compose files."""
    entries: List[Tuple[str, str, List[str]]] = []
    for file_name, category in CATEGORY_MAP.items():
        compose_path = REPO_ROOT / file_name
        if not compose_path.exists():
            continue
        data = yaml.safe_load(compose_path.read_text()) or {}
        services: Dict[str, dict] = data.get("services", {}) or {}
        for service_name, service_cfg in services.items():
            profiles = service_cfg.get("profiles")
            if not profiles:
                profiles = ["default"]
            entries.append((category, service_name, list(profiles)))
    return entries


def sort_key(entry: Tuple[str, str, List[str]]) -> Tuple[int, str]:
    category, service_name, _ = entry
    try:
        category_index = CATEGORY_ORDER.index(category)
    except ValueError:
        category_index = len(CATEGORY_ORDER)
    return (category_index, service_name)


def build_table(entries: Iterable[Tuple[str, str, List[str]]]) -> str:
    lines = []
    header_cells = ["Category", "Service", *PROFILE_COLUMNS]
    header_line = "| " + " | ".join(header_cells) + " |"
    separator_line = "| " + " | ".join(["---"] * len(header_cells)) + " |"
    lines.extend([header_line, separator_line])

    for category, service, profiles in sorted(entries, key=sort_key):
        profile_set = set(profiles)
        row = [category, service]
        for column in PROFILE_COLUMNS:
            row.append("✓" if column in profile_set else "")
        lines.append("| " + " | ".join(row) + " |")
    return "\n".join(lines)


def main() -> None:
    table = build_table(load_compose_services())
    OUTPUT_PATH.write_text("\n".join([HEADER.strip(), table, FOOTER.strip()]) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
