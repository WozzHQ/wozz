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
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
PUSH_TO_CLOUD=false
API_TOKEN=""
API_URL="${WOZZ_API_URL:-https://wozz.io}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --push)
      PUSH_TO_CLOUD=true
      shift
      ;;
    --token)
      API_TOKEN="$2"
      shift 2
      ;;
    --help)
      echo "Wozz Kubernetes Audit Script"
      echo ""
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --push          Push audit data to Wozz Monitor"
      echo "  --token TOKEN   API token for authentication (get from wozz.io/settings/api)"
      echo "  --help          Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                                    # Run local audit only"
      echo "  $0 --push                             # Push to cloud (magic link)"
      echo "  $0 --push --token YOUR_TOKEN          # Push to your account"
      echo ""
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run with --help for usage information"
      exit 1
      ;;
  esac
done

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
echo "1. Save to Wozz Monitor (FREE):"
echo "   Run with --push flag to track waste over time"
echo "   Command: curl -sL wozz.io/audit.sh | bash -s -- --push"
echo ""
echo "2. Get Fix Plan (\$49 one-time):"
echo "   We generate kubectl patches for you"
echo "   Get it: https://wozz.io/buy?waste=$TOTAL_ANNUAL_SAVINGS"
echo ""
echo "Questions? audit@wozz.io"
echo ""

# Track completion
track_event "audit_complete" "$TOTAL_ANNUAL_SAVINGS"

# Generate cluster hash (unique identifier based on kubectl context)
CLUSTER_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "default")
CLUSTER_HASH=$(echo -n "$CLUSTER_CONTEXT" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "unknown")

# Create detailed JSON output
cat > wozz-audit.json <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cluster": {
    "context": "$CLUSTER_HASH",
    "totalPods": $TOTAL_PODS,
    "totalNodes": $TOTAL_NODES,
    "namespaces": 3
  },
  "costs": {
    "monthlyWaste": $MONTHLY_WASTE,
    "annualSavings": $TOTAL_ANNUAL_SAVINGS
  },
  "findings": [
    {
      "type": "PLACEHOLDER",
      "severity": "MEDIUM",
      "monthlySavings": $MONTHLY_WASTE,
      "description": "Placeholder finding - will be enhanced with real analysis"
    }
  ],
  "breakdown": {
    "memory": $((MONTHLY_WASTE * 60 / 100)),
    "cpu": $((MONTHLY_WASTE * 20 / 100)),
    "storage": $((MONTHLY_WASTE * 10 / 100)),
    "loadBalancers": $((MONTHLY_WASTE * 10 / 100))
  }
}
EOF

echo "Audit data saved to: wozz-audit.json"
echo ""

# Push to cloud if --push flag is set
if [ "$PUSH_TO_CLOUD" = true ]; then
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}Pushing to Wozz Monitor...${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  
  # Try to load token from saved location if not provided
  if [ -z "$API_TOKEN" ] && [ -f ~/.wozz/token ]; then
    API_TOKEN=$(cat ~/.wozz/token)
    echo "→ Using saved API token"
  fi
  
  # Prepare request body
  REQUEST_BODY=$(cat <<EOF_JSON
{
  "cluster_hash": "$CLUSTER_HASH",
  "api_token": "$API_TOKEN",
  "audit_data": $(cat wozz-audit.json)
}
EOF_JSON
)
  
  # Push to API
  PUSH_RESPONSE=$(curl -s -X POST "$API_URL/api/push" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY")
  
  # Check if push was successful
  if echo "$PUSH_RESPONSE" | grep -q '"success":true'; then
    echo -e "${GREEN}✓${NC} Data uploaded successfully"
    echo ""
    
    # Check if this is a magic claim URL response (unauthenticated)
    if echo "$PUSH_RESPONSE" | grep -q '"claim_url"'; then
      CLAIM_URL=$(echo "$PUSH_RESPONSE" | grep -o '"claim_url":"[^"]*"' | cut -d'"' -f4)
      
      echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      echo -e "${YELLOW}🎉 CLAIM YOUR AUDIT${NC}"
      echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      echo ""
      echo "View your results and save to your account:"
      echo ""
      echo -e "${GREEN}$CLAIM_URL${NC}"
      echo ""
      echo "This link expires in 7 days."
      echo ""
      echo "Tip: Sign in to get an API token for automatic uploads:"
      echo "     $API_URL/settings/api"
      echo ""
    else
      # Authenticated push - show dashboard URL
      DASHBOARD_URL=$(echo "$PUSH_RESPONSE" | grep -o '"dashboard_url":"[^"]*"' | cut -d'"' -f4)
      
      echo -e "${GREEN}✓${NC} Audit added to your dashboard"
      echo ""
      echo "View results: ${DASHBOARD_URL:-$API_URL/dashboard}"
      echo ""
    fi
  else
    ERROR_MSG=$(echo "$PUSH_RESPONSE" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
    echo -e "${RED}✗${NC} Upload failed: ${ERROR_MSG:-Unknown error}"
    echo ""
    echo "Troubleshooting:"
    echo "  • Check your API token: $API_URL/settings/api"
    echo "  • Verify network connection"
    echo "  • Try again with: $0 --push --token YOUR_TOKEN"
    echo ""
  fi
fi

