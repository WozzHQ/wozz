# Wozz: The Cloud Cost Simulation Engine

Wozz is an open-source, extensible engine that finds expensive "cost anti-patterns" in your Python code.

## This is Not Another Naive Linter

Most linters just "find loops." This is naive.

A real cloud cost bug is a complex trade-off between API calls, data transfer, and memory. A simple linter can't tell you the dollar impact of your code.

Wozz is a simulation engine. It's a pluggable rule system that ingests code + context (like real-time cloud prices) to give you a true dollar-impact estimate, not just a warning.

## How It Works

Wozz parses your code into an Abstract Syntax Tree (AST) and runs it against a set of rules.

**Rule**: `NPlusOneAPICallRule`

**Context**: `{"aws.pricing.data_transfer_out": $0.09/GB}`

**Finding**: `[HIGH] $0.0913/call - L28: N+1 API call in loop`

## Usage

This is the free, open-source engine.

```bash
# Run locally
python3 cost_bug_finder.py /path/to/your/code
```

## The Wozz Pro (Coming Soon)

The free engine is powerful. The SaaS app is the "brain."

The Pro version (coming soon) will:

- Connect to your AWS/GCP account (read-only).
- Feed your real, live pricing into the Wozz engine.
- Give you a 100% accurate dollar-impact report inside your PRs.
- Provide AI-generated fixes that actually balance cost, data, and memory.

Sign up for the Pro Beta at [wozz.com](https://wozz.com)
