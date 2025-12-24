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


def choose_mode(host: str) -> str:
    host = (host or "").strip().lower()
    if host.endswith(f".{LAB_DOMAIN}"):
        return "lab"
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

        if mode == "lab":
            target_host = f"{service}.{LAB_DOMAIN}"
            scheme = LAB_SCHEME
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
