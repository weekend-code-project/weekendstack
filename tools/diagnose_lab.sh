#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load settings from .env if present
HOST_IP=""
SERVER_IP=""
PIHOLE_DNS_PORT=""
PIHOLE_WEB_PORT=""
if [[ -f "$REPO_ROOT/.env" ]]; then
  HOST_IP="$(grep -E '^HOST_IP=' "$REPO_ROOT/.env" | head -n 1 | cut -d= -f2- | tr -d '"\r')"
  SERVER_IP="$(grep -E '^SERVER_IP=' "$REPO_ROOT/.env" | head -n 1 | cut -d= -f2- | tr -d '"\r')"
  PIHOLE_DNS_PORT="$(grep -E '^PIHOLE_PORT_DNS=' "$REPO_ROOT/.env" | head -n 1 | cut -d= -f2- | tr -d '"\r')"
  PIHOLE_WEB_PORT="$(grep -E '^PIHOLE_PORT_WEB=' "$REPO_ROOT/.env" | head -n 1 | cut -d= -f2- | tr -d '"\r')"
fi

HOST_IP="${HOST_IP:-${SERVER_IP:-192.168.2.50}}"
PIHOLE_DNS_PORT="${PIHOLE_DNS_PORT:-53}"
PIHOLE_WEB_PORT="${PIHOLE_WEB_PORT:-8088}"

PIHOLE_IP="$HOST_IP"
TEST_HOST="${1:-coder.lab}"

echo "== Weekend Stack local (.lab) diagnostics =="
echo "Repo: $REPO_ROOT"
echo "Host IP (from .env): $HOST_IP"
echo "Pi-hole DNS: $PIHOLE_IP:$PIHOLE_DNS_PORT"
echo "Pi-hole Admin: http://$PIHOLE_IP:$PIHOLE_WEB_PORT/admin"
echo "Test hostname: $TEST_HOST"
echo

echo "-- 1) Docker containers (traefik + pihole) --"
( cd "$REPO_ROOT" && docker compose ps traefik pihole ) || true
echo

echo "-- 2) Host port listeners ($PIHOLE_DNS_PORT, 80, 443, $PIHOLE_WEB_PORT) --"
if command -v ss >/dev/null 2>&1; then
  ss -lntu 2>/dev/null | egrep ":(${PIHOLE_DNS_PORT}|80|443|${PIHOLE_WEB_PORT})\\b" || echo "No listeners found for expected ports (or insufficient permissions)."
elif command -v netstat >/dev/null 2>&1; then
  netstat -lntu 2>/dev/null | egrep ":(${PIHOLE_DNS_PORT}|80|443|${PIHOLE_WEB_PORT})\\b" || echo "No listeners found for expected ports (or insufficient permissions)."
else
  echo "Neither ss nor netstat found; skipping port check."
fi
echo

echo "-- 3) DNS query directly against Pi-hole ($PIHOLE_IP:$PIHOLE_DNS_PORT) --"
if command -v dig >/dev/null 2>&1; then
  dig +time=2 +tries=1 +short -p "$PIHOLE_DNS_PORT" @"$PIHOLE_IP" "$TEST_HOST" || true
elif command -v nslookup >/dev/null 2>&1; then
  if [[ "$PIHOLE_DNS_PORT" != "53" ]]; then
    echo "nslookup can't query a custom DNS port ($PIHOLE_DNS_PORT). Install dig (dnsutils/bind-tools) or use port 53."
  else
    nslookup "$TEST_HOST" "$PIHOLE_IP" || true
  fi
else
  echo "Neither dig nor nslookup found; skipping DNS check."
fi
echo

echo "-- 4) HTTP routing via Traefik (Host header) --"
if command -v curl >/dev/null 2>&1; then
  echo "Request: http://$HOST_IP/ with Host: $TEST_HOST"
  curl -sS -o /dev/null -D - "http://$HOST_IP/" -H "Host: $TEST_HOST" | head -n 20 || true
else
  echo "curl not found; skipping HTTP check."
fi

echo
cat <<'EOF'
== How to interpret results ==
- If step (3) times out: client can't reach Pi-hole on UDP/TCP 53 (VLAN/firewall) OR Pi-hole isn't bound to :53.
- If step (3) returns 192.168.2.50 but browsers can't resolve: your client is NOT using Pi-hole (secondary DNS, DoH/Private DNS).
- If step (4) shows a Traefik response (even 404): routing path to Traefik works; next check Traefik router rules.

macOS note:
- macOS can only use DNS servers on port 53 via system settings.
- If PIHOLE_PORT_DNS is not 53, you can still test with dig -p, but normal browsing won't use it.
EOF
