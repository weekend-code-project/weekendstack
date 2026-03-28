#!/bin/bash
# Unit tests for Pi-hole networking defaults

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Pi-hole Networking"

test_case "Pi-hole DNS ports bind to HOST_IP instead of all interfaces"
if grep -q '\${HOST_IP}:\${PIHOLE_PORT_DNS:-53}:53/tcp' "$PROJECT_ROOT/compose/docker-compose.networking.yml" && \
   grep -q '\${HOST_IP}:\${PIHOLE_PORT_DNS:-53}:53/udp' "$PROJECT_ROOT/compose/docker-compose.networking.yml" && \
   ! grep -q '^[[:space:]]*-[[:space:]]*"\${PIHOLE_PORT_DNS:-53}:53/tcp"$' "$PROJECT_ROOT/compose/docker-compose.networking.yml" && \
   ! grep -q '^[[:space:]]*-[[:space:]]*"\${PIHOLE_PORT_DNS:-53}:53/udp"$' "$PROJECT_ROOT/compose/docker-compose.networking.yml"; then
    test_pass
else
    test_fail "Expected Pi-hole DNS ports to bind specifically to HOST_IP"
fi

test_case "Pi-hole uses v6 FTLCONF settings for DNS behavior"
if grep -q "FTLCONF_dns_listeningMode: 'ALL'" "$PROJECT_ROOT/compose/docker-compose.networking.yml" && \
   grep -q "FTLCONF_misc_etc_dnsmasq_d: 'true'" "$PROJECT_ROOT/compose/docker-compose.networking.yml" && \
   grep -q 'FTLCONF_dns_upstreams: |-' "$PROJECT_ROOT/compose/docker-compose.networking.yml" && \
   ! grep -q 'DNSMASQ_LISTENING:' "$PROJECT_ROOT/compose/docker-compose.networking.yml" && \
   ! grep -q 'PIHOLE_DNS_:' "$PROJECT_ROOT/compose/docker-compose.networking.yml"; then
    test_pass
else
    test_fail "Expected Pi-hole compose config to use v6 FTLCONF DNS settings"
fi

test_suite_end
