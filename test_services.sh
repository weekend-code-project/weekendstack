#!/bin/bash

HOST_IP="192.168.2.50"

echo "=== Testing Services ==="
echo ""

# Test function
test_service() {
    local service=$1
    local port=$2
    
    echo "Testing: $service"
    
    # Test /go/ redirect via IP
    ip_redirect=$(curl -s -I "http://${HOST_IP}/go/${service}" | grep -i "^Location:" | awk '{print $2}' | tr -d '\r')
    echo "  IP redirect: $ip_redirect"
    
    # Test /go/ redirect via .lab
    lab_redirect=$(curl -s -I "http://home.lab/go/${service}" | grep -i "^Location:" | awk '{print $2}' | tr -d '\r')
    echo "  .lab redirect: $lab_redirect"
    
    # Test direct IP access
    ip_status=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST_IP}:${port}" 2>/dev/null)
    echo "  Direct IP (${HOST_IP}:${port}): HTTP $ip_status"
    
    # Test .lab access
    lab_status=$(curl -s -o /dev/null -w "%{http_code}" "http://${service}.lab" 2>/dev/null)
    echo "  .lab (${service}.lab): HTTP $lab_status"
    
    echo ""
}

# Test key services
test_service "coder" "7080"
test_service "gitea" "7000"
test_service "nocodb" "7011"
test_service "paperless" "8082"
test_service "vaultwarden" "8222"
test_service "traefik" "80"
test_service "n8n" "7012"
test_service "immich" "2283"
