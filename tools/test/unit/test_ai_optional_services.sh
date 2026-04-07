#!/bin/bash
# Unit tests for optional AI service profile mappings

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "AI Optional Services"

test_case "SearXNG has its own compose profile"
searxng_profile=$(awk '
    /^  searxng:$/ { in_service=1; next }
    in_service && /^  [a-z0-9-]+:$/ { exit }
    in_service && /profiles:/ { getline; gsub(/^[[:space:]]*-[[:space:]]*/, "", $0); print; exit }
' "$PROJECT_ROOT/compose/docker-compose.ai.yml")

if [[ "$searxng_profile" == "searxng" ]]; then
    test_pass
else
    test_fail "Expected searxng profile, got '$searxng_profile'"
fi

test_case "CPU Ollama has a dedicated runtime profile"
ollama_cpu_profile=$(awk '
    /^  ollama-cpu:$/ { in_service=1; next }
    in_service && /^  [a-z0-9-]+:$/ { exit }
    in_service && /profiles:/ { getline; gsub(/^[[:space:]]*-[[:space:]]*/, "", $0); print; exit }
' "$PROJECT_ROOT/compose/docker-compose.ai.yml")

if [[ "$ollama_cpu_profile" == "ollama-cpu" ]]; then
    test_pass
else
    test_fail "Expected ollama-cpu profile, got '$ollama_cpu_profile'"
fi

test_case "AI profile mapping no longer auto-includes SearXNG"
if jq -e '.ai | index("searxng") | not' "$PROJECT_ROOT/tools/env/mappings/profile-to-services.json" >/dev/null 2>&1 && \
   jq -e '.searxng == ["searxng"]' "$PROJECT_ROOT/tools/env/mappings/profile-to-services.json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "Profile mappings still treat SearXNG as part of base ai"
fi

test_case "AI frontends default to the in-stack Ollama endpoint"
if grep -q 'OLLAMA_BASE_URL=${OLLAMA_HOST:-http://ollama:11434}' "$PROJECT_ROOT/compose/docker-compose.ai.yml" && \
   grep -q 'PGPT_OLLAMA_API_BASE=${OLLAMA_HOST:-http://ollama:11434}' "$PROJECT_ROOT/compose/docker-compose.ai.yml" && \
   ! grep -q 'host-gateway' "$PROJECT_ROOT/compose/docker-compose.ai.yml"; then
    test_pass
else
    test_fail "Expected AI services to use the internal ollama endpoint without host-gateway"
fi

test_case "SearXNG metadata uses the searxng profile"
if jq -e '.searxng.profile == "searxng"' "$PROJECT_ROOT/tools/env/mappings/service-metadata.json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "service-metadata.json does not map searxng to the searxng profile"
fi

test_case "Assembled env includes SearXNG variables only when requested"
create_temp_env

if "$PROJECT_ROOT/tools/env/scripts/assemble-env.sh" --profiles "ai,searxng" --output "$TEST_ENV" >/dev/null 2>&1 && \
   grep -q '^SEARXNG_' "$TEST_ENV"; then
    test_pass
else
    test_fail "Expected assembled env to include SearXNG variables"
fi

test_case "Paperclip has its own compose profile"
paperclip_profile=$(awk '
    /^  paperclip:$/ { in_service=1; next }
    in_service && /^  [a-z0-9-]+:$/ { exit }
    in_service && /profiles:/ { getline; gsub(/^[[:space:]]*-[[:space:]]*/, "", $0); print; exit }
' "$PROJECT_ROOT/compose/docker-compose.ai.yml")

if [[ "$paperclip_profile" == "paperclip" ]]; then
    test_pass
else
    test_fail "Expected paperclip profile, got '$paperclip_profile'"
fi

test_case "Paperclip metadata uses the paperclip profile"
if jq -e '.paperclip.profile == "paperclip"' "$PROJECT_ROOT/tools/env/mappings/service-metadata.json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "service-metadata.json does not map paperclip to the paperclip profile"
fi

test_case "Paperclip profile mapping stays optional"
if jq -e '.paperclip == ["paperclip"]' "$PROJECT_ROOT/tools/env/mappings/profile-to-services.json" >/dev/null 2>&1 && \
   jq -e '.ai | index("paperclip") | not' "$PROJECT_ROOT/tools/env/mappings/profile-to-services.json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "Profile mappings still treat Paperclip as part of base ai"
fi

test_case "Assembled env includes Paperclip variables only when requested"
create_temp_env

if "$PROJECT_ROOT/tools/env/scripts/assemble-env.sh" --profiles "ai,paperclip" --output "$TEST_ENV" >/dev/null 2>&1 && \
   grep -q '^PAPERCLIP_' "$TEST_ENV" && \
   grep -q '^BETTER_AUTH_SECRET=' "$TEST_ENV"; then
    test_pass
else
    test_fail "Expected assembled env to include Paperclip variables"
fi

test_suite_end
