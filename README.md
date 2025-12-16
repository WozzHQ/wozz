# Wozz

**Kubernetes cost optimization. Prevent waste before it ships.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## Overview

Wozz helps engineering teams reduce Kubernetes spend through two approaches:

| Tool | Purpose | How It Works |
| :--- | :--- | :--- |
| **[PR Cost Linter](./action)** | Prevention | Analyzes pull requests for resource changes and comments with cost impact before merge. |
| **[Audit CLI](./cli)** | Discovery | Scans running clusters to identify over-provisioned pods and wasted resources. |

---

## PR Cost Linter (GitHub Action)

Catches expensive resource changes during code review.

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
      - uses: WozzHQ/wozz/action@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          cost-threshold: 100
```

[View documentation →](./action)

---

## Audit CLI

Identifies waste in your current cluster. Runs locally.

```bash
curl -o wozz.sh -L https://wozz.io/audit.sh
cat wozz.sh
chmod +x wozz.sh && ./wozz.sh
```

[View documentation →](./cli)

---

## Security

- Runs on your infrastructure (local machine or GitHub runner)
- No agents or cluster modifications
- Read-only operations only
- Fully open source

---

## License

MIT
