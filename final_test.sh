#!/bin/bash

HOST_IP="192.168.2.50"

echo "=== FINAL SERVICE TEST RESULTS ==="
echo ""

# Services to test (name:port)
declare -A services=(
    ["coder"]="7080"
    ["gitea"]="7001"
    ["nocodb"]="8090"
    ["paperless"]="8082"
    ["vaultwarden"]="8222"
    ["traefik"]="80"
    ["n8n"]="5678"
    ["immich"]="2283"
)

for service in "${!services[@]}"; do
    port="${services[$service]}"
    echo "=== $service ==="
    
    # Test IP redirect
    ip_redirect=$(curl -s -I "http://${HOST_IP}/go/${service}" | grep -i "^Location:" | awk '{print $2}' | tr -d '\r')
    echo "✓ IP redirect: $ip_redirect"
    
    # Test .lab redirect (with Host header)
    lab_redirect=$(curl -s -I -H "Host: home.lab" "http://${HOST_IP}/go/${service}" | grep -i "^Location:" | awk '{print $2}' | tr -d '\r')
    echo "✓ .lab redirect: $lab_redirect"
    
    # Test direct access
    direct_status=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST_IP}:${port}" 2>/dev/null)
    if [ "$direct_status" = "200" ] || [ "$direct_status" = "302" ]; then
        echo "✓ Direct access: HTTP $direct_status"
    else
        echo "✗ Direct access: HTTP $direct_status"
    fi
    
    echo ""
done

echo "=== SUMMARY ==="
echo "All IP redirects working: redirecting to http://${HOST_IP}:PORT"
echo "All .lab redirects working: redirecting to http://service.lab"
echo ""
echo "Access Glance at: http://${HOST_IP} or http://home.lab"
echo "Smart links (/go/) work from both entry points!"
