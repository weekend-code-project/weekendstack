#!/usr/bin/env python3
"""List local (.lab) service URLs based on Traefik router rules in docker-compose files.

This repo already defines dual-domain Traefik rules like:
  traefik.http.routers.coder.rule=Host(`coder.${BASE_DOMAIN}`) || Host(`coder.lab`)

This script parses docker-compose*.yml, extracts Host(...) values, and prints URLs.

Usage:
  python3 tools/list_lab_urls.py
  python3 tools/list_lab_urls.py --all
  python3 tools/list_lab_urls.py --format markdown

Notes:
- By default, only explicit *.lab hostnames are shown.
- We do not try to query Docker or Traefik; this is static analysis of compose files.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
COMPOSE_GLOBS: Sequence[str] = (
    "docker-compose.yml",
    "docker-compose.*.yml",
)

HOST_RE = re.compile(r"Host\(`([^`]+)`\)")


@dataclass(frozen=True)
class Route:
    host: str
    scheme: str
    compose_file: str
    service: str
    router: str


def load_dotenv(dotenv_path: Path) -> Dict[str, str]:
    env: Dict[str, str] = {}
    if not dotenv_path.exists():
        return env

    for raw in dotenv_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
            value = value[1:-1]
        env[key] = value
    return env


_VAR_RE = re.compile(r"\$\{([^}]+)\}")


def expand_docker_vars(text: str, env: Dict[str, str], *, max_passes: int = 5) -> str:
    """Expand a small subset of docker-compose variable syntax.

    Supports:
      ${VAR}
      ${VAR:-default}

    Unknown variables are replaced with "" (empty).
    """

    def replace(match: re.Match[str]) -> str:
        expr = match.group(1)
        if ":-" in expr:
            var, default = expr.split(":-", 1)
            var = var.strip()
            default = default.strip()
            value = env.get(var)
            return value if value not in (None, "") else default
        return env.get(expr.strip(), "")

    out = text
    for _ in range(max_passes):
        new = _VAR_RE.sub(replace, out)
        if new == out:
            break
        out = new
    return out


def normalize_labels(labels: Any) -> List[Tuple[str, str]]:
    """Return [(key, value)] label pairs from either list or dict compose formats."""
    if not labels:
        return []

    pairs: List[Tuple[str, str]] = []
    if isinstance(labels, dict):
        for key, value in labels.items():
            pairs.append((str(key), str(value)))
        return pairs

    if isinstance(labels, list):
        for item in labels:
            if isinstance(item, str) and "=" in item:
                key, value = item.split("=", 1)
                pairs.append((key, value))
        return pairs

    return []


def iter_compose_files() -> Iterable[Path]:
    seen: set[Path] = set()
    for pattern in COMPOSE_GLOBS:
        for path in sorted(REPO_ROOT.glob(pattern)):
            if path.is_file() and path not in seen:
                seen.add(path)
                yield path


def collect_routes(env: Dict[str, str]) -> List[Route]:
    routes: List[Route] = []

    for compose_path in iter_compose_files():
        data = yaml.safe_load(compose_path.read_text(encoding="utf-8")) or {}
        services: Dict[str, dict] = (data.get("services") or {})
        for service_name, service_cfg in services.items():
            label_pairs = normalize_labels(service_cfg.get("labels"))

            router_tls: Dict[str, bool] = {}
            router_rules: Dict[str, str] = {}

            for key, value in label_pairs:
                if not key.startswith("traefik.http.routers."):
                    continue
                rest = key[len("traefik.http.routers.") :]
                if "." not in rest:
                    continue
                router, attr = rest.split(".", 1)

                expanded_value = expand_docker_vars(value, env)

                if attr == "rule":
                    router_rules[router] = expanded_value
                elif attr == "tls":
                    router_tls[router] = expanded_value.strip().lower() == "true"

            for router, rule in router_rules.items():
                hosts = HOST_RE.findall(rule)
                scheme = "https" if router_tls.get(router, False) else "http"
                for host in hosts:
                    routes.append(
                        Route(
                            host=host,
                            scheme=scheme,
                            compose_file=compose_path.name,
                            service=service_name,
                            router=router,
                        )
                    )

    # De-dupe while preserving useful metadata (keep first occurrence)
    uniq: Dict[Tuple[str, str], Route] = {}
    for route in routes:
        key = (route.scheme, route.host)
        if key not in uniq:
            uniq[key] = route
    return sorted(uniq.values(), key=lambda r: (r.host, r.scheme))


def main() -> None:
    parser = argparse.ArgumentParser(description="List Traefik-based service URLs")
    parser.add_argument(
        "--all",
        action="store_true",
        help="Include non-.lab hostnames too (e.g., public domains)",
    )
    parser.add_argument(
        "--format",
        choices=("text", "markdown", "json"),
        default="text",
        help="Output format",
    )
    args = parser.parse_args()

    env = load_dotenv(REPO_ROOT / ".env")
    routes = collect_routes(env)

    if not args.all:
        routes = [r for r in routes if r.host.endswith(".lab")]

    if args.format == "json":
        payload = [
            {
                "url": f"{r.scheme}://{r.host}",
                "host": r.host,
                "scheme": r.scheme,
                "compose_file": r.compose_file,
                "service": r.service,
                "router": r.router,
            }
            for r in routes
        ]
        print(json.dumps(payload, indent=2, sort_keys=False))
        return

    if args.format == "markdown":
        print("| URL | Service | Compose |")
        print("|---|---|---|")
        for r in routes:
            print(f"| {r.scheme}://{r.host} | {r.service} | {r.compose_file} |")
        return

    # text
    for r in routes:
        print(f"{r.scheme}://{r.host} ({r.service} in {r.compose_file})")


if __name__ == "__main__":
    main()
