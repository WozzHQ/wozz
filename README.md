# Wozz - Agentless Kubernetes Cost Auditor

**Find wasted resources in your Kubernetes cluster in 15 minutes. No agent installation required.**

Most Kubernetes clusters over-provision CPU and Memory by 40-60%. Existing tools (Kubecost, CastAI) require installing heavy agents, which triggers long security reviews.

**Wozz is different.** It is a lightweight Bash script that runs locally on your machine, using your existing `kubectl` credentials to identify the gap between *Requested Resources* and *Actual Usage*.

## 🚀 Quick Start

### 1. Run the Audit

No installation required. Uses standard `kubectl` commands.

```bash
curl -sL https://raw.githubusercontent.com/WozzHQ/wozz/main/scripts/wozz-audit.sh | bash
```

### 2. Get Your Report

The script generates an anonymized `.tar.gz` file containing ONLY anonymized data (all raw files are deleted after processing). Email this file to `support@wozz.io` to receive your Savings Report.

## 🛡️ Security & Privacy

We designed this to be "Paranoid-Proof."

### What it Collects ✅

- Resource Requests & Limits (CPU/Memory)
- Current Usage Metrics (`kubectl top`)
- Node Capacity & Instance Types
- Storage (PV/PVC) sizes

### What it DOES NOT Collect ❌

- **No Secrets:** We strip all Secrets, ConfigMaps, and Env Vars.
- **No Source Code:** We never look at application logic.
- **No Identifiers:** Pod names, Namespaces, and Labels are hashed locally before export.

You can verify the code in `scripts/wozz-audit.sh` or run our verification script to prove anonymity before sending.

**Read our full [Privacy Policy](PRIVACY.md)** for details on data retention, usage, and your rights.

## 📊 Example Findings

Common issues this tool detects:

- **Fear-Based Limits:** Developers requesting 8GB RAM for apps using 500MB.
- **Orphaned Resources:** Load balancers and PVCs attached to dead workloads.
- **Bin-Packing Inefficiency:** Nodes that are 20% utilized but cannot accept new pods.

## 🛠️ Development

If you want to inspect the code or run it manually:

```bash
# Clone repo
git clone https://github.com/WozzHQ/wozz.git
cd wozz

# Run audit script
bash scripts/wozz-audit.sh

# Test anonymization
./scripts/verify-anonymization.sh
```

## 🆘 Support

- **Email:** support@wozz.io
- **Issues:** [Open a GitHub Issue](https://github.com/WozzHQ/wozz/issues)
- **Privacy:** [Privacy Policy](PRIVACY.md)
- **License:** MIT

Built for the Kubernetes Community.
