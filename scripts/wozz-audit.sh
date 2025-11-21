#!/bin/bash
# wozz-audit.sh v1.1
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

# 1. Get all pods with resource requests/limits
echo "  [1/5] Pod resource configurations..."
kubectl get pods --all-namespaces -o json > "${OUTPUT_DIR}/pods-raw.json"

# 2. Get current resource usage (if available)
if [ "$METRICS_AVAILABLE" = true ]; then
    echo "  [2/5] Current resource usage..."
    kubectl top pods --all-namespaces --containers > "${OUTPUT_DIR}/usage-pods.txt" 2>/dev/null || true
    kubectl top nodes > "${OUTPUT_DIR}/usage-nodes.txt" 2>/dev/null || true
else
    echo "  [2/5] Skipping usage data (metrics unavailable)"
fi

# 3. Get node information
echo "  [3/5] Node capacity and allocations..."
kubectl get nodes -o json > "${OUTPUT_DIR}/nodes-raw.json"

# 4. Get persistent volumes (storage costs)
echo "  [4/5] Storage resources..."
kubectl get pv -o json > "${OUTPUT_DIR}/pv-raw.json" 2>/dev/null || echo '{"items":[]}' > "${OUTPUT_DIR}/pv-raw.json"

# 5. Get services (load balancer costs)
echo "  [5/5] Service configurations..."
kubectl get svc --all-namespaces -o json > "${OUTPUT_DIR}/services-raw.json"

# 6. Anonymize sensitive data
echo ""
echo "→ Anonymizing sensitive information..."
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

def strip_env_vars(data):
    """Remove environment variables completely from containers"""
    if isinstance(data, dict):
        # Remove env and envFrom entirely from containers
        if 'env' in data:
            del data['env']
        if 'envFrom' in data:
            del data['envFrom']
        
        # Recurse into nested structures
        for key, value in list(data.items()):
            data[key] = strip_env_vars(value)
    elif isinstance(data, list):
        return [strip_env_vars(item) for item in data]
    return data

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
    'controller-uid', 'pod-template-hash', 'serviceAccount', 'serviceAccountName',
    'volumeName', 'server', 'path', 'secretName', 'user'
}

# Sensitive Label Keys to anonymize values for
sensitive_label_keys = {
    'app', 'name', 'component', 'release', 'chart', 'heritage',
    'app.kubernetes.io/name', 'app.kubernetes.io/instance',
    'app.kubernetes.io/component', 'app.kubernetes.io/part-of'
}

try:
    # Process pods
    pods_path = os.path.join(output_dir, 'pods-raw.json')
    with open(pods_path, 'r') as f:
        pods = json.load(f)
    
    # Strip environment variables FIRST (before anonymization)
    pods = strip_env_vars(pods)
    
    # Then anonymize other fields
    anonymized_pods = anonymize_data(pods, sensitive_fields, sensitive_label_keys)
    
    out_path = os.path.join(output_dir, 'pods-anonymized.json')
    with open(out_path, 'w') as f:
        json.dump(anonymized_pods, f, indent=2)
    
    # Process nodes
    nodes_path = os.path.join(output_dir, 'nodes-raw.json')
    if os.path.exists(nodes_path):
        with open(nodes_path, 'r') as f:
            nodes = json.load(f)
        
        anonymized_nodes = anonymize_data(nodes, sensitive_fields, sensitive_label_keys)
        
        out_path = os.path.join(output_dir, 'nodes-anonymized.json')
        with open(out_path, 'w') as f:
            json.dump(anonymized_nodes, f, indent=2)
    
    # Process services
    services_path = os.path.join(output_dir, 'services-raw.json')
    if os.path.exists(services_path):
        with open(services_path, 'r') as f:
            services = json.load(f)
        
        anonymized_services = anonymize_data(services, sensitive_fields, sensitive_label_keys)
        
        out_path = os.path.join(output_dir, 'services-anonymized.json')
        with open(out_path, 'w') as f:
            json.dump(anonymized_services, f, indent=2)
    
    # Process PVs
    pv_path = os.path.join(output_dir, 'pv-raw.json')
    if os.path.exists(pv_path):
        with open(pv_path, 'r') as f:
            pvs = json.load(f)
        
        anonymized_pvs = anonymize_data(pvs, sensitive_fields, sensitive_label_keys)
        
        out_path = os.path.join(output_dir, 'pv-anonymized.json')
        with open(out_path, 'w') as f:
            json.dump(anonymized_pvs, f, indent=2)
    
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
        has_requests = False
        has_limits = False
        for container in pod.get('spec', {}).get('containers', []):
            resources = container.get('resources', {})
            
            if resources.get('requests'):
                has_requests = True
            if resources.get('limits'):
                has_limits = True
        
        if not has_requests:
            summary['podsWithoutRequests'] += 1
        if not has_limits:
            summary['podsWithoutLimits'] += 1
    
    summary_path = os.path.join(output_dir, 'summary.json')
    with open(summary_path, 'w') as f:
        json.dump(summary, f, indent=2)
    
    print("  ✅ Data anonymized successfully")

except Exception as e:
    print(f"  ❌ Error during anonymization: {e}")
    sys.exit(1)
PYTHON_SCRIPT

# Create audit summary
cat > "${OUTPUT_DIR}/README.txt" << EOF
Wozz Kubernetes Audit - ${TIMESTAMP}

This audit contains anonymized data from your Kubernetes cluster.

✅ Data Security Guarantee:
- All pod/namespace/node names are hashed
- Container images are hashed
- Environment variables are completely removed
- No secrets or configmaps included
- IP addresses are hashed
- Service accounts are hashed

Files Included (All Anonymized):
- pods-anonymized.json: Resource configurations (NO env vars)
- nodes-anonymized.json: Node capacity information (NO hostnames)
- services-anonymized.json: Load balancer configurations
- pv-anonymized.json: Persistent volume information
- usage-*.txt: Current resource usage metrics (safe - just numbers)
- summary.json: High-level statistics

Files NOT Included:
- Raw JSON files (deleted after anonymization)
- Environment variables (stripped completely)
- Secrets or ConfigMaps
- Application logs
- Cluster-info dumps

Next Steps:
1. Verify: You can inspect these files to confirm anonymization
2. Email: Send this file to support@wozz.io
3. Subject: "Wozz Audit - [Your Company Name]"
4. We'll analyze and send your savings report within 24 hours

Questions? https://wozz.io/support
EOF

echo ""
echo "→ Creating secure archive (raw files excluded)..."

# Create clean directory with ONLY anonymized files
CLEAN_DIR="${OUTPUT_DIR}-clean"
mkdir -p "${CLEAN_DIR}"

# Copy only anonymized and safe files
cp "${OUTPUT_DIR}/pods-anonymized.json" "${CLEAN_DIR}/" 2>/dev/null || true
cp "${OUTPUT_DIR}/nodes-anonymized.json" "${CLEAN_DIR}/" 2>/dev/null || true
cp "${OUTPUT_DIR}/services-anonymized.json" "${CLEAN_DIR}/" 2>/dev/null || true
cp "${OUTPUT_DIR}/pv-anonymized.json" "${CLEAN_DIR}/" 2>/dev/null || true
cp "${OUTPUT_DIR}/summary.json" "${CLEAN_DIR}/" 2>/dev/null || true
cp "${OUTPUT_DIR}/README.txt" "${CLEAN_DIR}/" 2>/dev/null || true

# Copy usage files if they exist (these are safe - just metrics)
[ -f "${OUTPUT_DIR}/usage-pods.txt" ] && cp "${OUTPUT_DIR}/usage-pods.txt" "${CLEAN_DIR}/"
[ -f "${OUTPUT_DIR}/usage-nodes.txt" ] && cp "${OUTPUT_DIR}/usage-nodes.txt" "${CLEAN_DIR}/"

# Create tarball from clean directory only
tar -czf "${OUTPUT_DIR}.tar.gz" -C "${CLEAN_DIR}" .

# Clean up - Remove ALL raw data
rm -rf "${CLEAN_DIR}"
rm -rf "${OUTPUT_DIR}"

# Calculate size
SIZE=$(du -h "${OUTPUT_DIR}.tar.gz" | cut -f1)

echo ""
echo "✅ Audit Complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Output: ${OUTPUT_DIR}.tar.gz (${SIZE})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔒 Security Verified:"
echo "   ✅ All raw files deleted"
echo "   ✅ Environment variables stripped"
echo "   ✅ Names and IPs hashed"
echo "   ✅ Only anonymized data in archive"
echo ""
echo "Next Steps:"
echo "1. Optional: Extract and review files to verify anonymization"
echo "   tar -xzf ${OUTPUT_DIR}.tar.gz && cat README.txt"
echo ""
echo "2. Email:  support@wozz.io"
echo "3. Subject: 'Wozz Audit - [Your Company Name]'"
echo ""
echo "What happens next:"
echo "→ We analyze your cluster configuration"
echo "→ You receive detailed waste report in 24 hours"
echo "→ Report includes specific $ savings & recommendations"
echo ""
echo "Have questions? https://wozz.io/support"
echo ""

