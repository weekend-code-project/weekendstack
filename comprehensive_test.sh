#!/bin/bash

# Comprehensive service test script
# Tests ALL services for actual page loads, not just HTTP codes

HOST_IP="192.168.2.50"
TIMEOUT=5

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Services that require HTTPS (will be skipped for direct port test)
HTTPS_ONLY=("gitlab" "vaultwarden")

# Services that only work via .lab domain (not via IP:port)
LAB_ONLY=("traefik")

# Services without web UI (API-only services)
API_ONLY=("coder-registry")

# Complete service-to-port mapping (from docker ps)
declare -A SERVICES
SERVICES["activepieces"]=8087
SERVICES["anythingllm"]=3003
SERVICES["bytestash"]=8094
SERVICES["coder"]=7080
SERVICES["coder-registry"]=5001
SERVICES["docmost"]=8093
SERVICES["dozzle"]=9999
SERVICES["duplicati"]=8200
SERVICES["excalidraw"]=8092
SERVICES["filebrowser"]=8096
SERVICES["firefly"]=8086
SERVICES["focalboard"]=8097
SERVICES["gitea"]=7001
SERVICES["gitlab"]=8929
SERVICES["hoarder"]=3030
SERVICES["homeassistant"]=8123
SERVICES["immich"]=2283
SERVICES["it-tools"]=8091
SERVICES["kavita"]=5000
SERVICES["librechat"]=3080
SERVICES["localai"]=8084
SERVICES["mealie"]=9925
SERVICES["n8n"]=5678
SERVICES["navidrome"]=4533
SERVICES["netbox"]=8484
SERVICES["netdata"]=19999
SERVICES["nocodb"]=8090
SERVICES["nodered"]=1880
SERVICES["open-webui"]=3000
SERVICES["paperless"]=8082
SERVICES["pihole"]="8088/admin"  # Special case: needs /admin path
SERVICES["portainer"]=9000
SERVICES["postiz"]=8095
SERVICES["searxng"]=4000
SERVICES["traefik"]="lab-only"  # Special: only via traefik.lab
SERVICES["trilium"]=8085
SERVICES["uptime-kuma"]=3001
SERVICES["vikunja"]=3456
SERVICES["wger"]=8089
SERVICES["whisper"]=9002
SERVICES["wud"]=3002

echo "=== COMPREHENSIVE SERVICE TEST ==="
echo "Testing all ${#SERVICES[@]} services..."
echo ""

PASS=0
FAIL=0
SKIP=0

for service in "${!SERVICES[@]}"; do
    port="${SERVICES[$service]}"
    
    # Check if service requires HTTPS
    if [[ " ${HTTPS_ONLY[@]} " =~ " ${service} " ]]; then
        echo -e "${YELLOW}⏭️  $service${NC}: SKIPPED (requires HTTPS)"
        ((SKIP++))
        continue
    fi
    
    # Check if service is lab-only
    if [[ "$port" == "lab-only" ]] || [[ " ${LAB_ONLY[@]} " =~ " ${service} " ]]; then
        echo -e "${BLUE}🔷 $service${NC}: .lab domain only (requires Pi-hole DNS)"
        ((SKIP++))
        continue
    fi
    
    # Check if service is API-only (no web UI)
    if [[ " ${API_ONLY[@]} " =~ " ${service} " ]]; then
        echo -e "${BLUE}🔷 $service${NC}: API-only (no web UI)"
        ((SKIP++))
        continue
    fi
    
    # Build URL based on port format
    if [[ "$port" == *"/"* ]]; then
        # Port includes path (like "8088/admin")
        URL="http://${HOST_IP}:${port}"
    else
        URL="http://${HOST_IP}:${port}"
    fi
    
    # Test direct access WITH redirect following to get actual content
    HTTP_CODE=$(curl -sL -o /dev/null -w "%{http_code}" --max-time $TIMEOUT "$URL" 2>/dev/null)
    CONTENT_SIZE=$(curl -sL --max-time $TIMEOUT "$URL" 2>/dev/null | wc -c)
    
    # Check if we got a valid response and actual content
    if [[ "$HTTP_CODE" == "200" ]]; then
        if [[ "$CONTENT_SIZE" -gt 200 ]]; then
            echo -e "${GREEN}✅ $service${NC}: $URL (${CONTENT_SIZE}b)"
            ((PASS++))
        else
            echo -e "${RED}❌ $service${NC}: $URL (HTTP 200 but tiny page: ${CONTENT_SIZE}b)"
            ((FAIL++))
        fi
    elif [[ "$HTTP_CODE" == "401" ]] || [[ "$HTTP_CODE" == "400" ]]; then
        # Auth required or CORS - service is running
        echo -e "${GREEN}✅ $service${NC}: $URL (HTTP $HTTP_CODE - auth/CORS)"
        ((PASS++))
    elif [[ -z "$HTTP_CODE" ]] || [[ "$HTTP_CODE" == "000" ]]; then
        echo -e "${RED}❌ $service${NC}: $URL (timeout/connection refused)"
        ((FAIL++))
    elif [[ "$HTTP_CODE" == "502" ]] || [[ "$HTTP_CODE" == "503" ]] || [[ "$HTTP_CODE" == "504" ]]; then
        echo -e "${RED}❌ $service${NC}: $URL (HTTP $HTTP_CODE - service down)"
        ((FAIL++))
    else
        echo -e "${RED}❌ $service${NC}: $URL (HTTP $HTTP_CODE)"
        ((FAIL++))
    fi
done

echo ""
echo "=== RESULTS ==="
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"
echo -e "${YELLOW}Skipped: $SKIP${NC}"
echo "Total: ${#SERVICES[@]}"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "⚠️  Some services failed. Check the output above for details."
    exit 1
else
    echo ""
    echo "✅ All accessible services are working!"
fi
