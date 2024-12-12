# Wozz - Kubernetes Resource Audit Tool

**Find over-provisioned resources in your K8s cluster. See exactly what you're wasting.**

[![Stars](https://img.shields.io/github/stars/WozzHQ/wozz?style=social)](https://github.com/WozzHQ/wozz)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

---

## Quick Start

```bash
curl -sL wozz.io/audit.sh | bash
```

See your waste breakdown instantly. No signup. No agents. Runs locally.

---

## What It Does

Most K8s clusters over-provision CPU and memory by 30-60%. This script analyzes your pod resource configs and shows you the gap.

```yaml
# What teams typically set:
resources:
  limits:
    memory: "4Gi"
    cpu: "1"

# What the app actually needs:
# memory: ~800Mi
# cpu: ~200m
```

**Wozz finds these gaps and estimates the cost.**

---

## Example Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WOZZ KUBERNETES AUDIT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💰 ANNUAL WASTE DETECTED: $14,880
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Breakdown by Category:
  Memory: $840/mo ($10,080/year)
  CPU: $360/mo ($4,320/year)
  Load Balancers: $40/mo ($480/year) — 2 orphaned

🎯 #1 Biggest Waster:
  Pod: api-gateway
  Namespace: production
  💸 Wasting: $8,400/year
  
  💡 Fix: Lower memory request to match actual usage
```

---

## What It Detects

| Issue | Description | Typical Savings |
|-------|-------------|-----------------|
| Over-provisioned memory | Requests > Actual Usage (kubectl top) | $5-50/pod/month |
| Over-provisioned CPU | Requests > Actual Usage (kubectl top) | $5-30/pod/month |
| Orphaned load balancers | LBs with no backend | ~$20/month each |
| Unbound volumes | PVs not attached | ~$10/100GB/month |

**Note:** Requires metrics-server for accurate usage data. Falls back to request/limit analysis if metrics unavailable.

---

## How It Works

Runs these read-only kubectl commands:

```bash
kubectl get pods --all-namespaces -o json
kubectl get nodes -o json
kubectl get pv -o json
kubectl get svc --all-namespaces -o json
kubectl top pods --all-namespaces  # For actual usage metrics
```

**Analysis Method:**
- **With metrics-server:** Compares actual pod usage (kubectl top) vs resource requests
- **Without metrics-server:** Falls back to comparing requests vs limits

**No writes. No modifications. No agents installed.**

---

## Track Over Time

Push results to view in a dashboard:

```bash
curl -sL wozz.io/audit.sh | bash -s -- --push
```

Dashboard features:
- Namespace breakdown
- Historical trends
- PDF export
- Alerts when waste increases

---

## Privacy

- **Runs locally** - All analysis happens on your machine
- **Optional upload** - Only sends data if you use `--push`
- **No agents** - Just standard kubectl commands
- **Open source** - Inspect the code yourself

Disable telemetry: `WOZZ_NO_TELEMETRY=1`

---

## Pricing Methodology

Uses conservative cloud pricing averages:

| Resource | Cost | Source |
|----------|------|--------|
| Memory | $7.20/GB/month | AWS/GCP/Azure avg |
| CPU | $21.60/core/month | AWS/GCP/Azure avg |
| Storage | $0.10/GB/month | EBS gp3 / PD-SSD |
| Load Balancer | $20/month | ALB/NLB avg |

Your actual costs may vary with reserved instances, spot pricing, etc.

---

## Requirements

- `kubectl` configured with cluster access
- `curl` 
- `jq` (optional, for detailed analysis)

---

## Options

```bash
# Basic audit (local only)
curl -sL wozz.io/audit.sh | bash

# Push to dashboard
curl -sL wozz.io/audit.sh | bash -s -- --push

# With API token (saves to your account)
curl -sL wozz.io/audit.sh | bash -s -- --push --token YOUR_TOKEN

# Disable telemetry
WOZZ_NO_TELEMETRY=1 curl -sL wozz.io/audit.sh | bash
```

---

## Don't Trust curl | bash?

Download and inspect first:

```bash
curl -o wozz-audit.sh https://wozz.io/audit.sh
cat wozz-audit.sh
bash wozz-audit.sh
```

---

## Links

- Website: [wozz.io](https://wozz.io)
- Docs: [wozz.io/docs](https://wozz.io/docs)
- Issues: [GitHub Issues](https://github.com/WozzHQ/wozz/issues)

---

## License

MIT - See [LICENSE](LICENSE)

---

## Contributing

PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).
