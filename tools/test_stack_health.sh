#!/bin/bash
# Stack Health Test Script
# Tests container status, Traefik routing, and HTTP/HTTPS access

# Don't exit on errors - we want to collect all test results
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables (only key=value lines, no comments)
if [ -f .env ]; then
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        # Remove quotes from value if present
        value="${value%\"}"
        value="${value#\"}"
        export "$key=$value"
    done < <(grep -E '^[A-Z_]+=.*' .env)
fi

LAB_DOMAIN=${LAB_DOMAIN:-lab}
BASE_DOMAIN=${BASE_DOMAIN:-weekendcodeproject.dev}
HOST_IP=${HOST_IP:-192.168.2.50}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Weekend Stack Health Check${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to print test result
print_result() {
    local test_name=$1
    local result=$2
    local details=$3
    
    if [ "$result" = "PASS" ]; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        [ -n "$details" ] && echo -e "    ${details}"
    elif [ "$result" = "WARN" ]; then
        echo -e "  ${YELLOW}⚠${NC} $test_name"
        [ -n "$details" ] && echo -e "    ${details}"
    else
        echo -e "  ${RED}✗${NC} $test_name"
        [ -n "$details" ] && echo -e "    ${details}"
    fi
}

# Test 1: Check if Traefik is running
echo -e "${YELLOW}[1/6] Checking Core Services...${NC}"
if docker ps --filter "name=traefik" --filter "status=running" | grep -q traefik; then
    traefik_status=$(docker ps --filter "name=traefik" --format "{{.Status}}")
    print_result "Traefik Container" "PASS" "Status: $traefik_status"
    TRAEFIK_UP=1
else
    print_result "Traefik Container" "FAIL" "Not running or not found"
    TRAEFIK_UP=0
fi

# Test 2: Check Traefik API accessibility
if [ $TRAEFIK_UP -eq 1 ]; then
    if curl -s http://localhost:8081/api/http/routers > /dev/null 2>&1; then
        router_count=$(curl -s http://localhost:8081/api/http/routers | jq -r '. | length')
        print_result "Traefik API" "PASS" "Discovered $router_count routers"
    else
        print_result "Traefik API" "FAIL" "Cannot access API on port 8081"
    fi
fi
echo ""

# Test 3: Check critical containers
echo -e "${YELLOW}[2/6] Checking Critical Containers...${NC}"
critical_containers=("traefik" "glance" "coder" "coder-database" "error-pages")
for container in "${critical_containers[@]}"; do
    if docker ps --filter "name=^${container}$" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
        print_result "$container" "PASS"
    else
        status=$(docker ps -a --filter "name=^${container}$" --format "{{.Status}}" 2>/dev/null || echo "not found")
        print_result "$container" "FAIL" "Status: $status"
    fi
done
echo ""

# Test 4: Check redirect middleware
echo -e "${YELLOW}[3/6] Checking HTTP→HTTPS Redirect Middleware...${NC}"
if [ $TRAEFIK_UP -eq 1 ]; then
    if curl -s http://localhost:8081/api/http/middlewares/redirect-to-https@file > /dev/null 2>&1; then
        middleware_status=$(curl -s http://localhost:8081/api/http/middlewares/redirect-to-https@file | jq -r '.status')
        usedby_count=$(curl -s http://localhost:8081/api/http/middlewares/redirect-to-https@file | jq -r '.usedBy | length')
        print_result "redirect-to-https middleware" "PASS" "Status: $middleware_status, Used by: $usedby_count routers"
    else
        print_result "redirect-to-https middleware" "FAIL" "Middleware not found - check dynamic config files"
    fi
fi
echo ""

# Test 5: Test HTTP→HTTPS redirects for key services
echo -e "${YELLOW}[4/6] Testing HTTP→HTTPS Redirects...${NC}"
test_services=(
    "coder.${LAB_DOMAIN}"
    "home.${LAB_DOMAIN}"
    "gitea.${LAB_DOMAIN}"
    "vaultwarden.${LAB_DOMAIN}"
    "n8n.${LAB_DOMAIN}"
    "paperless.${LAB_DOMAIN}"
)

for service in "${test_services[@]}"; do
    response=$(curl -s -o /dev/null -w "%{http_code}|%{redirect_url}" -H "Host: $service" http://127.0.0.1/ 2>/dev/null || echo "000|")
    http_code=$(echo $response | cut -d'|' -f1)
    redirect_url=$(echo $response | cut -d'|' -f2)
    
    if [ "$http_code" = "302" ] || [ "$http_code" = "301" ]; then
        if [[ "$redirect_url" == https://* ]]; then
            print_result "$service" "PASS" "→ $redirect_url"
        else
            print_result "$service" "WARN" "Redirects but not to HTTPS: $redirect_url"
        fi
    elif [ "$http_code" = "200" ]; then
        print_result "$service" "FAIL" "Returns 200 (no redirect)"
    elif [ "$http_code" = "404" ]; then
        print_result "$service" "FAIL" "Not found (404) - router not configured"
    else
        print_result "$service" "FAIL" "HTTP $http_code"
    fi
done
echo ""

# Test 6: Test HTTPS access for key services
echo -e "${YELLOW}[5/6] Testing HTTPS Access...${NC}"
for service in "${test_services[@]}"; do
    response=$(curl -sk -o /dev/null -w "%{http_code}" --resolve "$service:443:127.0.0.1" "https://$service/" 2>/dev/null || echo "000")
    
    if [ "$response" = "200" ]; then
        print_result "$service (HTTPS)" "PASS"
    elif [ "$response" = "404" ]; then
        print_result "$service (HTTPS)" "FAIL" "Not found (404)"
    elif [ "$response" = "000" ]; then
        print_result "$service (HTTPS)" "FAIL" "Connection failed"
    else
        print_result "$service (HTTPS)" "WARN" "HTTP $response"
    fi
done
echo ""

# Test 7: Check for containers with errors
echo -e "${YELLOW}[6/6] Checking for Container Errors...${NC}"
error_containers=$(docker ps -a --filter "status=exited" --filter "status=dead" --format "{{.Names}}: {{.Status}}" 2>/dev/null | grep -v "Exited (0)" || true)

if [ -z "$error_containers" ]; then
    print_result "Container Health" "PASS" "No containers in error state"
else
    print_result "Container Health" "WARN" "Some containers not running:"
    echo "$error_containers" | while read line; do
        echo -e "    ${RED}→${NC} $line"
    done
fi
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Count running containers
total_containers=$(docker ps -a | grep -v "CONTAINER ID" | wc -l)
running_containers=$(docker ps | grep -v "CONTAINER ID" | wc -l)
echo -e "Containers: ${GREEN}$running_containers${NC} running / $total_containers total"

# Traefik stats
if [ $TRAEFIK_UP -eq 1 ]; then
    routers=$(curl -s http://localhost:8081/api/http/routers 2>/dev/null | jq -r '. | length' || echo "0")
    services=$(curl -s http://localhost:8081/api/http/services 2>/dev/null | jq -r '. | length' || echo "0")
    echo -e "Traefik: ${GREEN}$routers${NC} routers, ${GREEN}$services${NC} services"
fi

echo ""
echo -e "${BLUE}Quick Diagnostics:${NC}"
echo -e "  View Traefik dashboard: http://localhost:8081/dashboard/"
echo -e "  View all routers:       curl -s http://localhost:8081/api/http/routers | jq"
echo -e "  View container logs:    docker logs <container-name>"
echo -e "  Restart stack:          docker compose down && docker compose up -d"
echo ""
