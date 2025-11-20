# Wozz Kubernetes Audit Scripts

This directory contains the Phase 1 audit tools for analyzing Kubernetes cluster resource waste.

## Quick Start

### Run the Audit

```bash
# Make sure you have kubectl configured
kubectl config current-context

# Run the audit script
./wozz-audit.sh

# This creates: wozz-audit-TIMESTAMP.tar.gz
```

### Analyze Results (Internal Tool)

```bash
# Extract the audit
tar -xzf wozz-audit-20251119_143022.tar.gz

# Run analysis
python3 analyze-audit.py wozz-audit-20251119_143022/
```

## Prerequisites

- **kubectl** - Must be installed and configured with cluster access
- **python3** - Required for anonymization and analysis
- **tar** and **gzip** - Standard Unix tools (usually pre-installed)

## What the Audit Script Does

1. **Validates Prerequisites**
   - Checks for kubectl installation
   - Verifies cluster connectivity
   - Detects metrics-server availability

2. **Collects Cluster Data**
   - Pod resource configurations (requests/limits)
   - Current resource usage (if metrics-server available)
   - Node capacity information
   - Storage allocations
   - Service configurations

3. **Anonymizes Sensitive Data**
   - Hashes pod/namespace names
   - Removes environment variables
   - Removes secrets and config maps
   - Keeps only resource numbers visible

4. **Creates Output Package**
   - Compressed tarball with all data
   - Human-readable README with next steps
   - Summary statistics

## Output Structure

```
wozz-audit-TIMESTAMP.tar.gz
├── pods-anonymized.json      # Resource configurations (anonymized)
├── usage-pods.txt            # Current pod usage (if metrics available)
├── usage-nodes.txt           # Current node usage (if metrics available)
├── nodes-raw.json            # Node capacity
├── nodes-describe.txt        # Node details
├── pv-raw.json               # Persistent volumes
├── services-raw.json         # Service configurations
├── summary.json              # High-level statistics
└── README.txt                # Instructions for customer
```

## Security & Privacy

**What We Collect:**
- ✅ Resource requests and limits (CPU/memory)
- ✅ Current usage metrics
- ✅ Node capacity
- ✅ Storage allocations

**What We DON'T Collect:**
- ❌ Pod/namespace names (hashed)
- ❌ Container images (hashed)
- ❌ Environment variables
- ❌ Secrets or ConfigMaps
- ❌ Application logs
- ❌ Any application code

**Anonymization:**
- All sensitive strings are SHA-256 hashed
- Only resource numbers remain visible
- Customer can review tarball before sending

## Troubleshooting

### "kubectl: command not found"
Install kubectl: https://kubernetes.io/docs/tasks/tools/

### "Cannot connect to cluster"
Check your kubeconfig:
```bash
kubectl config current-context
kubectl config view
```

### "Metrics server not available"
The script will continue but won't collect usage data. To install:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### "Python3 not found"
Install Python 3.6+ (required for anonymization)

### "Permission denied"
Make scripts executable:
```bash
chmod +x wozz-audit.sh
chmod +x analyze-audit.py
```

## Testing

### Test on Local Cluster

```bash
# Start minikube
minikube start

# Deploy sample workload
kubectl create deployment nginx --image=nginx
kubectl set resources deployment nginx --requests=memory=256Mi,cpu=100m --limits=memory=512Mi,cpu=500m

# Run audit
./wozz-audit.sh

# Verify output
ls -la wozz-audit-*.tar.gz
tar -tzf wozz-audit-*.tar.gz
```

### Test Analysis

```bash
# Extract audit
tar -xzf wozz-audit-*.tar.gz

# Run analysis
python3 analyze-audit.py wozz-audit-*/
```

## Next Steps

1. **Customer runs audit** → Gets tarball
2. **Customer emails tarball** → audit@wozz.io
3. **We analyze** → Generate detailed report
4. **We deliver report** → Within 48 hours
5. **Customer implements** → DIY or hire us ($10K)

## Support

- **Email:** audit@wozz.io
- **Documentation:** https://wozz.io/docs
- **Issues:** https://github.com/wozz-io/wozz/issues


