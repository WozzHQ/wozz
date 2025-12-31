# Wozz Audit CLI

**Find Kubernetes waste in 5 minutes.**

Scans your cluster and identifies over-provisioned resources. No agents, no modifications, fully local.

---

## Installation

**Homebrew (Recommended):**
```bash
brew tap WozzHQ/wozz
brew install wozz
```

**Manual:**
```bash
curl -o wozz.sh -L https://raw.githubusercontent.com/WozzHQ/wozz/main/scripts/wozz-audit.sh
cat wozz.sh  # Always inspect before running
chmod +x wozz.sh && ./wozz.sh
```

---

## What It Detects

- **Over-provisioned pods**: Requesting 8Gi, using 500Mi
- **Missing resource requests**: Unbounded workloads
- **Idle load balancers**: $20/month each
- **Orphaned persistent volumes**: Allocated but unused

---

## Requirements

- `kubectl` configured and connected to your cluster
- `kubectl top` working (requires metrics-server)
- Bash shell (Linux/macOS)

---

## Output

```
🛡️  Wozz: Kubernetes Waste Audit
================================

Analyzing cluster: production-cluster

📊 FINDINGS:
-----------
High Waste Pods (>50% over-provisioned):
  • api-server (namespace: default)
    Requested: 8.0Gi memory, 2.0 CPU
    Using: 1.2Gi memory, 0.3 CPU
    Waste: 6.8Gi memory (85%), 1.7 CPU (85%)
    Annual waste: $438

💰 TOTAL ANNUAL WASTE: $52,480
```

---

## Security

- **Read-only**: Uses `kubectl get` and `kubectl top` only
- **No modifications**: Never changes your cluster
- **Runs locally**: All data stays on your machine
- **Open source**: MIT licensed, review the code

---

## Options

```bash
# Basic audit
./wozz.sh

# Disable telemetry
WOZZ_NO_TELEMETRY=1 ./wozz.sh

# Push results to dashboard (requires account)
./wozz.sh --push --token YOUR_API_TOKEN
```

---

## License

MIT - Free to use in commercial and open-source projects.




