#!/bin/bash
# Quick script to set debug-template phase by enabling/disabling modules

PHASE=${1:-}
MODULES_FILE="/opt/stacks/weekendstack/config/coder/templates/debug-template/modules.txt"

if [[ -z "$PHASE" ]]; then
    echo "Usage: $0 <phase-number>"
    echo "  0 - Baseline (code-server only)"
    echo "  1 - Phase 1 (+ metadata, docker)"
    echo "  2 - Phase 2 (+ ssh) HIGH RISK"
    echo "  3 - Phase 3 (+ setup-server) HIGH RISK"
    exit 1
fi

# Reset all to commented
sed -i 's/^metadata:params/#metadata:params/' "$MODULES_FILE"
sed -i 's/^docker:params/#docker:params/' "$MODULES_FILE"
sed -i 's/^ssh:params/#ssh:params/' "$MODULES_FILE"
sed -i 's/^setup-server:params/#setup-server:params/' "$MODULES_FILE"

# Enable based on phase
case $PHASE in
    0)
        echo "Phase 0: Baseline (code-server only)"
        ;;
    1)
        echo "Phase 1: Adding metadata, docker"
        sed -i 's/^#metadata:params/metadata:params/' "$MODULES_FILE"
        sed -i 's/^#docker:params/docker:params/' "$MODULES_FILE"
        ;;
    2)
        echo "Phase 2: Adding metadata, docker, ssh (HIGH RISK)"
        sed -i 's/^#metadata:params/metadata:params/' "$MODULES_FILE"
        sed -i 's/^#docker:params/docker:params/' "$MODULES_FILE"
        sed -i 's/^#ssh:params/ssh:params/' "$MODULES_FILE"
        ;;
    3)
        echo "Phase 3: Adding metadata, docker, ssh, setup-server (HIGH RISK)"
        sed -i 's/^#metadata:params/metadata:params/' "$MODULES_FILE"
        sed -i 's/^#docker:params/docker:params/' "$MODULES_FILE"
        sed -i 's/^#ssh:params/ssh:params/' "$MODULES_FILE"
        sed -i 's/^#setup-server:params/setup-server:params/' "$MODULES_FILE"
        ;;
    *)
        echo "Unknown phase: $PHASE"
        exit 1
        ;;
esac

echo "✓ modules.txt updated for Phase $PHASE"
echo "Run: ./config/coder/scripts/test-debug-phases.sh $PHASE"
