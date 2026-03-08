#!/bin/bash
# harness/run-harness.sh
# Orchestrates WeekendStack test scenarios.
#
# Usage:
#   ./run-harness.sh              # run all scenarios
#   ./run-harness.sh --scenario 01
#   ./run-harness.sh --scenario 01,03,05
#   ./run-harness.sh --dry-run    # list scenarios without running
#   ./run-harness.sh --list       # same as --dry-run
#
# Exit code: number of failed scenarios (0 = all passed)

set -uo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIOS_DIR="$HARNESS_DIR/scenarios"
export WEEKENDSTACK_DIR="${WEEKENDSTACK_DIR:-/home/ubuntu/weekendstack}"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Parse arguments ───────────────────────────────────────────────────────────
DRY_RUN=false
SELECTED=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --scenario|-s)
            SELECTED="$2"; shift 2 ;;
        --dry-run|--list|-l)
            DRY_RUN=true; shift ;;
        --help|-h)
            sed -n '2,12p' "$0" | sed 's/^# *//'
            exit 0 ;;
        *)
            echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# ── Discover available scenarios ──────────────────────────────────────────────
mapfile -t ALL_SCENARIOS < <(
    ls "$SCENARIOS_DIR"/[0-9][0-9]-*.sh 2>/dev/null | sort
)

if [[ ${#ALL_SCENARIOS[@]} -eq 0 ]]; then
    echo "No scenarios found in $SCENARIOS_DIR"
    exit 1
fi

# ── Filter to requested scenarios ────────────────────────────────────────────
if [[ -n "$SELECTED" ]]; then
    IFS=',' read -ra NUMS <<< "$SELECTED"
    SCENARIOS=()
    for num in "${NUMS[@]}"; do
        num=$(printf "%02d" "$num")
        match=$(ls "$SCENARIOS_DIR/${num}-"*.sh 2>/dev/null | head -1)
        if [[ -n "$match" ]]; then
            SCENARIOS+=("$match")
        else
            echo -e "${YELLOW}[WARN] No scenario matching number $num${NC}"
        fi
    done
else
    SCENARIOS=("${ALL_SCENARIOS[@]}")
fi

# ── Dry-run: list only ────────────────────────────────────────────────────────
if $DRY_RUN; then
    echo -e "${BOLD}Available scenarios:${NC}"
    for s in "${SCENARIOS[@]}"; do
        name=$(basename "$s" .sh)
        desc=$(grep "^# Scenario:" "$s" 2>/dev/null | head -1 | sed 's/# Scenario: //' || echo "")
        echo -e "  ${CYAN}$name${NC}  $desc"
    done
    exit 0
fi

# ── Check dependencies ────────────────────────────────────────────────────────
missing_deps=()
for dep in docker expect jq curl; do
    command -v "$dep" >/dev/null 2>&1 || missing_deps+=("$dep")
done
if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo -e "${RED}[HARNESS] Missing dependencies: ${missing_deps[*]}${NC}"
    echo "Install with: sudo apt-get install -y ${missing_deps[*]}"
    exit 1
fi

# ── Run scenarios ─────────────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
declare -A RESULTS

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║          WeekendStack Test Harness                       ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Stack dir:  $WEEKENDSTACK_DIR"
echo -e "  Scenarios:  ${#SCENARIOS[@]}"
echo -e "  Started:    $(date)"
echo ""

for scenario_file in "${SCENARIOS[@]}"; do
    scenario_name=$(basename "$scenario_file" .sh)
    echo -e "${BOLD}──────────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}  Running: ${CYAN}$scenario_name${NC}"
    echo -e "${BOLD}──────────────────────────────────────────────────────────${NC}"

    start_time=$(date +%s)

    # Run in a subshell so trap/exit in the scenario doesn't kill the harness
    set +e
    bash "$scenario_file" 2>&1
    exit_code=$?
    set -e

    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    if [[ $exit_code -eq 0 ]]; then
        RESULTS[$scenario_name]="PASS"
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "${GREEN}  PASSED${NC} (${elapsed}s)"
    else
        RESULTS[$scenario_name]="FAIL"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo -e "${RED}  FAILED${NC} (exit $exit_code, ${elapsed}s)"
    fi
    echo ""
done

# ── Summary table ─────────────────────────────────────────────────────────────
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Test Harness Summary                                    ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
for scenario_name in "${!RESULTS[@]}"; do
    result="${RESULTS[$scenario_name]}"
    if [[ "$result" == "PASS" ]]; then
        icon="${GREEN}✓${NC}"
    else
        icon="${RED}✗${NC}"
    fi
    printf "║  %-48s %s  ║\n" "$scenario_name" "$(echo -e "$icon")"
done | sort
echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}║  Passed: ${GREEN}${PASS_COUNT}/${TOTAL}${NC}${BOLD}   Failed: ${RED}${FAIL_COUNT}${NC}${BOLD}   Finished: $(date +%H:%M:%S)  ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

exit $FAIL_COUNT
