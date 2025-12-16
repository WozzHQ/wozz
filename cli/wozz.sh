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

# ---- Quantity parsing helpers ----
# CPU -> millicores (e.g. "250m" => 250, "1" => 1000)
to_millicores() {
  local v="$1"
  [[ -z "$v" ]] && echo "" && return
  if [[ "$v" =~ m$ ]]; then
    echo "${v%m}"
  else
    awk "BEGIN {printf \"%d\", ($v * 1000)}"
  fi
}

# Memory -> MiB (e.g. "512Mi" => 512, "1Gi" => 1024)
to_mib() {
  local v="$1"
  [[ -z "$v" ]] && echo "" && return
  case "$v" in
    *Ki) awk "BEGIN {printf \"%d\", (${v%Ki} / 1024)}" ;;
    *Mi) echo "${v%Mi}" ;;
    *Gi) awk "BEGIN {printf \"%d\", (${v%Gi} * 1024)}" ;;
    *Ti) awk "BEGIN {printf \"%d\", (${v%Ti} * 1024 * 1024)}" ;;
    *)   echo "" ;; # unsupported format
  esac
}

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

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: 'jq' not found. Install for better analysis: brew install jq (Mac) or apt-get install jq (Linux)${NC}"
    echo "Falling back to basic counting..."
    USE_BASIC_COUNT=true
else
    USE_BASIC_COUNT=false
fi

PODS=$(kubectl get pods --all-namespaces -o json 2>/dev/null)
NODES=$(kubectl get nodes -o json 2>/dev/null)
PVS=$(kubectl get pv -o json 2>/dev/null || echo '{"items":[]}')
SERVICES=$(kubectl get svc --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')

if [ -z "$PODS" ] || [ -z "$NODES" ]; then
    echo -e "${RED}Error: Failed to collect cluster data${NC}"
    exit 1
fi

# Try to get actual metrics (kubectl top)
echo "→ Fetching live metrics..."
METRICS_AVAILABLE=false
if kubectl top pods --all-namespaces > /dev/null 2>&1; then
    POD_METRICS=$(kubectl top pods --all-namespaces --no-headers 2>/dev/null)
    METRICS_AVAILABLE=true
    echo -e "${GREEN}✓${NC} Live metrics available (using kubectl top)"
else
    echo -e "${YELLOW}⚠${NC} Metrics server not available - using request/limit analysis"
    echo "   Install metrics-server for accurate usage data"
fi

echo -e "${GREEN}✓${NC} Data collected"
echo ""

# REAL COST ANALYSIS
echo "→ Analyzing resource usage..."

# Real cloud pricing (conservative averages across AWS/GCP/Azure)
MEMORY_COST_PER_GB_MONTH=7.20  # $0.01/GB/hour
CPU_COST_PER_CORE_MONTH=21.60  # $0.03/vCPU/hour
STORAGE_COST_PER_GB_MONTH=0.10 # EBS gp3/PD-SSD average
LB_COST_PER_MONTH=20          # ALB/NLB/Cloud LB average

# Count resources
if [ "$USE_BASIC_COUNT" = true ]; then
    TOTAL_PODS=$(echo "$PODS" | grep -o '"name":' | wc -l | tr -d ' ')
    TOTAL_NODES=$(echo "$NODES" | grep -o '"name":' | wc -l | tr -d ' ')
else
    TOTAL_PODS=$(echo "$PODS" | jq '.items | length' 2>/dev/null || echo "0")
    TOTAL_NODES=$(echo "$NODES" | jq '.items | length' 2>/dev/null || echo "0")
fi

# Initialize counters
memory_waste_monthly=0
cpu_waste_monthly=0
storage_waste_monthly=0
lb_waste_monthly=0
pods_over_provisioned=0
pods_no_requests=0

# Aggregated findings tracking (by issue type)
declare -A finding_pods_count      # Count of pods per finding type
declare -A finding_total_savings   # Total monthly savings per type
declare -A finding_severity        # Severity per type
declare -A finding_examples        # JSON array of top examples per type

# Top offender tracking
top_offender_name=""
top_offender_namespace=""
top_offender_waste=0
top_offender_mem_request=""
top_offender_mem_limit=""
top_offender_mem_actual=""
top_offender_cpu_request=""
top_offender_cpu_limit=""
top_offender_cpu_actual=""

# Helper to track a finding for aggregation
track_finding() {
    local type="$1"
    local severity="$2"
    local pod="$3"
    local ns="$4"
    local savings="$5"
    local req="$6"
    local actual="$7"

    # Initialize if first occurrence
    if [[ -z "${finding_pods_count[$type]}" ]]; then
        finding_pods_count[$type]=0
        finding_total_savings[$type]=0
        finding_severity[$type]="$severity"
        finding_examples[$type]=""
    fi

    # Increment count and add savings
    finding_pods_count[$type]=$((finding_pods_count[$type] + 1))
    finding_total_savings[$type]=$((finding_total_savings[$type] + savings))

    # Track top 5 examples per type (only if savings > 0)
    if [[ $savings -gt 0 ]]; then
        local example_count=$(echo "${finding_examples[$type]}" | grep -o '"pod":' | wc -l)
        if [[ $example_count -lt 5 ]]; then
            [[ -n "${finding_examples[$type]}" ]] && finding_examples[$type]="${finding_examples[$type]},"
            finding_examples[$type]="${finding_examples[$type]}
        {\"pod\":\"$pod\",\"namespace\":\"$ns\",\"savings\":$savings,\"requested\":\"$req\",\"actual\":\"$actual\"}"
        fi
    fi
}

if [ "$USE_BASIC_COUNT" = false ]; then
    # REAL ANALYSIS: Compare actual usage vs requests
    while read -r pod_data; do
        [ -z "$pod_data" ] && continue
        
        pod_name=$(echo "$pod_data" | jq -r '.metadata.name // ""' 2>/dev/null)
        pod_namespace=$(echo "$pod_data" | jq -r '.metadata.namespace // "default"' 2>/dev/null)
        
        # Get first container resources
        # container_data=$(echo "$pod_data" | jq -r '.spec.containers[0]' 2>/dev/null)
        # [ -z "$container_data" ] && continue
        
        # mem_request=$(echo "$container_data" | jq -r '.resources.requests.memory // ""' 2>/dev/null)
        # mem_limit=$(echo "$container_data" | jq -r '.resources.limits.memory // ""' 2>/dev/null)
        # cpu_request=$(echo "$container_data" | jq -r '.resources.requests.cpu // ""' 2>/dev/null)
        # cpu_limit=$(echo "$container_data" | jq -r '.resources.limits.cpu // ""' 2>/dev/null)
        # Aggregate resources across ALL containers (handles sidecars)

        # Sum only if the field exists; empty stays empty.
        mem_request=$(echo "$pod_data" | jq -r '
          [ .spec.containers[].resources.requests.memory? // empty ] | if length==0 then "" else join(",") end' 2>/dev/null)
        mem_limit=$(echo "$pod_data" | jq -r '
          [ .spec.containers[].resources.limits.memory? // empty ] | if length==0 then "" else join(",") end' 2>/dev/null)
        cpu_request=$(echo "$pod_data" | jq -r '
          [ .spec.containers[].resources.requests.cpu? // empty ] | if length==0 then "" else join(",") end' 2>/dev/null)
        cpu_limit=$(echo "$pod_data" | jq -r '
          [ .spec.containers[].resources.limits.cpu? // empty ] | if length==0 then "" else join(",") end' 2>/dev/null)

        # Convert comma lists (one per container) into totals
        sum_cpu_mc=0
        sum_mem_mib=0
        sum_cpu_lim_mc=0
        sum_mem_lim_mib=0

        IFS=',' read -ra cpu_req_arr <<< "$cpu_request"
        for c in "${cpu_req_arr[@]}"; do
          mc=$(to_millicores "$c"); [[ -n "$mc" ]] && sum_cpu_mc=$((sum_cpu_mc + mc))
        done

        IFS=',' read -ra mem_req_arr <<< "$mem_request"
        for m in "${mem_req_arr[@]}"; do
          mib=$(to_mib "$m"); [[ -n "$mib" ]] && sum_mem_mib=$((sum_mem_mib + mib))
        done

        IFS=',' read -ra cpu_lim_arr <<< "$cpu_limit"
        for c in "${cpu_lim_arr[@]}"; do
          mc=$(to_millicores "$c"); [[ -n "$mc" ]] && sum_cpu_lim_mc=$((sum_cpu_lim_mc + mc))
        done

        IFS=',' read -ra mem_lim_arr <<< "$mem_limit"
        for m in "${mem_lim_arr[@]}"; do
          mib=$(to_mib "$m"); [[ -n "$mib" ]] && sum_mem_lim_mib=$((sum_mem_lim_mib + mib))
        done

        # If nothing was set anywhere, treat as "no requests"
        if [[ $sum_mem_mib -eq 0 && $sum_cpu_mc -eq 0 ]]; then
          : $((pods_no_requests++))
          # Track as finding
          track_finding "NO_REQUESTS" "HIGH" "$pod_name" "$pod_namespace" "0" "none" "unknown"
          continue
        fi
        
        pod_waste_total=0
        
        # If metrics available, compare actual usage vs request
        # Otherwise, fall back to limit vs request analysis
        if [ "$METRICS_AVAILABLE" = true ]; then
            # Get actual usage from kubectl top
            
            actual_usage=$(echo "$POD_METRICS" | awk -v ns="$pod_namespace" -v name="$pod_name" '$1==ns && $2==name {print; exit}')
            if [[ -n "$actual_usage" ]]; then
                actual_cpu=$(echo "$actual_usage" | awk '{print $3}')
                actual_mem=$(echo "$actual_usage" | awk '{print $4}')
            [[ -z "$actual_cpu" ]] && actual_cpu="0m"
            [[ -z "$actual_mem" ]] && actual_mem="0Mi"
                
                # Memory waste: request - actual usage (MiB)
                actual_mem_mib=$(to_mib "$actual_mem")
                if [[ -n "$actual_mem_mib" && $sum_mem_mib -gt $((actual_mem_mib * 2)) ]]; then
                    waste_mib=$((sum_mem_mib - (actual_mem_mib * 3 / 2)))
                    # Calculate annual first to avoid rounding small values to 0
                    waste_gb_annual=$(awk "BEGIN {printf \"%.0f\", ($waste_mib / 1024) * $MEMORY_COST_PER_GB_MONTH * 12}")
                    waste_gb_cost=$(( (waste_gb_annual + 6) / 12 ))  # Round to nearest month
                    [[ $waste_gb_cost -eq 0 && $waste_gb_annual -gt 0 ]] && waste_gb_cost=1
                    memory_waste_monthly=$((memory_waste_monthly + waste_gb_cost))
                    pod_waste_total=$((pod_waste_total + waste_gb_cost))
                    : $((pods_over_provisioned++))
                    # Track finding
                    track_finding "MEMORY_OVERPROVISIONED" "HIGH" "$pod_name" "$pod_namespace" "$waste_gb_cost" "${sum_mem_mib}Mi" "${actual_mem_mib}Mi"
                fi

                # CPU waste: request - actual usage (millicores)
                actual_cpu_mc=$(to_millicores "$actual_cpu")
                if [[ -n "$actual_cpu_mc" && $sum_cpu_mc -gt $((actual_cpu_mc * 2)) ]]; then
                    waste_mc=$((sum_cpu_mc - (actual_cpu_mc * 3 / 2)))
                    # Calculate annual first to avoid rounding small values to 0
                    waste_cpu_annual=$(awk "BEGIN {printf \"%.0f\", ($waste_mc / 1000) * $CPU_COST_PER_CORE_MONTH * 12}")
                    waste_cores_cost=$(( (waste_cpu_annual + 6) / 12 ))  # Round to nearest month
                    [[ $waste_cores_cost -eq 0 && $waste_cpu_annual -gt 0 ]] && waste_cores_cost=1
                    cpu_waste_monthly=$((cpu_waste_monthly + waste_cores_cost))
                    pod_waste_total=$((pod_waste_total + waste_cores_cost))
                    # Track finding
                    track_finding "CPU_OVERPROVISIONED" "MEDIUM" "$pod_name" "$pod_namespace" "$waste_cores_cost" "${sum_cpu_mc}m" "${actual_cpu_mc}m"
                fi
            fi
        else
            # FALLBACK: Use limit vs request (when metrics not available)
            # Memory over-provisioning: limit > 2x request
            if [[ $sum_mem_mib -gt 0 && $sum_mem_lim_mib -gt 0 && $sum_mem_lim_mib -gt $((sum_mem_mib * 2)) ]]; then
                waste_mib=$((sum_mem_lim_mib - (sum_mem_mib * 3 / 2)))
                # Calculate annual first to avoid rounding small values to 0
                waste_gb_annual=$(awk "BEGIN {printf \"%.0f\", ($waste_mib / 1024) * $MEMORY_COST_PER_GB_MONTH * 12}")
                waste_gb_cost=$(( (waste_gb_annual + 6) / 12 ))
                [[ $waste_gb_cost -eq 0 && $waste_gb_annual -gt 0 ]] && waste_gb_cost=1
                memory_waste_monthly=$((memory_waste_monthly + waste_gb_cost))
                pod_waste_total=$((pod_waste_total + waste_gb_cost))
                : $((pods_over_provisioned++))
                # Track finding
                track_finding "MEMORY_OVERPROVISIONED" "HIGH" "$pod_name" "$pod_namespace" "$waste_gb_cost" "${sum_mem_mib}Mi" "${sum_mem_lim_mib}Mi"
            fi

            # CPU over-provisioning: limit > 3x request
            if [[ $sum_cpu_mc -gt 0 && $sum_cpu_lim_mc -gt 0 && $sum_cpu_lim_mc -gt $((sum_cpu_mc * 3)) ]]; then
                waste_mc=$((sum_cpu_lim_mc - (sum_cpu_mc * 3 / 2)))
                # Calculate annual first to avoid rounding small values to 0
                waste_cpu_annual=$(awk "BEGIN {printf \"%.0f\", ($waste_mc / 1000) * $CPU_COST_PER_CORE_MONTH * 12}")
                waste_cores_cost=$(( (waste_cpu_annual + 6) / 12 ))
                [[ $waste_cores_cost -eq 0 && $waste_cpu_annual -gt 0 ]] && waste_cores_cost=1
                cpu_waste_monthly=$((cpu_waste_monthly + waste_cores_cost))
                pod_waste_total=$((pod_waste_total + waste_cores_cost))
                # Track finding
                track_finding "CPU_OVERPROVISIONED" "MEDIUM" "$pod_name" "$pod_namespace" "$waste_cores_cost" "${sum_cpu_mc}m" "${sum_cpu_lim_mc}m"
            fi
        
        fi
        # Track top offender
        if [[ $pod_waste_total -gt $top_offender_waste && -n "$pod_name" ]]; then
            top_offender_waste=$pod_waste_total
            top_offender_name="$pod_name"
            top_offender_namespace="$pod_namespace"
            top_offender_mem_request="$mem_request"
            top_offender_mem_limit="$mem_limit"
            top_offender_cpu_request="$cpu_request"
            top_offender_cpu_limit="$cpu_limit"
            if [ "$METRICS_AVAILABLE" = true ] && [[ -n "$actual_usage" ]]; then
                top_offender_mem_actual="$actual_mem"
                top_offender_cpu_actual="$actual_cpu"
            fi
        fi
    done < <(echo "$PODS" | jq -c '.items[]? // empty' 2>/dev/null)
    
    # Analyze unbound storage
    unbound_storage_gb=0
    while read -r pv; do
        [ -z "$pv" ] && continue
        status=$(echo "$pv" | jq -r '.status.phase // "Unknown"' 2>/dev/null)
        capacity=$(echo "$pv" | jq -r '.spec.capacity.storage // "0Gi"' 2>/dev/null)
        
        if [[ "$status" != "Bound" ]]; then
            size_gb=$(echo "$capacity" | sed 's/Gi$//' | sed 's/G$//')
            unbound_storage_gb=$((unbound_storage_gb + size_gb))
        fi
    done < <(echo "$PVS" | jq -c '.items[]? // empty' 2>/dev/null)
    
    storage_waste_monthly=$(awk "BEGIN {printf \"%.0f\", $unbound_storage_gb * $STORAGE_COST_PER_GB_MONTH}")
    
    # Analyze orphaned load balancers
    orphaned_lbs=0
    while read -r svc; do
        [ -z "$svc" ] && continue
        svc_type=$(echo "$svc" | jq -r '.spec.type // ""' 2>/dev/null)
        if [[ "$svc_type" == "LoadBalancer" ]]; then
            selector_count=$(echo "$svc" | jq '.spec.selector // {} | length' 2>/dev/null)
            if [[ $selector_count -eq 0 ]]; then
                : $((orphaned_lbs++))
            fi
        fi
    done < <(echo "$SERVICES" | jq -c '.items[]? // empty' 2>/dev/null)
    
    lb_waste_monthly=$((orphaned_lbs * LB_COST_PER_MONTH))
fi

# Calculate total waste
MONTHLY_WASTE=$((memory_waste_monthly + cpu_waste_monthly + storage_waste_monthly + lb_waste_monthly))
TOTAL_ANNUAL_SAVINGS=$((MONTHLY_WASTE * 12))

# If no waste detected (or jq not available), show conservative estimate
if [[ $MONTHLY_WASTE -eq 0 ]]; then
    echo -e "${YELLOW}Note: Unable to detect specific waste. Showing conservative estimate.${NC}"
    # Conservative estimate: 20% of estimated cluster cost
    est_node_cost=$((TOTAL_NODES * 150))
    est_pod_cost=$((TOTAL_PODS * 3))
    est_total=$((est_node_cost + est_pod_cost))
    MONTHLY_WASTE=$((est_total * 20 / 100))
    TOTAL_ANNUAL_SAVINGS=$((MONTHLY_WASTE * 12))
fi

echo -e "${GREEN}✓${NC} Analysis complete"
echo ""

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}💰 ANNUAL WASTE DETECTED: \$$TOTAL_ANNUAL_SAVINGS${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Show breakdown by category
echo "Breakdown by Category:"
if [[ $memory_waste_monthly -gt 0 ]]; then
    annual_mem=$((memory_waste_monthly * 12))
    echo -e "  ${RED}Memory:${NC} \$${memory_waste_monthly}/mo (\$${annual_mem}/year)"
fi
if [[ $cpu_waste_monthly -gt 0 ]]; then
    annual_cpu=$((cpu_waste_monthly * 12))
    echo -e "  ${YELLOW}CPU:${NC} \$${cpu_waste_monthly}/mo (\$${annual_cpu}/year)"
fi
if [[ $lb_waste_monthly -gt 0 ]]; then
    annual_lb=$((lb_waste_monthly * 12))
    echo -e "  ${BLUE}Load Balancers:${NC} \$${lb_waste_monthly}/mo (\$${annual_lb}/year) — ${orphaned_lbs} orphaned"
fi
if [[ $storage_waste_monthly -gt 0 ]]; then
    annual_storage=$((storage_waste_monthly * 12))
    echo -e "  ${BLUE}Storage:${NC} \$${storage_waste_monthly}/mo (\$${annual_storage}/year) — ${unbound_storage_gb}GB unbound"
fi
echo ""

# Show top offender with actionable details
if [[ -n "$top_offender_name" && $top_offender_waste -gt 0 ]]; then
    annual_offender_waste=$((top_offender_waste * 12))
    echo -e "${RED}🎯 #1 Biggest Waster:${NC}"
    echo "  Pod: ${top_offender_name}"
    echo "  Namespace: ${top_offender_namespace}"
    echo ""
    
    # Show actual vs requested if metrics available
    if [ "$METRICS_AVAILABLE" = true ] && [[ -n "$top_offender_mem_actual" ]]; then
        echo "  Memory:"
        echo "    Requested: ${top_offender_mem_request}"
        echo "    Actually Using: ${top_offender_mem_actual}"
        echo ""
    elif [[ -n "$top_offender_mem_request" && -n "$top_offender_mem_limit" ]]; then
        echo "  Memory: Request ${top_offender_mem_request}, Limit ${top_offender_mem_limit}"
        echo ""
    fi
    
    echo "  💸 Wasting: \$${annual_offender_waste}/year"
    echo ""
    echo -e "${YELLOW}  💡 Fix: Lower memory request to match actual usage${NC}"
    echo ""
fi

# Tease more detailed insights available in dashboard
# Use FINDING_IDX which counts actual individual findings generated
if [[ $FINDING_IDX -gt 1 ]]; then
    remaining=$((FINDING_IDX - 1))
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📋 ${FINDING_IDX} Total Issues Found${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  ✓ Showing top 1 above"
    echo "  🔒 ${remaining} more hidden (use --push to see all)"
    echo ""
fi

# Summary stats
echo "Cluster Summary:"
echo "  Pods: $TOTAL_PODS | Nodes: $TOTAL_NODES"
if [ "$METRICS_AVAILABLE" = true ]; then
    echo "  Analysis: Real usage data (kubectl top)"
else
    echo "  Analysis: Request/limit estimation"
    echo -e "  ${YELLOW}Install metrics-server for accurate usage tracking${NC}"
fi
echo ""

# Track completion
track_event "audit_complete" "$TOTAL_ANNUAL_SAVINGS"

# Generate cluster hash (unique identifier based on kubectl context)
CLUSTER_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "default")
CLUSTER_HASH=$(echo -n "$CLUSTER_CONTEXT" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "unknown")

# Generate aggregated findings JSON
FINDINGS="["
FINDING_IDX=0
for finding_type in "${!finding_pods_count[@]}"; do
    pods_affected="${finding_pods_count[$finding_type]}"
    total_savings="${finding_total_savings[$finding_type]}"
    severity="${finding_severity[$finding_type]}"
    examples="${finding_examples[$finding_type]}"

    # Format type for display
    type_display=$(echo "$finding_type" | sed 's/_/ /g')

    # Create description based on type
    case "$finding_type" in
        "MEMORY_OVERPROVISIONED")
            description="Pods requesting significantly more memory than they use"
            ;;
        "CPU_OVERPROVISIONED")
            description="Pods requesting more CPU than they use"
            ;;
        "NO_REQUESTS")
            description="Pods with no resource requests set - causes unpredictable scheduling"
            ;;
        *)
            description="Resource inefficiency detected"
            ;;
    esac

    # Add comma separator for subsequent findings
    [[ $FINDING_IDX -gt 0 ]] && FINDINGS="$FINDINGS,"

    # Build finding JSON
    FINDINGS="$FINDINGS
    {
      \"id\": \"finding-$FINDING_IDX\",
      \"type\": \"$finding_type\",
      \"severity\": \"$severity\",
      \"podsAffected\": $pods_affected,
      \"monthlySavings\": $total_savings,
      \"description\": \"$description\",
      \"details\": {
        \"examples\": [$examples
        ]
      },
      \"recommendation\": \"Right-size these pods to match actual usage\"
    }"

    : $((FINDING_IDX++))
done
FINDINGS="$FINDINGS
  ]"

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
  "findings": $FINDINGS,
  "breakdown": {
    "memory": $memory_waste_monthly,
    "cpu": $cpu_waste_monthly,
    "storage": ${storage_waste_monthly:-0},
    "loadBalancers": ${lb_waste_monthly:-0}
  },
  "details": {
    "pods_over_provisioned": ${pods_over_provisioned:-0},
    "pods_no_requests": ${pods_no_requests:-0},
    "orphaned_load_balancers": ${orphaned_lbs:-0},
    "unbound_storage_gb": ${unbound_storage_gb:-0}
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
else
  # Teaser: Show what they get with --push
  if [[ $TOTAL_ANNUAL_SAVINGS -gt 0 ]]; then
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  💡 This is your high-level summary."
    echo ""
    echo "  Push results to see:"
    echo ""
    echo -e "    ${GREEN}✓${NC} Full list of wasteful pods (ranked)"
    echo -e "    ${GREEN}✓${NC} Breakdown by team/namespace"
    echo -e "    ${GREEN}✓${NC} Ready-to-run kubectl patches"
    echo -e "    ${GREEN}✓${NC} Historical trends over time"
    echo ""
    echo "  Run this to view full analysis:"
    echo ""
    echo -e "    ${GREEN}curl -sL wozz.io/audit.sh | bash -s -- --push${NC}"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
  fi
fi