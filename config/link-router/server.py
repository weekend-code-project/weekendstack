import os
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def _env(name: str, default: str) -> str:
    value = os.getenv(name)
    if value is None:
        return default
    value = value.strip()
    return value if value else default


LAB_DOMAIN = _env("LAB_DOMAIN", "lab")
BASE_DOMAIN = _env("BASE_DOMAIN", "")
LAB_SCHEME = _env("LAB_SCHEME", "http")
EXTERNAL_SCHEME = _env("EXTERNAL_SCHEME", "https")
HOST_IP = _env("HOST_IP", "192.168.2.50")

# Port mappings for IP-based access (from docker ps output)
PORT_MAP = {
    # Core services
    "coder": 7080,
    "gitea": 7001,
    "gitlab": 8929,  # Requires HTTPS
    "nocodb": 8090,
    "paperless": 8082,
    "vaultwarden": 8222,  # Requires HTTPS
    "link-router": None,  # Internal only
    "glance": None,  # Access via / (Traefik routes it)
    
    # Dev & AI
    "n8n": 5678,
    "activepieces": 8087,
    "anythingllm": 3003,
    "librechat": 3080,
    "localai": 8084,
    "open-webui": 3000,
    "whisper": 9002,
    
    # Productivity
    "vikunja": 3456,
    "trilium": 8085,
    "focalboard": 8097,
    "hoarder": 3030,
    "docmost": 8093,
    "nodered": 1880,
    "postiz": 8095,
    
    # Media
    "immich": 2283,
    "navidrome": 4533,
    "kavita": 5000,
    
    # Personal
    "firefly": 8086,
    "mealie": 9925,
    "wger": 8089,
    
    # Monitoring
    "portainer": 9000,
    "uptime-kuma": 3001,
    "uptimekuma": 3001,  # Alias
    "netdata": 19999,
    "dozzle": 9999,
    "wud": 3002,
    "homeassistant": 8123,
    
    # Networking & Infrastructure  
    "traefik": None,  # Special: only accessible via traefik.lab (Host-based routing)
    "pihole": "8088/admin",  # Special case: needs /admin path
    
    # Tools
    "bytestash": 8094,
    "it-tools": 8091,
    "ittools": 8091,  # Alias
    "excalidraw": 8092,
    "filebrowser": 8096,
    "duplicati": 8200,
    "searxng": 4000,
    "netbox": 8484,
    "coder-registry": 5001,
}


def choose_mode(host: str) -> str:
    host = (host or "").strip().lower()
    if host.endswith(f".{LAB_DOMAIN}"):
        return "lab"
    # Check if it's an IP address with port
    if any(char.isdigit() for char in host.split(":")[0]):
        return "ip"
    return "external"


class Handler(BaseHTTPRequestHandler):
    server_version = "weekendstack-link-router/1.0"

    def do_GET(self):
        self._handle()

    def do_HEAD(self):
        self._handle(head_only=True)

    def _handle(self, head_only: bool = False):
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path or "/"

        if not path.startswith("/go/"):
            self.send_response(404)
            self.end_headers()
            return

        rest = path[len("/go/") :]
        rest = rest.lstrip("/")
        if not rest:
            self.send_response(400)
            self.end_headers()
            return

        # /go/<service>/<optional-path>
        parts = rest.split("/", 1)
        service = parts[0].strip()
        tail = parts[1] if len(parts) > 1 else ""

        if not service or any(ch in service for ch in ".: "):
            self.send_response(400)
            self.end_headers()
            return

        host = self.headers.get("Host", "")
        mode = choose_mode(host)

        # Special handling for services that only work via .lab domain
        if service in ["traefik", "glance"]:
            # Always redirect to .lab domain for these services
            target_host = f"{service}.{LAB_DOMAIN}"
            scheme = LAB_SCHEME
            target_path = "/" + tail if tail else "/"
        elif mode == "lab":
            target_host = f"{service}.{LAB_DOMAIN}"
            scheme = LAB_SCHEME
            target_path = "/" + tail if tail else "/"
        elif mode == "ip":
            # Use IP:PORT format
            port_or_path = PORT_MAP.get(service)
            if port_or_path is None:
                # Services with None port (like link-router, glance) - fallback to .lab
                target_host = f"{service}.{LAB_DOMAIN}"
                scheme = LAB_SCHEME
                target_path = "/" + tail if tail else "/"
            else:
                # Handle special case where port includes path (e.g., "8088/admin")
                if isinstance(port_or_path, str) and "/" in port_or_path:
                    port, base_path = port_or_path.split("/", 1)
                    target_host = f"{HOST_IP}:{port}"
                    # Combine base_path with tail
                    target_path = "/" + base_path.rstrip("/")
                    if tail:
                        target_path += "/" + tail
                else:
                    target_host = f"{HOST_IP}:{port_or_path}"
                    target_path = "/" + tail if tail else "/"
                scheme = "http"
        else:
            if not BASE_DOMAIN:
                self.send_response(500)
                self.end_headers()
                return
            target_host = f"{service}.{BASE_DOMAIN}"
            scheme = EXTERNAL_SCHEME
            target_path = "/" + tail if tail else "/"

        target = urllib.parse.urlunsplit(
            (scheme, target_host, target_path, parsed.query or "", "")
        )

        self.send_response(302)
        self.send_header("Location", target)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

        if not head_only:
            self.wfile.write(b"redirect\n")


def main() -> None:
    port = int(_env("PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
