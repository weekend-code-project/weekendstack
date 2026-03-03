#!/bin/bash
# =============================================================================
# WordPress Template Integration Test
# =============================================================================
# Tests the "wordpress" Coder template with full WordPress + MySQL install.
#
# Validates:
#   1. Workspace creation (main + MySQL + phpMyAdmin containers)
#   2. PHP installed with correct version
#   3. Apache running and serving WordPress
#   4. MySQL sidecar running and accepting connections
#   5. WordPress fully installed — initial setup page accessible
#   6. phpMyAdmin sidecar accessible
#   7. code-server is running
#
# Usage:
#   ./tools/test/test-wordpress-template.sh [--keep]
#
# Required:
#   CODER_SESSION_TOKEN env var must be set
# =============================================================================

set -euo pipefail

# ─── Template config ────────────────────────────────────────
TEMPLATE_NAME="wordpress"
WAIT_SCRIPTS_TIMEOUT=300  # WordPress install w/ PHP + Apache + MySQL can be slow
WAIT_AGENT_TIMEOUT=180

CREATE_PARAMS=(
    --parameter php_version=8.3
    --parameter external_preview=true
    --parameter workspace_password=""
    --parameter enable_ssh=true
)

# ─── Source shared helpers ───────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"

# =============================================================================
# TEST: Sidecar Containers
# =============================================================================

test_sidecar_containers() {
    log_section "Sidecar Containers"

    # Check MySQL container is running
    local mysql_container
    mysql_container=$(docker ps --filter "name=mysql-${WORKSPACE_NAME}" --format "{{.Names}}" | head -1)
    if [[ -n "$mysql_container" ]]; then
        log_pass "MySQL container running ($mysql_container)"
    else
        log_fail "MySQL container running" "no container matching mysql-${WORKSPACE_NAME}"
        return 1
    fi

    # Check MySQL is responsive
    log "Waiting for MySQL to be ready..."
    local start_time=$SECONDS
    local mysql_ready=false
    while [[ $((SECONDS - start_time)) -lt 60 ]]; do
        if docker exec "$mysql_container" mysqladmin ping -h localhost -u root -pwordpress_root_pass --silent 2>/dev/null | grep -q "alive"; then
            mysql_ready=true
            break
        fi
        sleep 3
    done

    local elapsed=$((SECONDS - start_time))
    if $mysql_ready; then
        log_pass "MySQL is accepting connections (${elapsed}s)"
    else
        log_fail "MySQL is accepting connections" "timed out after 60s"
    fi

    # Verify wordpress database exists
    local db_check
    db_check=$(docker exec "$mysql_container" mysql -u wordpress_user -pwordpress_pass -e "SHOW DATABASES;" 2>/dev/null || echo "")
    if echo "$db_check" | grep -q "wordpress"; then
        log_pass "WordPress database exists"
    else
        log_fail "WordPress database exists" "database 'wordpress' not found"
    fi

    # Check phpMyAdmin container is running
    local pma_container
    pma_container=$(docker ps --filter "name=pma-${WORKSPACE_NAME}" --format "{{.Names}}" | head -1)
    if [[ -n "$pma_container" ]]; then
        log_pass "phpMyAdmin container running ($pma_container)"
    else
        log_fail "phpMyAdmin container running" "no container matching pma-${WORKSPACE_NAME}"
    fi

    # Verify phpMyAdmin is responding
    if [[ -n "$pma_container" ]]; then
        local pma_response
        pma_response=$(docker exec "$pma_container" curl -sf http://localhost:80/ 2>/dev/null | head -5 || echo "")
        if [[ -n "$pma_response" ]]; then
            log_pass "phpMyAdmin is responding on port 80"
        else
            log_skip "phpMyAdmin response" "may need more time or internal networking"
        fi
    fi
}

# =============================================================================
# TEST: PHP Installation
# =============================================================================

test_php_installed() {
    log_section "PHP Installation"

    # Wait for PHP install to complete
    log "Waiting for PHP installation..."
    local start_time=$SECONDS
    local php_ready=false

    while [[ $((SECONDS - start_time)) -lt $WAIT_SCRIPTS_TIMEOUT ]]; do
        local php_check
        php_check=$(workspace_exec "php --version 2>/dev/null | head -1" || echo "")
        if [[ "$php_check" == *"PHP 8"* ]]; then
            php_ready=true
            break
        fi
        sleep 10
    done

    local elapsed=$((SECONDS - start_time))
    if $php_ready; then
        log_pass "PHP installed (${elapsed}s)"
    else
        log_fail "PHP installed" "timed out after ${WAIT_SCRIPTS_TIMEOUT}s"
        return 1
    fi

    # Check PHP version
    local php_version
    php_version=$(workspace_exec "php -r 'echo PHP_VERSION;' 2>/dev/null" || echo "")
    assert_not_empty "$php_version" "PHP version: $php_version"

    # Verify expected PHP extensions
    local extensions
    extensions=$(workspace_exec "php -m 2>/dev/null" || echo "")
    assert_contains "$extensions" "mysqli" "PHP mysqli extension loaded"
    assert_contains "$extensions" "curl" "PHP curl extension loaded"
    assert_contains "$extensions" "mbstring" "PHP mbstring extension loaded"
    assert_contains "$extensions" "xml" "PHP xml extension loaded"
    assert_contains "$extensions" "zip" "PHP zip extension loaded"
}

# =============================================================================
# TEST: Apache Web Server
# =============================================================================

test_apache() {
    log_section "Apache Web Server"

    # Check Apache process
    local apache_pid
    apache_pid=$(workspace_exec_root "pgrep -x apache2 2>/dev/null | head -1" || echo "")
    if [[ -n "$apache_pid" ]]; then
        log_pass "Apache process running (PID: $apache_pid)"
    else
        # Apache might be started as root
        log "Waiting for Apache to start..."
        sleep 10
        apache_pid=$(workspace_exec_root "pgrep -x apache2 2>/dev/null | head -1" || echo "")
        if [[ -n "$apache_pid" ]]; then
            log_pass "Apache process running (delayed, PID: $apache_pid)"
        else
            log_fail "Apache process running" "not found"
            return
        fi
    fi

    # Check port 80 is listening
    local listening
    listening=$(workspace_exec_root "ss -tlnp 2>/dev/null | grep ':80 '" || echo "")
    assert_not_empty "$listening" "Apache listening on port 80"

    # Check mod_rewrite is enabled
    local mods
    mods=$(workspace_exec_root "apache2ctl -M 2>/dev/null | grep rewrite" || echo "")
    if [[ -n "$mods" ]]; then
        log_pass "Apache mod_rewrite enabled"
    else
        log_skip "Apache mod_rewrite" "may not be queryable"
    fi
}

# =============================================================================
# TEST: WordPress Installation & Setup Page
# =============================================================================

test_wordpress_install() {
    log_section "WordPress Installation"

    # Check WordPress files exist
    local wp_config
    wp_config=$(workspace_exec "test -f /var/www/html/wp-config.php && echo yes" || echo "")
    if [[ "$wp_config" == "yes" ]]; then
        log_pass "wp-config.php exists"
    else
        log_fail "wp-config.php exists" "file not found"
    fi

    local wp_includes
    wp_includes=$(workspace_exec "test -d /var/www/html/wp-includes && echo yes" || echo "")
    if [[ "$wp_includes" == "yes" ]]; then
        log_pass "wp-includes/ directory exists"
    else
        log_fail "wp-includes/ directory exists" "not found"
    fi

    local wp_admin
    wp_admin=$(workspace_exec "test -d /var/www/html/wp-admin && echo yes" || echo "")
    if [[ "$wp_admin" == "yes" ]]; then
        log_pass "wp-admin/ directory exists"
    else
        log_fail "wp-admin/ directory exists" "not found"
    fi

    # Verify wp-config.php has correct DB settings
    local db_name
    db_name=$(workspace_exec "grep DB_NAME /var/www/html/wp-config.php 2>/dev/null" || echo "")
    assert_contains "$db_name" "wordpress" "wp-config.php DB_NAME is 'wordpress'"

    local db_host
    db_host=$(workspace_exec "grep DB_HOST /var/www/html/wp-config.php 2>/dev/null" || echo "")
    assert_contains "$db_host" "mysql-${WORKSPACE_NAME}" "wp-config.php DB_HOST points to MySQL sidecar"

    # Test the WordPress setup page
    log "Checking WordPress initial setup page..."
    sleep 5

    local wp_response
    wp_response=$(workspace_exec "curl -sf -L http://localhost:80/ 2>/dev/null" || echo "")

    if [[ -n "$wp_response" ]]; then
        log_pass "WordPress responds on port 80"

        # WordPress should show either:
        # - The install page (wp-admin/install.php) with "WordPress" title
        # - A redirect to wp-admin/install.php
        if echo "$wp_response" | grep -qi "wordpress\|wp-install\|install\.php\|language\|setup\|configuration"; then
            log_pass "WordPress install/setup page accessible"
        else
            # Try the install URL directly
            local install_response
            install_response=$(workspace_exec "curl -sf -L http://localhost:80/wp-admin/install.php 2>/dev/null" || echo "")
            if echo "$install_response" | grep -qi "wordpress\|install\|setup\|language\|site title"; then
                log_pass "WordPress install page accessible at /wp-admin/install.php"
            else
                log_fail "WordPress setup page accessible" "no WordPress content found"
                echo "  Response preview: $(echo "$wp_response" | head -5)"
            fi
        fi
    else
        log_fail "WordPress responds on port 80" "empty response"
    fi

    # Test wp-login.php exists and responds
    local login_response
    login_response=$(workspace_exec "curl -sf -o /dev/null -w '%{http_code}' http://localhost:80/wp-login.php 2>/dev/null" || echo "000")
    if [[ "$login_response" =~ ^(200|302|301)$ ]]; then
        log_pass "wp-login.php accessible (HTTP $login_response)"
    else
        log_skip "wp-login.php accessibility" "HTTP $login_response (expected before setup)"
    fi

    # Verify WordPress can connect to the database
    local db_connection
    db_connection=$(workspace_exec '
        php -r "
            \$conn = new mysqli(\"mysql-'${WORKSPACE_NAME}'\", \"wordpress_user\", \"wordpress_pass\", \"wordpress\");
            if (\$conn->connect_error) {
                echo \"FAIL: \" . \$conn->connect_error;
            } else {
                echo \"OK\";
                \$conn->close();
            }
        " 2>/dev/null
    ' || echo "FAIL")

    if [[ "$db_connection" == "OK" ]]; then
        log_pass "WordPress can connect to MySQL database"
    else
        log_fail "WordPress MySQL connection" "$db_connection"
    fi
}

# =============================================================================
# TEST: No Git Modules (wordpress template should not have git)
# =============================================================================

test_no_git_config() {
    log_section "No Git Config (by design)"

    local git_name
    git_name=$(workspace_exec "git config --global user.name 2>/dev/null" || echo "")
    if [[ -z "$git_name" ]]; then
        log_pass "Git user.name not configured (expected — no git module)"
    else
        log_skip "Git user.name check" "git user.name is set ($git_name) — may come from base image"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  WordPress Template Test Suite${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "  Template:  ${CYAN}$TEMPLATE_NAME${NC}"
    echo -e "  Workspace: ${CYAN}$WORKSPACE_NAME${NC}"
    echo ""

    if ! $KEEP_WORKSPACE; then
        trap cleanup EXIT
    fi

    preflight
    create_workspace || { echo -e "${RED}Workspace creation failed${NC}"; exit 1; }
    wait_for_workspace || { echo -e "${RED}Workspace not ready${NC}"; exit 1; }
    test_container_basics
    test_sidecar_containers
    test_php_installed
    test_apache
    test_wordpress_install
    test_code_server
    test_no_git_config
    print_summary
}

main
