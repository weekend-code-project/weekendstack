#!/bin/bash
# harness/scenarios/04-both-domains.sh
# Scenario: Both Cloudflare Tunnel (external) and Pi-Hole (local) configured.
#
# Pre-requisites: ~/.weekendstack/test-secrets with CF_API_TOKEN + CF_ZONE_DOMAIN

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="${WEEKENDSTACK_DIR:-/home/ubuntu/weekendstack}"
SCENARIO_NAME="04-both-domains"

source "$HARNESS_DIR/lib/secrets.sh"
source "$HARNESS_DIR/lib/assertions.sh"
source "$HARNESS_DIR/lib/snapshot.sh"
source "$HARNESS_DIR/lib/teardown.sh"

echo "============================================================"
echo " Scenario $SCENARIO_NAME"
echo "============================================================"
echo ""

load_secrets || exit 1

TS=$(date +%s)
export HARNESS_BASE_DOMAIN="${CF_ZONE_DOMAIN}"
export HARNESS_CF_API_TOKEN="${CF_API_TOKEN}"
export HARNESS_LAB_DOMAIN="testlab"
export STACK_DIR

save_stack_state "$SCENARIO_NAME"
register_teardown "" "${CF_ACCOUNT_ID:-}"

echo "[SCENARIO] Running interactive setup (both Cloudflare + Pi-Hole)..."

# Re-use CF interactive script but with local domain also set via env
# The CF expect script sends "\r" for local domain — override it for this
# scenario by patching env so the prompt pre-fills.
# We run a custom inline expect instead of reusing the single-purpose scripts.
EXPECT_SCRIPT=$(mktemp /tmp/harness-both-XXXXXX.exp)
cat > "$EXPECT_SCRIPT" << EXPEOF
#!/usr/bin/expect -f
set timeout 300
set stack_dir "$STACK_DIR"
set base_domain "$HARNESS_BASE_DOMAIN"
set cf_token    "$CF_API_TOKEN"
set lab_domain  "$HARNESS_LAB_DOMAIN"

spawn bash -c "cd \$stack_dir && ./setup.sh --interactive --skip-pull --force-reconfigure 2>&1"

expect { "Continue with setup?" { send "y\r" } timeout { exit 1 } }
expect { "Selection:" { send "1 3\r" } timeout { exit 1 } }
expect { "Choose mode" { send "replace\r" ; exp_continue } "Computer/host name" { } timeout { exit 1 } }
expect { "Computer/host name" { send "\r" } timeout { exit 1 } }
expect { "Host IP address" { send "\r" } timeout { exit 1 } }
expect { "Timezone" { send "\r" } timeout { exit 1 } }
expect { "External domain" { send "\$base_domain\r" } timeout { exit 1 } }
expect { "Local DNS suffix" { send "\$lab_domain\r" } timeout { exit 1 } }
expect { "Set custom admin credentials" { send "n\r" } timeout { exit 1 } }
expect { "Customize storage paths" { send "n\r" } timeout { exit 1 } }
expect { "Generate .env file" { send "y\r" } timeout { exit 1 } }
# Cloudflare wizard
expect { "Domain name" { send "\r" } timeout { exit 1 } }
expect { "Tunnel name" { send "weekendstack-harness-[clock seconds]\r" } timeout { exit 1 } }
expect { "existing API token" { send "n\r" ; exp_continue } "Cloudflare API token" { send "\$cf_token\r" } timeout { exit 1 } }
expect { "Select tunnel" { send "1\r" } "Created tunnel" { } "Using existing tunnel" { } timeout { exit 1 } }
expect { "Delete unused tunnels" { send "n\r" } "Setup Complete" { } "setup complete" { } timeout { exit 1 } }
expect { "Start WeekendStack services" { send "n\r" } timeout { exit 1 } }
expect eof
EXPEOF
chmod +x "$EXPECT_SCRIPT"

if ! expect "$EXPECT_SCRIPT"; then
    rm -f "$EXPECT_SCRIPT"
    echo "[SCENARIO ERROR] expect script failed"
    exit 1
fi
rm -f "$EXPECT_SCRIPT"

TEST_TUNNEL_ID=$(grep "^CLOUDFLARE_TUNNEL_ID=" "$STACK_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
TEST_ACCOUNT_ID=$(grep "^CLOUDFLARE_ACCOUNT_ID=" "$STACK_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
export _HARNESS_TEST_TUNNEL_ID="$TEST_TUNNEL_ID"
export _HARNESS_TEST_ACCOUNT_ID="$TEST_ACCOUNT_ID"

# Start the stack
echo "[SCENARIO] Starting stack..."
pushd "$STACK_DIR" >/dev/null
COMPOSE_PROFILES_VAL=$(grep "^COMPOSE_PROFILES=" .env 2>/dev/null | cut -d'=' -f2 | tr -d '"')
docker compose --profile "${COMPOSE_PROFILES_VAL//,/ --profile }" up -d 2>&1 | tail -5
sleep 15
popd >/dev/null

# Assertions
echo ""
echo "[SCENARIO] Running assertions..."

assert_env_var "$STACK_DIR/.env" "DOMAIN_MODE" "both"
assert_env_var "$STACK_DIR/.env" "BASE_DOMAIN" "$HARNESS_BASE_DOMAIN"
assert_env_var "$STACK_DIR/.env" "LAB_DOMAIN" "$HARNESS_LAB_DOMAIN"
assert_env_var_nonempty "$STACK_DIR/.env" "CLOUDFLARE_TUNNEL_TOKEN"

assert_container_running "traefik"
assert_container_running "cloudflare-tunnel"
assert_container_running "pihole"

if [[ -n "$TEST_TUNNEL_ID" && -n "$TEST_ACCOUNT_ID" ]]; then
    sleep 10
    assert_tunnel_active "$CF_API_TOKEN" "$TEST_ACCOUNT_ID" "$TEST_TUNNEL_ID"
fi

echo ""
if print_assertion_summary; then
    echo "[SCENARIO] $SCENARIO_NAME PASSED"
    exit 0
else
    echo "[SCENARIO] $SCENARIO_NAME FAILED"
    exit 1
fi
