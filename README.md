# Wozz: Kubernetes Cost Optimization

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub Action](https://img.shields.io/badge/GitHub%20Action-v1-blue)](https://github.com/marketplace/actions/wozz-cost-linter)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/WozzHQ/wozz/blob/main/CONTRIBUTING.md)

**Prevent waste before it ships.**

### Overview

Wozz helps engineering teams reduce Kubernetes spend through two approaches:

| Tool | Purpose | How It Works |
| :--- | :--- | :--- |
| **PR Cost Linter** | **Prevention** | Analyzes pull requests for resource changes and comments with cost impact before merge. |
| **Audit CLI** | **Discovery** | Scans running clusters to identify over-provisioned pods and wasted resources. |

---

### 🛡️ PR Cost Linter (GitHub Action)
*Catches expensive resource changes during code review.*

```yaml
# .github/workflows/wozz.yml
name: Cost Check
on: [pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
      - uses: WozzHQ/wozz/action@main
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          cost-threshold: 100
```

---

### 🔍 Audit CLI
*Identifies waste in your current cluster. Runs locally.*

```bash
# Download, Inspect, Run
curl -o wozz.sh -L https://raw.githubusercontent.com/WozzHQ/wozz/main/scripts/wozz-audit.sh
cat wozz.sh
chmod +x wozz.sh && ./wozz.sh
```

---

### Security

- **Zero Trust:** Runs entirely on your infrastructure (local machine or GitHub runner).
- **No Agents:** No DaemonSets or cluster modifications required.
- **Read-Only:** Only uses `kubectl get` and `kubectl top`.
- **Open Source:** MIT Licensed.

---

### License

MIT License - see [LICENSE](https://github.com/WozzHQ/wozz/blob/main/LICENSE) file for details.

---

<p align="center">
  <strong>Built with ❤️ by the Wozz team</strong><br>
  <a href="https://wozz.io">wozz.io</a>
</p>
