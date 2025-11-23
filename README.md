# Wozz - Agentless Kubernetes Cost Auditor

**Find wasted resources in your cluster. No agents. No data uploads.**

Most Kubernetes clusters over-provision CPU and Memory by 40-60%. Existing tools require installing heavy agents, which triggers long security reviews.

**Wozz is different.** It's a lightweight Bash script that runs locally, using your existing `kubectl` credentials. You see savings immediately in your terminal.

## Quick Start

No installation required. Uses standard `kubectl` commands.

```bash
curl -sL wozz.io/audit.sh | bash
```

## What You Get

- **Immediate cost analysis** in your terminal
- **Detailed HTML report** with charts (`wozz-report.html`)
- **Optional:** Web visualizer for interactive analysis (`wozz-audit.json`)

## How It Works

1. Script runs locally using `kubectl`
2. Analyzes resource configs vs usage
3. Calculates waste based on cloud pricing
4. Shows results immediately

## What It Finds

- Over-provisioned memory/CPU limits
- Pods without resource requests
- Orphaned load balancers
- Unused persistent volumes
- Underutilized resources

## Privacy

- All analysis happens locally
- No data leaves your machine
- Optional: Upload to web analyzer (client-side only)
- Optional: Email for consulting help

## Example Output

After running the script, you'll see:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WOZZ AUDIT RESULTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Monthly Waste: $4,250
Annual Savings: $51,000

Cluster Overview:
  • Total Pods: 47
  • Total Nodes: 5

Top Issues:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Over-Provisioned Memory [HIGH] → $2,800/mo
2. Orphaned Load Balancers [MEDIUM] → $1,200/mo
3. Unused Storage [LOW] → $250/mo
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Detailed report: wozz-report.html
Visualize: https://wozz.io/analyze
```

## Three Ways to Use Results

1. **Terminal Summary** - Immediate savings breakdown (shown above)
2. **HTML Report** - Open `wozz-report.html` for detailed charts
3. **Web Analyzer** - Upload `wozz-audit.json` to https://wozz.io/analyze for interactive visualization

## Security & Privacy

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

You can verify the code in `scripts/wozz-audit.sh` or run our verification script to prove anonymity.

**Read our full [Privacy Policy](PRIVACY.md)** for details on data retention, usage, and your rights.

## FAQ

**Q: Is this safe?**  
A: Yes. Script is ~400 lines. Audit it yourself. All analysis happens locally.

**Q: What data is collected?**  
A: None. Unless you email us for consulting help.

**Q: Does it work with EKS/GKE/AKS?**  
A: Yes. Any cluster with `kubectl` access.

**Q: Do I need metrics-server?**  
A: Optional. Without it, we analyze configured limits only (no usage-based waste detection).

**Q: How accurate are the cost estimates?**  
A: We use conservative cloud pricing averages. Actual savings may vary based on your provider and instance types.

## Development

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

## Support

- **Email:** support@wozz.io
- **Issues:** [Open a GitHub Issue](https://github.com/WozzHQ/wozz/issues)
- **Privacy:** [Privacy Policy](PRIVACY.md)
- **License:** MIT

Built for the Kubernetes Community.
