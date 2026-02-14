#!/bin/bash
# Integration test for Docker Compose validation

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Docker Compose Integration"

# Test 1: docker-compose.yml is valid
test_case "docker-compose.yml syntax is valid"
cd "$PROJECT_ROOT"

if docker compose config >/dev/null 2>&1; then
    test_pass
else
    test_fail "docker-compose.yml has syntax errors"
fi

# Test 2: All profile compose files exist
test_case "All profile compose files exist"
cd "$PROJECT_ROOT"

profiles="core networking monitoring productivity dev ai media"
missing=0

for profile in $profiles; do
    compose_file="compose/docker-compose.${profile}.yml"
    if [ ! -f "$compose_file" ]; then
        echo "    Missing: $compose_file"
        missing=$((missing + 1))
    fi
done

if [ $missing -eq 0 ]; then
    test_pass
else
    test_fail "$missing compose files missing"
fi

# Test 3: Profile compose files are valid YAML
test_case "Profile compose files have valid YAML"
cd "$PROJECT_ROOT"

errors=0
for file in compose/docker-compose.*.yml; do
    if [ -f "$file" ]; then
        if ! docker compose -f "$file" config >/dev/null 2>&1; then
            echo "    Invalid YAML: $file"
            errors=$((errors + 1))
        fi
    fi
done

if [ $errors -eq 0 ]; then
    test_pass
else
    test_fail "$errors compose files have invalid YAML"
fi

# Test 4: Main docker-compose.yml includes all profiles
test_case "docker-compose.yml includes all profile files"
cd "$PROJECT_ROOT"

missing=0
for profile in core networking monitoring productivity dev ai media; do
    if ! grep -q "docker-compose.${profile}.yml" docker-compose.yml; then
        echo "    Not included: docker-compose.${profile}.yml"
        missing=$((missing + 1))
    fi
done

if [ $missing -eq 0 ]; then
    test_pass
else
    test_fail "$missing profile files not included in main compose"
fi

test_suite_end
