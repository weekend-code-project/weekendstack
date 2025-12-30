import os
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


# Global cache for tunnel availability check
_tunnel_check_cache = {"available": True, "last_check": 0}
TUNNEL_CHECK_INTERVAL = 30  # Check every 30 seconds


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
FORCE_LINK_MODE = _env("FORCE_LINK_MODE", "").lower()  # Options: "local", "external", "" (auto-detect)

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
    "openwebui": 3000,  # Alias
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
    "resourcespace": 8099,
    
    # Monitoring
    "cockpit": 9090,  # Cockpit web interface
    "portainer": 9000,
    "uptime-kuma": 3001,
    "uptimekuma": 3001,  # Alias
    "netdata": 19999,
    "dozzle": 9999,
    "wud": 3002,
    "homeassistant": 8123,
    "speedtest": 8765,
    
    # Networking & Infrastructure  
    "traefik": 8081,  # Traefik API/dashboard (insecure mode)
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


def is_tunnel_available() -> bool:
    """Check if external tunnel is available by trying to reach BASE_DOMAIN"""
    import time
    
    global _tunnel_check_cache
    
    # Use cached result if checked recently
    now = time.time()
    if now - _tunnel_check_cache["last_check"] < TUNNEL_CHECK_INTERVAL:
        return _tunnel_check_cache["available"]
    
    # No BASE_DOMAIN configured = no tunnel
    if not BASE_DOMAIN:
        _tunnel_check_cache["available"] = False
        _tunnel_check_cache["last_check"] = now
        return False
    
    # Try to reach glance.BASE_DOMAIN
    try:
        test_url = f"{EXTERNAL_SCHEME}://glance.{BASE_DOMAIN}"
        req = urllib.request.Request(test_url, method="HEAD")
        with urllib.request.urlopen(req, timeout=2) as response:
            available = response.status < 500
    except Exception:
        available = False
    
    _tunnel_check_cache["available"] = available
    _tunnel_check_cache["last_check"] = now
    return available


def choose_mode(host: str) -> str:
    # Check if mode is forced via environment variable
    if FORCE_LINK_MODE == "local":
        return "lab"
    elif FORCE_LINK_MODE == "external":
        return "external"
    
    # Auto-detect based on incoming Host header
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

        # Check for /go-external/ (force external) or /go/ (auto-detect)
        force_external = False
        if path.startswith("/go-external/"):
            force_external = True
            rest = path[len("/go-external/") :]
        elif path.startswith("/go/"):
            rest = path[len("/go/") :]
        else:
            self.send_response(404)
            self.end_headers()
            return

        rest = rest.lstrip("/")
        if not rest:
            self.send_response(400)
            self.end_headers()
            return

        # /go/<service>/<optional-path> or /go-external/<service>/<optional-path>
        parts = rest.split("/", 1)
        service = parts[0].strip()
        tail = parts[1] if len(parts) > 1 else ""

        if not service or any(ch in service for ch in ".: "):
            self.send_response(400)
            self.end_headers()
            return

        host = self.headers.get("Host", "")
        
        # Detect if incoming request is HTTPS by checking X-Forwarded-Proto header
        forwarded_proto = self.headers.get("X-Forwarded-Proto", "").lower()
        incoming_scheme = "https" if forwarded_proto == "https" else "http"
        
        # If force_external and tunnel is available, use external mode
        # Otherwise, fall back to auto-detection (respects IP/lab/external)
        if force_external and is_tunnel_available():
            mode = "external"
        else:
            mode = choose_mode(host)

        # Special handling for services using Host-based routing
        if service == "glance":
            # Glance requires specific Host header - always use .lab domain
            target_host = f"{service}.{LAB_DOMAIN}"
            scheme = incoming_scheme  # Use the same scheme as incoming request
            target_path = "/" + tail if tail else "/"
        elif mode == "lab":
            target_host = f"{service}.{LAB_DOMAIN}"
            scheme = incoming_scheme  # Use the same scheme as incoming request
            target_path = "/" + tail if tail else "/"
        elif mode == "ip":
            # Use IP:PORT format
            port_or_path = PORT_MAP.get(service)
            if port_or_path is None:
                # Services with None port (like link-router, glance) - fallback to .lab
                target_host = f"{service}.{LAB_DOMAIN}"
                scheme = incoming_scheme  # Use the same scheme as incoming request
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
