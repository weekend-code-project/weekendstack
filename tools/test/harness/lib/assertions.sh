#!/bin/bash
# harness/lib/assertions.sh
# Assertion helpers for the WeekendStack test harness.
# Each function prints PASS/FAIL and accumulates a counter.

: "${HARNESS_PASS_COUNT:=0}"
: "${HARNESS_FAIL_COUNT:=0}"
export HARNESS_PASS_COUNT HARNESS_FAIL_COUNT

_assert_pass() {
    local desc="$1"
    HARNESS_PASS_COUNT=$((HARNESS_PASS_COUNT + 1))
    echo "  [PASS] $desc"
}

_assert_fail() {
    local desc="$1"
    local detail="${2:-}"
    HARNESS_FAIL_COUNT=$((HARNESS_FAIL_COUNT + 1))
    echo "  [FAIL] $desc"
    [[ -n "$detail" ]] && echo "         $detail"
}

# ── Env file assertions ────────────────────────────────────────────────────────

# assert_env_var ENV_FILE VAR EXPECTED_VALUE
assert_env_var() {
    local env_file="$1" var="$2" expected="$3"
    local actual
    actual=$(grep "^${var}=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' "' || true)
    if [[ "$actual" == "$expected" ]]; then
        _assert_pass "$var = '$expected'"
    else
        _assert_fail "$var = '$expected'" "actual: '$actual'"
    fi
}

# assert_env_var_nonempty ENV_FILE VAR
assert_env_var_nonempty() {
    local env_file="$1" var="$2"
    local actual
    actual=$(grep "^${var}=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/#.*//' | tr -d ' "' || true)
    if [[ -n "$actual" ]]; then
        _assert_pass "$var is non-empty"
    else
        _assert_fail "$var is non-empty" "value was empty or missing"
    fi
}

# ── Container assertions ───────────────────────────────────────────────────────

# assert_container_running NAME
assert_container_running() {
    local name="$1"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name"; then
        _assert_pass "container '$name' is running"
    else
        _assert_fail "container '$name' is running" "not found in 'docker ps'"
    fi
}

# assert_container_stopped NAME
assert_container_stopped() {
    local name="$1"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name"; then
        _assert_fail "container '$name' is NOT running" "it is still listed in 'docker ps'"
    else
        _assert_pass "container '$name' is not running"
    fi
}

# ── File assertions ────────────────────────────────────────────────────────────

assert_file_exists() {
    local path="$1"
    if [[ -f "$path" ]]; then
        _assert_pass "file exists: $path"
    else
        _assert_fail "file exists: $path"
    fi
}

assert_file_absent() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        _assert_pass "file absent: $path"
    else
        _assert_fail "file absent: $path" "file still present"
    fi
}

assert_dir_absent() {
    local path="$1"
    if [[ ! -d "$path" ]]; then
        _assert_pass "directory absent: $path"
    else
        _assert_fail "directory absent: $path" "directory still present"
    fi
}

# ── HTTP assertions ────────────────────────────────────────────────────────────

# assert_url_responds URL EXPECTED_CODE [TIMEOUT_SECS]
assert_url_responds() {
    local url="$1" expected_code="$2" timeout="${3:-15}"
    local actual_code
    actual_code=$(curl -sk --max-time "$timeout" -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    if [[ "$actual_code" == "$expected_code" ]]; then
        _assert_pass "GET $url → HTTP $expected_code"
    else
        _assert_fail "GET $url → HTTP $expected_code" "got: $actual_code"
    fi
}

# assert_url_nonempty URL [TIMEOUT_SECS]
# Passes if the URL returns any 2xx response with non-empty body
assert_url_nonempty() {
    local url="$1" timeout="${2:-15}"
    local body
    body=$(curl -sk --max-time "$timeout" "$url" 2>/dev/null || true)
    if [[ -n "$body" ]]; then
        _assert_pass "GET $url returned non-empty body"
    else
        _assert_fail "GET $url returned non-empty body" "empty or no response"
    fi
}

# ── Cloudflare API assertions ──────────────────────────────────────────────────

# assert_tunnel_active CF_API_TOKEN ACCOUNT_ID TUNNEL_ID
assert_tunnel_active() {
    local token="$1" account_id="$2" tunnel_id="$3"
    local status
    status=$(curl -sf --max-time 10 \
        "https://api.cloudflare.com/client/v4/accounts/$account_id/cfd_tunnel/$tunnel_id" \
        -H "Authorization: Bearer $token" 2>/dev/null \
        | jq -r '.result.status // empty' 2>/dev/null)
    if [[ "$status" == "healthy" || "$status" == "degraded" ]]; then
        _assert_pass "Cloudflare tunnel $tunnel_id is $status"
    else
        _assert_fail "Cloudflare tunnel $tunnel_id is active" "API status: '${status:-no response}'"
    fi
}

# assert_tunnel_deleted CF_API_TOKEN ACCOUNT_ID TUNNEL_ID
assert_tunnel_deleted() {
    local token="$1" account_id="$2" tunnel_id="$3"
    local deleted_at
    deleted_at=$(curl -sf --max-time 10 \
        "https://api.cloudflare.com/client/v4/accounts/$account_id/cfd_tunnel/$tunnel_id" \
        -H "Authorization: Bearer $token" 2>/dev/null \
        | jq -r '.result.deleted_at // empty' 2>/dev/null)
    if [[ -n "$deleted_at" ]]; then
        _assert_pass "Cloudflare tunnel $tunnel_id is deleted (deleted_at: $deleted_at)"
    else
        _assert_fail "Cloudflare tunnel $tunnel_id is deleted" "tunnel still exists or API unreachable"
    fi
}

# ── Summary ────────────────────────────────────────────────────────────────────

print_assertion_summary() {
    local total=$((HARNESS_PASS_COUNT + HARNESS_FAIL_COUNT))
    echo ""
    echo "  Assertions: $HARNESS_PASS_COUNT/$total passed"
    if [[ $HARNESS_FAIL_COUNT -gt 0 ]]; then
        echo "  FAILED: $HARNESS_FAIL_COUNT assertion(s)"
        return 1
    fi
    return 0
}

reset_assertion_counts() {
    HARNESS_PASS_COUNT=0
    HARNESS_FAIL_COUNT=0
}
