# 🛡️ Wozz PR Cost Linter (GitHub Action)

**Layer 5 of the Wozz Defense Grid**

Automatically detect expensive Kubernetes resource changes in Pull Requests. Stop cost increases before they merge.

[![GitHub Action](https://img.shields.io/badge/Action-Wozz%20PR%20Linter-blue.svg?colorA=24292e&colorB=0366d6&style=flat&longCache=true&logo=github)](https://github.com/WozzHQ/wozz/tree/main/action)

---

## 🎯 What It Does

The Wozz PR Bot analyzes every Pull Request for Kubernetes resource changes and automatically:

1. **Detects** changes to `resources.requests.memory` and `resources.requests.cpu`
2. **Calculates** annual cost impact (memory + CPU)
3. **Posts** a comment if cost increase exceeds your threshold
4. **Recommends** alternatives and optimization strategies

---

## 💰 Cost Model

| Resource | Monthly Cost | Annual Cost |
|:---------|:-------------|:------------|
| 1 GB Memory | $4 | $48 |
| 1 vCPU Core | $20 | $240 |

**Example:** Increasing memory from `4Gi` → `8Gi` costs **$192/year**.

---

## 🚀 Quick Setup

### 1. Create Workflow File

Create `.github/workflows/wozz-cost-check.yml`:

```yaml
name: Wozz Cost Check

on:
  pull_request:
    paths:
      - '**.yaml'
      - '**.yml'
      - '**/Chart.yaml'

jobs:
  cost-lint:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
        with:
          fetch-depth: 0  # Need full history for git diff

      - name: Run Wozz Cost Linter
        uses: WozzHQ/wozz/action@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          cost-threshold: 100  # Alert if annual cost > $100
```

### 2. Done!

That's it. The action will now analyze all PRs touching Kubernetes manifests.

---

## ⚙️ Configuration Options

### Inputs

| Input | Required | Default | Description |
|:------|:---------|:--------|:------------|
| `github-token` | ✅ Yes | - | GitHub token for posting comments (`${{ secrets.GITHUB_TOKEN }}`) |
| `cost-threshold` | No | `50` | Annual cost threshold in USD. PRs exceeding this trigger warnings. |
| `working-directory` | No | `.` | Directory containing Kubernetes manifests |

### Example: Custom Configuration

```yaml
- uses: WozzHQ/wozz/action@v1
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    cost-threshold: 500        # Only alert for big changes
    working-directory: k8s/    # Manifests in subdirectory
```

---

## 📊 Example PR Comment

When the action detects a cost increase above your threshold, it posts:

<img width="700" alt="Wozz PR Comment Example" src="https://wozz.io/images/pr-comment-example.png">

```markdown
## ⚠️ Wozz Cost Alert: MODERATE Impact

This PR changes cloud infrastructure costs by **+$384/yr**.

<details>
<summary><strong>📊 Cost Breakdown by Resource</strong></summary>

| Resource | File | Old Resources | New Resources | Annual Impact |
|:---------|:-----|:--------------|:--------------|:--------------|
| `api-server` | `k8s/api-deployment.yaml` | 4.0Gi / 1.00 CPU | 8.0Gi / 2.00 CPU | **+$384/yr** |

</details>

### 🔍 Recommendations

1. **Validate necessity**: Are these increased resource requests required?
2. **Check actual usage**: Use `kubectl top` to see current utilization
3. **Consider alternatives**: Can you optimize the application instead?
4. **Test in staging**: Verify the new limits are actually needed

---

<sub>**Wozz Defense Grid** - Layer 5: Financial Linter | [Learn More](https://wozz.io)</sub>
```

---

## 🔍 How It Works

### 1. Triggered on PR
The action runs when a PR is opened or updated.

### 2. Git Diff Analysis
Uses `git diff` to find changed `.yaml`/`.yml`/`.helm` files.

### 3. Resource Extraction
Parses Kubernetes manifests and extracts:
- `resources.requests.memory` (before and after)
- `resources.requests.cpu` (before and after)

### 4. Cost Calculation
Applies industry-average pricing:
```
Annual Cost = (Memory_GB × $4 × 12) + (CPU_Cores × $20 × 12)
```

### 5. Threshold Check
If `|Cost_Increase| > threshold`, posts a PR comment.

---

## 🛠️ Advanced Usage

### Monorepo with Multiple Clusters

```yaml
jobs:
  cost-check-prod:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0

      - uses: WozzHQ/wozz/action@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          cost-threshold: 1000
          working-directory: clusters/production

  cost-check-staging:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0

      - uses: WozzHQ/wozz/action@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          cost-threshold: 200
          working-directory: clusters/staging
```

### Helm Charts

The action automatically detects Helm templates. No special configuration needed.

### Block Merges on Cost Increase

Make the action a required check:

```yaml
- uses: WozzHQ/wozz/action@v1
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    cost-threshold: 100

# Action exits with code 1 if threshold exceeded, failing the check
```

Then in GitHub Settings → Branches → Required Checks, add "Wozz Cost Check".

---

## 🔒 Security & Privacy

### Zero-Cost Architecture
- **Runs on your runner** - No external API calls
- **No data export** - Everything stays in your GitHub environment
- **Minimal permissions** - Only needs PR comment access

### Token Scope
The `GITHUB_TOKEN` only needs:
- `pull-requests: write` - To post comments
- `contents: read` - To access git history (already included)

### No Secrets Exposed
- Never reads secret values
- Only analyzes file structure
- Works with private repos

---

## 🐛 Troubleshooting

### "No significant cost changes detected" but I changed resources

**Cause:** Git history not available for diff.

**Solution:** Ensure `fetch-depth: 0` in checkout step:
```yaml
- uses: actions/checkout@v3
  with:
    fetch-depth: 0  # Required!
```

### Action fails with "python3: command not found"

**Cause:** Runner doesn't have Python 3.

**Solution:** Add Python setup step:
```yaml
- uses: actions/setup-python@v4
  with:
    python-version: '3.x'

- uses: WozzHQ/wozz/action@v1
  # ...
```

### Comment not posted to PR

**Cause:** Token doesn't have permission.

**Solution:** Check workflow permissions:
```yaml
permissions:
  contents: read
  pull-requests: write  # Required for comments
```

---

## 📈 Roadmap

### Coming Soon
- **Helm values support** - Analyze values.yaml changes
- **Slack notifications** - Alert teams on big cost changes
- **Historical tracking** - See cost trends over time
- **Custom pricing models** - Override default pricing

### Request a Feature
Open an issue: [github.com/WozzHQ/wozz/issues](https://github.com/WozzHQ/wozz/issues)

---

## 🤝 Contributing

We welcome contributions!

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a Pull Request

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

---

## 📜 License

MIT License - Free to use in commercial and open-source projects.

---

## 🔗 Related

- **Wozz CLI Tool** - Audit existing clusters: [/cli](../cli/README.md)
- **Pricing Model** - Understand cost calculations: [/lib/pricing.py](../lib/pricing.py)
- **Main README** - Full platform overview: [/README.md](../README.md)

---

<p align="center">
  <strong>Layer 5 of the Wozz Defense Grid</strong><br>
  <a href="https://wozz.io">wozz.io</a> • 
  <a href="https://github.com/WozzHQ/wozz">GitHub</a> •
  <a href="https://wozz.io/docs">Documentation</a>
</p>

