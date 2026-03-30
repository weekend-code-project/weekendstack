#!/bin/bash
# Unit tests for certificate helper path handling

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

CERT_HELPER="$PROJECT_ROOT/tools/setup/lib/certificate-helper.sh"

test_suite_start "Certificate Helper"

test_case "certificate helper uses repo-root SCRIPT_DIR paths"
if grep -q 'local stack_dir="${SCRIPT_DIR}"' "$CERT_HELPER" && \
   ! grep -q 'local stack_dir="${SCRIPT_DIR}/.."' "$CERT_HELPER"; then
    test_pass
else
    test_fail "Expected certificate helper to look for certs under the repo root, not the parent directory"
fi

test_case "certificate helper verifies traefik cert files in config/traefik/certs"
if grep -q 'config/traefik/certs/ca-cert.pem' "$CERT_HELPER" && \
   grep -q 'local required_files=("ca-cert.pem" "ca-key.pem" "cert.pem" "key.pem")' "$CERT_HELPER"; then
    test_pass
else
    test_fail "Expected certificate helper to verify the generated Traefik certificate bundle"
fi

test_suite_end
