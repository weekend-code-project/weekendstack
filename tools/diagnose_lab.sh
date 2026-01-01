#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load settings from .env if present
HOST_IP=""
SERVER_IP=""
PIHOLE_DNS_PORT=""
PIHOLE_WEB_PORT=""
if [[ -f "$REPO_ROOT/.env" ]]; then
  HOST_IP="$(grep -E '^HOST_IP=' "$REPO_ROOT/.env" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '"\r' || true)"
  SERVER_IP="$(grep -E '^SERVER_IP=' "$REPO_ROOT/.env" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '"\r' || true)"
  PIHOLE_DNS_PORT="$(grep -E '^PIHOLE_PORT_DNS=' "$REPO_ROOT/.env" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '"\r' || true)"
  PIHOLE_WEB_PORT="$(grep -E '^PIHOLE_PORT_WEB=' "$REPO_ROOT/.env" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '"\r' || true)"
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
  PIHOLE_RESULT=$(dig +time=2 +tries=1 +short -p "$PIHOLE_DNS_PORT" @"$PIHOLE_IP" "$TEST_HOST" 2>&1 || echo "FAILED")
  echo "$PIHOLE_RESULT"
elif command -v nslookup >/dev/null 2>&1; then
  if [[ "$PIHOLE_DNS_PORT" != "53" ]]; then
    echo "nslookup can't query a custom DNS port ($PIHOLE_DNS_PORT). Install dig (dnsutils/bind-tools) or use port 53."
    PIHOLE_RESULT="UNKNOWN"
  else
    PIHOLE_RESULT=$(nslookup "$TEST_HOST" "$PIHOLE_IP" 2>&1 | grep -A1 "^Name:" | grep "Address:" | awk '{print $2}' || echo "FAILED")
    nslookup "$TEST_HOST" "$PIHOLE_IP" || true
  fi
else
  echo "Neither dig nor nslookup found; skipping DNS check."
  PIHOLE_RESULT="UNKNOWN"
fi
echo

echo "-- 4) DNS query using SYSTEM resolver (what your browser uses) --"
SYSTEM_DNS_RESULT="UNKNOWN"
if command -v dig >/dev/null 2>&1; then
  echo "Querying: $TEST_HOST (using system DNS)"
  SYSTEM_DNS_OUTPUT=$(dig +time=2 +tries=1 "$TEST_HOST" 2>&1 || echo "QUERY_FAILED")
  SYSTEM_DNS_RESULT=$(echo "$SYSTEM_DNS_OUTPUT" | grep -A1 "^;; ANSWER SECTION:" | tail -1 | awk '{print $5}' || echo "FAILED")
  echo "$SYSTEM_DNS_OUTPUT" | head -20
  
  # Show which DNS server was used
  SYSTEM_DNS_SERVER=$(echo "$SYSTEM_DNS_OUTPUT" | grep "SERVER:" | awk '{print $3}' | sed 's/#.*//' || echo "UNKNOWN")
  echo
  echo "System DNS server used: $SYSTEM_DNS_SERVER"
elif command -v nslookup >/dev/null 2>&1; then
  echo "Querying: $TEST_HOST (using system DNS)"
  SYSTEM_DNS_OUTPUT=$(nslookup "$TEST_HOST" 2>&1 || echo "QUERY_FAILED")
  SYSTEM_DNS_RESULT=$(echo "$SYSTEM_DNS_OUTPUT" | grep -A1 "^Name:" | grep "Address:" | awk '{print $2}' || echo "FAILED")
  echo "$SYSTEM_DNS_OUTPUT"
  
  # Try to show DNS server
  SYSTEM_DNS_SERVER=$(echo "$SYSTEM_DNS_OUTPUT" | grep "^Server:" | awk '{print $2}' || echo "UNKNOWN")
  echo "System DNS server used: $SYSTEM_DNS_SERVER"
else
  echo "Neither dig nor nslookup found; can't test system DNS."
fi
echo

echo "-- 5) HTTP routing via Traefik (Host header) --"
if command -v curl >/dev/null 2>&1; then
  echo "Request: http://$HOST_IP/ with Host: $TEST_HOST"
  curl -sS -o /dev/null -D - "http://$HOST_IP/" -H "Host: $TEST_HOST" | head -n 20 || true
else
  echo "curl not found; skipping HTTP check."
fi

echo
echo "═══════════════════════════════════════════════════════════════"
echo "DIAGNOSIS & RECOMMENDATIONS:"
echo "═══════════════════════════════════════════════════════════════"

# Check if Pi-hole query worked
if [[ "$PIHOLE_RESULT" == "$HOST_IP" ]] || [[ "$PIHOLE_RESULT" == *"$HOST_IP"* ]]; then
  echo "✅ Pi-hole DNS is working correctly (returned $HOST_IP)"
else
  echo "❌ Pi-hole DNS query failed or returned wrong result: $PIHOLE_RESULT"
  echo "   → Check if Pi-hole container is running: docker compose ps pihole"
  echo "   → Check Pi-hole logs: docker compose logs pihole"
fi

# Check if system DNS is working
if [[ "$SYSTEM_DNS_RESULT" == "$HOST_IP" ]] || [[ "$SYSTEM_DNS_RESULT" == *"$HOST_IP"* ]]; then
  echo "✅ System DNS resolved $TEST_HOST correctly (returned $HOST_IP)"
  echo "   Your browser should be able to access http://$TEST_HOST"
elif [[ "$SYSTEM_DNS_RESULT" == "FAILED" ]] || [[ "$SYSTEM_DNS_RESULT" == "QUERY_FAILED" ]]; then
  echo "❌ System DNS CANNOT resolve $TEST_HOST"
  echo
  echo "   PROBLEM: Your device is NOT configured to use Pi-hole for DNS."
  echo
  echo "   CURRENT DNS SERVER: ${SYSTEM_DNS_SERVER:-Unknown}"
  echo "   EXPECTED DNS SERVER: $PIHOLE_IP (Pi-hole)"
  echo
  echo "   SOLUTION: Configure your device to use $PIHOLE_IP as DNS server."
  echo "   See: docs/dns-setup-guide.md for detailed instructions"
  echo
  echo "   Quick fixes:"
  echo "   1. Router DHCP: Set router to hand out $PIHOLE_IP as DNS (affects all devices)"
  echo "   2. Per-device: Configure this device to use $PIHOLE_IP as DNS"
  echo "   3. Testing only: Add to /etc/hosts: echo '$HOST_IP $TEST_HOST' | sudo tee -a /etc/hosts"
else
  echo "⚠️  System DNS returned unexpected result: $SYSTEM_DNS_RESULT"
  echo "   Expected: $HOST_IP"
  echo "   Check if another DNS server is intercepting queries"
fi

echo
echo "NEXT STEPS:"
if [[ "$SYSTEM_DNS_RESULT" == "$HOST_IP" ]] || [[ "$SYSTEM_DNS_RESULT" == *"$HOST_IP"* ]]; then
  echo "1. ✅ DNS is working! Try accessing: http://$TEST_HOST"
  echo "2. For HTTPS access, see: docs/local-https-setup.md"
else
  echo "1. Configure DNS using docs/dns-setup-guide.md"
  echo "2. Re-run this diagnostic: bash tools/diagnose_lab.sh"
  echo "3. Once DNS works, access services at http://$TEST_HOST"
fi
echo "═══════════════════════════════════════════════════════════════"
echo

cat <<'EOF'
== How to interpret results ==
- Step (3) tests Pi-hole directly: checks if Pi-hole container is working
- Step (4) tests system DNS: checks if YOUR DEVICE is using Pi-hole
- Step (5) tests Traefik routing: checks if reverse proxy is working

Common issues:
- Pi-hole works (3) but system DNS fails (4): Device not configured to use Pi-hole
  → Fix: Configure DNS per docs/dns-setup-guide.md
  
- Both DNS work but browser fails: TLS/certificate issue or browser cache
  → Fix: Clear browser cache, check HTTPS setup in docs/local-https-setup.md
  
- HTTP routing fails (5): Traefik configuration issue
  → Fix: Check docker compose ps traefik, review traefik logs

macOS note:
- macOS can only use DNS servers on port 53 via system settings.
- If PIHOLE_PORT_DNS is not 53, you can still test with dig -p, but normal browsing won't use it.
EOF
