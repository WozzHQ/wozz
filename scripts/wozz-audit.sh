#!/bin/bash
# wozz-audit.sh v1.0
# Agentless Kubernetes Cost Audit Tool
# Compares resource requests vs actual usage to find waste

set -e

echo "🔍 Wozz Kubernetes Cost Audit"
echo "======================================"
echo ""

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi

# Test cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to cluster. Please check your kubeconfig."
    exit 1
fi

echo "✅ Connected to cluster: $(kubectl config current-context)"
echo ""

# Check for metrics-server (critical for waste calculation)
echo "→ Checking for metrics-server..."
if ! kubectl top nodes &> /dev/null; then
    echo "⚠️  WARNING: Metrics server not available."
    echo "   We can analyze configured limits, but not actual waste."
    echo "   To install: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    METRICS_AVAILABLE=false
else
    echo "✅ Metrics server available"
    METRICS_AVAILABLE=true
fi
echo ""

# Create output directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="wozz-audit-${TIMESTAMP}"
mkdir -p "${OUTPUT_DIR}"

echo "→ Collecting cluster data..."
echo ""

# 1. Get cluster info
echo "  [1/7] Cluster overview..."
kubectl cluster-info dump --namespaces="" --output-directory="${OUTPUT_DIR}/cluster-info" > /dev/null 2>&1

# 2. Get all pods with resource requests/limits
echo "  [2/7] Pod resource configurations..."
kubectl get pods --all-namespaces -o json > "${OUTPUT_DIR}/pods-raw.json"

# 3. Get current resource usage (if available)
if [ "$METRICS_AVAILABLE" = true ]; then
    echo "  [3/7] Current resource usage..."
    kubectl top pods --all-namespaces --containers > "${OUTPUT_DIR}/usage-pods.txt" 2>/dev/null || true
    kubectl top nodes > "${OUTPUT_DIR}/usage-nodes.txt" 2>/dev/null || true
else
    echo "  [3/7] Skipping usage data (metrics unavailable)"
fi

# 4. Get node information
echo "  [4/7] Node capacity and allocations..."
kubectl get nodes -o json > "${OUTPUT_DIR}/nodes-raw.json"
kubectl describe nodes > "${OUTPUT_DIR}/nodes-describe.txt"

# 5. Get persistent volumes (storage costs)
echo "  [5/7] Storage resources..."
kubectl get pv -o json > "${OUTPUT_DIR}/pv-raw.json" 2>/dev/null || echo "No PVs found" > "${OUTPUT_DIR}/pv-raw.json"

# 6. Get services (load balancer costs)
echo "  [6/7] Service configurations..."
kubectl get svc --all-namespaces -o json > "${OUTPUT_DIR}/services-raw.json"

# 7. Anonymize sensitive data
echo "  [7/7] Anonymizing sensitive information..."
# Pass the OUTPUT_DIR as the first argument to the python script
python3 - "${OUTPUT_DIR}" << 'PYTHON_SCRIPT'
import json
import hashlib
import sys
import os

# Get the directory from the command line argument
output_dir = sys.argv[1]

def anonymize_string(s):
    """Hash sensitive strings while preserving uniqueness"""
    if not s:
        return s
    return hashlib.sha256(s.encode()).hexdigest()[:12]

def anonymize_data(data, sensitive_fields, sensitive_label_keys):
    """Recursively anonymize sensitive fields in nested structures"""
    if isinstance(data, dict):
        for key, value in list(data.items()):
            # Case 1: Key is in the sensitive fields blocklist (e.g. "name", "image")
            if key in sensitive_fields:
                if isinstance(value, str):
                    data[key] = anonymize_string(value)
            
            # Case 2: We are inside a "labels" or "annotations" dict
            elif key in ['labels', 'annotations', 'matchLabels'] and isinstance(value, dict):
                for label_key, label_val in list(value.items()):
                    if label_key in sensitive_label_keys:
                        value[label_key] = anonymize_string(label_val)
            
            # Recursion
            else:
                data[key] = anonymize_data(value, sensitive_fields, sensitive_label_keys)
    elif isinstance(data, list):
        return [anonymize_data(item, sensitive_fields, sensitive_label_keys) for item in data]
    return data

# Fields to anonymize - Expanded List
sensitive_fields = {
    'name', 'namespace', 'uid', 'hostname', 'nodeName',
    'clusterName', 'selfLink', 'resourceVersion',
    'ip', 'hostIP', 'podIP', 'claimRef',
    'generateName', 'image', 'imageID', 'message', 'reason',
    'controller-uid', 'pod-template-hash', 'serviceAccount', 'serviceAccountName'
}

# Sensitive Label Keys to anonymize values for
sensitive_label_keys = {
    'app', 'name', 'component', 'release', 'chart', 'heritage',
    'app.kubernetes.io/name', 'app.kubernetes.io/instance',
    'app.kubernetes.io/component', 'app.kubernetes.io/part-of'
}

# Process pods
try:
    # Use os.path.join with the passed directory
    pods_path = os.path.join(output_dir, 'pods-raw.json')
    with open(pods_path, 'r') as f:
        pods = json.load(f)
    
    anonymized_pods = anonymize_data(pods, sensitive_fields, sensitive_label_keys)
    
    out_path = os.path.join(output_dir, 'pods-anonymized.json')
    with open(out_path, 'w') as f:
        json.dump(anonymized_pods, f, indent=2)
    
    # Extract resource summary
    summary = {
        'totalPods': len(pods.get('items', [])),
        'podsWithoutRequests': 0,
        'podsWithoutLimits': 0,
        'resourceStats': {
            'cpuRequested': 0,
            'memoryRequested': 0,
            'cpuLimited': 0,
            'memoryLimited': 0
        }
    }
    
    for pod in pods.get('items', []):
        for container in pod.get('spec', {}).get('containers', []):
            resources = container.get('resources', {})
            
            if not resources.get('requests'):
                summary['podsWithoutRequests'] += 1
            if not resources.get('limits'):
                summary['podsWithoutLimits'] += 1
    
    summary_path = os.path.join(output_dir, 'summary.json')
    with open(summary_path, 'w') as f:
        json.dump(summary, f, indent=2)
    
    print("✅ Data anonymized successfully")

except Exception as e:
    print(f"❌ Error during anonymization: {e}")
    sys.exit(1)
PYTHON_SCRIPT

# Create audit summary
cat > "${OUTPUT_DIR}/README.txt" << EOF
Wozz Kubernetes Audit - ${TIMESTAMP}

This audit contains anonymized data from your Kubernetes cluster.

Data Collected:
✅ Resource requests and limits (CPU/memory)
✅ Current usage patterns (if metrics-server available)
✅ Node capacity information
✅ Storage allocation
✅ Service configurations

Data NOT Collected:
❌ Pod/namespace names (hashed for privacy)
❌ Container images (hashed)
❌ Environment variables
❌ Secrets or ConfigMaps
❌ Application logs

What's Included:
- pods-anonymized.json: Resource configurations
- usage-*.txt: Current resource usage
- nodes-*.txt: Node capacity and utilization
- pv-raw.json: Persistent volume information
- services-raw.json: Load balancer configurations
- summary.json: High-level statistics

Next Steps:
1. Review this data to ensure you're comfortable sharing
2. Create archive: tar -czf audit.tar.gz ${OUTPUT_DIR}
3. Email to: audit@wozz.io
4. We'll analyze and send your detailed savings report within 48 hours

Questions? https://wozz.io/support
EOF

# Create compressed archive
echo ""
echo "→ Creating compressed archive..."
tar -czf "${OUTPUT_DIR}.tar.gz" "${OUTPUT_DIR}"

# Calculate size
SIZE=$(du -h "${OUTPUT_DIR}.tar.gz" | cut -f1)

echo ""
echo "✅ Audit Complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Output: ${OUTPUT_DIR}.tar.gz (${SIZE})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next Steps:"
echo "1. Review: cat ${OUTPUT_DIR}/README.txt"
echo "2. Email:  audit@wozz.io"
echo "3. Subject: 'Wozz Audit - [Your Company Name]'"
echo ""
echo "What happens next:"
echo "→ We analyze your cluster configuration"
echo "→ You receive detailed waste report in 48 hours"
echo "→ Report includes specific \$ savings & recommendations"
echo ""
echo "Have questions? https://wozz.io/call"
echo ""


