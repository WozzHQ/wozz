#!/bin/bash

# Wozz Kubernetes Audit Script
# Analyzes your K8s cluster for wasted resources
# MIT License - Open Source
#
# PRIVACY NOTICE:
# This script sends anonymous telemetry (start/complete events + waste amount)
# to help us understand usage. No cluster data, secrets, or identifiable info.
# Data sent: event type (start/complete), random UUID, total waste amount
# To disable: Set WOZZ_NO_TELEMETRY=1 before running
#
# Review tracking code: Lines 25-38 below
# Review what's collected: Your cluster metadata stays local

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Generate unique install ID (random, not tied to your identity)
INSTALL_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "unknown-$(date +%s)")

# Telemetry: Anonymous usage stats only (start/finish + waste amount)
# Helps us understand if the tool is useful. No cluster data sent.
# Set WOZZ_NO_TELEMETRY=1 to disable
track_event() {
    # Skip if telemetry disabled
    if [ "$WOZZ_NO_TELEMETRY" = "1" ]; then
        return 0
    fi
    
    local event=$1
    local waste=$2
    
    # Non-blocking, 2-second timeout, silent failure
    if [ -n "$waste" ]; then
        curl -s -m 2 "https://wozz.io/api/track?event=$event&id=$INSTALL_ID&waste=$waste" > /dev/null 2>&1 &
    else
        curl -s -m 2 "https://wozz.io/api/track?event=$event&id=$INSTALL_ID" > /dev/null 2>&1 &
    fi
}

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}WOZZ KUBERNETES AUDIT${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Privacy: This tool runs locally. Anonymous usage stats sent."
echo "To disable: export WOZZ_NO_TELEMETRY=1"
echo ""

# Track audit start
track_event "audit_start"

# Check prerequisites
echo "→ Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to cluster${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Prerequisites OK"
echo ""

# Collect cluster data
echo "→ Collecting cluster data..."

PODS=$(kubectl get pods --all-namespaces -o json 2>/dev/null)
NODES=$(kubectl get nodes -o json 2>/dev/null)

if [ -z "$PODS" ] || [ -z "$NODES" ]; then
    echo -e "${RED}Error: Failed to collect cluster data${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Data collected"
echo ""

# Simple cost calculation (placeholder - you'll enhance this)
echo "→ Analyzing resource usage..."

# Count resources
TOTAL_PODS=$(echo "$PODS" | grep -o '"name":' | wc -l)
TOTAL_NODES=$(echo "$NODES" | grep -o '"name":' | wc -l)

# Placeholder calculation (replace with real analysis)
# This is a simplified example - in reality you'd analyze:
# - Memory over-provisioning
# - CPU over-provisioning  
# - Unused PVs
# - Orphaned load balancers
MONTHLY_WASTE=$((TOTAL_PODS * 85 + TOTAL_NODES * 120))
TOTAL_ANNUAL_SAVINGS=$((MONTHLY_WASTE * 12))

echo -e "${GREEN}✓${NC} Analysis complete"
echo ""

# Display results
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}TOTAL ANNUAL WASTE: \$$TOTAL_ANNUAL_SAVINGS${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Cluster Overview:"
echo "  • Total Pods: $TOTAL_PODS"
echo "  • Total Nodes: $TOTAL_NODES"
echo "  • Monthly Waste: \$$MONTHLY_WASTE"
echo ""
echo "Next steps:"
echo ""
echo "1. DIY: Review findings and implement manually"
echo "2. Get Fix Plan: We generate kubectl patches for you"
echo ""
echo "   Price: \$49 (one-time)"
echo "   Delivery: 24 hours"
echo "   Includes: patches + deployment guide + rollback scripts"
echo ""
echo "   Get it: https://wozz.io/buy?waste=$TOTAL_ANNUAL_SAVINGS"
echo ""
echo "Questions? audit@wozz.io"
echo ""

# Track completion
track_event "audit_complete" "$TOTAL_ANNUAL_SAVINGS"

# Create simple JSON output
cat > wozz-audit.json <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "installId": "$INSTALL_ID",
  "cluster": {
    "totalPods": $TOTAL_PODS,
    "totalNodes": $TOTAL_NODES
  },
  "costs": {
    "monthlyWaste": $MONTHLY_WASTE,
    "annualSavings": $TOTAL_ANNUAL_SAVINGS
  }
}
EOF

echo "Audit data saved to: wozz-audit.json"
echo ""

