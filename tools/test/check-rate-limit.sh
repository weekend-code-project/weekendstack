#!/bin/bash
# Check Docker Hub rate limit status without consuming pulls
# This is a safe utility that doesn't count against rate limits

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_docker_rate_limit() {
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Warning: jq not installed, using basic parsing${NC}"
        
        # Fallback: check if authenticated via docker info
        if docker info 2>/dev/null | grep -q "Username:"; then
            local docker_user=$(docker info 2>/dev/null | grep "Username:" | awk '{print $2}')
            echo "Status: Authenticated as '$docker_user'"
            echo "Limit: 200 pulls per 6 hours (authenticated)"
            echo "Remaining: Unknown (jq required for exact count)"
        else
            echo "Status: Anonymous"
            echo "Limit: 100 pulls per 6 hours (anonymous)"
            echo "Remaining: Unknown (jq required for exact count)"
        fi
        return 0
    fi
    
    # Get authentication token (anonymous or authenticated)
    local token=$(curl -sf "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" 2>/dev/null | jq -r '.token' 2>/dev/null)
    
    if [[ -z "$token" ]] || [[ "$token" == "null" ]]; then
        echo -e "${RED}Error: Unable to get authentication token${NC}"
        echo "Status: Unknown"
        return 1
    fi
    
    # Query rate limit headers
    local response=$(curl -sf -H "Authorization: Bearer $token" \
        -I "https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest" 2>/dev/null)
    
    if [[ -z "$response" ]]; then
        echo -e "${RED}Error: Unable to query rate limit endpoint${NC}"
        return 1
    fi
    
    # Parse rate limit headers
    local limit=$(echo "$response" | grep -i "ratelimit-limit:" | awk -F'[:;]' '{print $2}' | tr -d ' \r')
    local remaining=$(echo "$response" | grep -i "ratelimit-remaining:" | awk -F'[:;]' '{print $2}' | tr -d ' \r')
    
    if [[ -z "$limit" ]] || [[ -z "$remaining" ]]; then
        # Fallback: check if authenticated
        if docker info 2>/dev/null | grep -q "Username:"; then
            local docker_user=$(docker info 2>/dev/null | grep "Username:" | awk '{print $2}')
            echo "Status: Authenticated as '$docker_user'"
            echo "Limit: 200 pulls per 6 hours"
            echo "Remaining: Unknown (headers not available)"
        else
            echo "Status: Anonymous"
            echo "Limit: 100 pulls per 6 hours"
            echo "Remaining: Unknown (headers not available)"
        fi
        return 0
    fi
    
    # Calculate used pulls
    local used=$((limit - remaining))
    
    # Determine status color
    local status_msg=""
    if [[ $remaining -le 10 ]]; then
        status_msg="${RED}CRITICAL${NC}"
    elif [[ $remaining -le 50 ]]; then
        status_msg="${YELLOW}WARNING${NC}"
    else
        status_msg="${GREEN}OK${NC}"
    fi
    
    # Display results
    echo -e "Status: $status_msg"
    echo "Limit: $limit pulls per 6 hours"
    echo "Remaining: $remaining pulls"
    echo "Used: $used pulls"
    
    # Determine if authenticated
    if [[ $limit -ge 200 ]]; then
        local docker_user=$(docker info 2>/dev/null | grep "Username:" | awk '{print $2}')
        echo "Account: Authenticated as '$docker_user'"
    else
        echo "Account: Anonymous (consider authenticating: docker login)"
    fi
    
    return 0
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Docker Hub Rate Limit Status"
    echo "=============================="
    echo ""
    check_docker_rate_limit
    echo ""
    echo "Note: This check does NOT consume any pulls from your rate limit."
fi
