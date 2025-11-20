# Wozz - Kubernetes Cost Optimization Platform

**Prevent infrastructure waste BEFORE deployment. Like spell-check for infrastructure costs.**

## 🎯 What is Wozz?

Wozz is a two-phase Kubernetes cost optimization platform:

**Phase 1: Live Cluster Auditing** (Available Now)
- Run `wozz-audit.sh` to scan your cluster
- Get detailed waste analysis
- Manual consulting to implement fixes

**Phase 2: Shift-Left Prevention** (Coming Soon)
- CLI integrates into CI/CD
- Blocks wasteful deployments before production
- Continuous cost optimization

## 🚀 Quick Start

### Audit Your Cluster (Phase 1)

```bash
# Download and run the audit script
curl -O https://raw.githubusercontent.com/WozzHQ/wozz/main/scripts/wozz-audit.sh
chmod +x wozz-audit.sh
./wozz-audit.sh
```

This creates: `wozz-audit-TIMESTAMP.tar.gz`

**Email to:** audit@wozz.io

**What it collects:**
- ✅ Resource requests/limits configurations
- ✅ Current usage metrics (if metrics-server available)
- ✅ Node capacity information
- ✅ Storage allocations

**What it DOESN'T collect:**
- ❌ Secrets or sensitive data
- ❌ Application code
- ❌ Environment variables
- ❌ Logs

### CLI Usage (Phase 2 - Coming Soon)

Phase 2 will include a TypeScript CLI and Go agent for CI/CD integration. Coming Q2 2025.

## 📊 How It Works

### Phase 1: The Audit (Manual Analysis)

```
Your Cluster → wozz-audit.sh → Anonymized Data →
Email to Wozz → Manual Analysis → Detailed Report →
Consulting Engagement
```

### Phase 2: The Platform (Automated Prevention)

```
Developer writes YAML → Git Push → CI/CD runs wozz check →
wozz CLI calls Agent → Agent queries Prometheus →
Agent returns risk score →
✅ Safe = Deploy | ❌ Wasteful = Block PR
```

## 🏗️ Architecture

### Phase 1
- **Bash Script**: Collects cluster data locally
- **Python Analyzer**: Generates preliminary findings
- **Manual Service**: Expert analysis & recommendations

### Phase 2
- **TypeScript CLI**: Developer-facing tool (runs in CI/CD)
- **Go Agent**: In-cluster service (queries Prometheus)
- **Prometheus**: Metrics source (historical usage data)

## 💰 Pricing

### Phase 1: Consulting
- **Free Audit**: Run script, email results, get report
- **Implementation**: $10K flat OR 15% of first-year savings
- **Guarantee**: Find 3x our fee in savings or free

### Phase 2: SaaS (Coming Q2 2025)
- **Free**: CLI with basic checks
- **Starter**: $299/mo - 1-5 clusters, benchmark data
- **Pro**: $999/mo - Unlimited clusters, API access
- **Enterprise**: $5K+/mo - SSO, support, SLA

## 🛠️ Development

```bash
# Clone repo
git clone https://github.com/WozzHQ/wozz.git
cd wozz

# Run audit script
chmod +x scripts/wozz-audit.sh
./scripts/wozz-audit.sh

# Test anonymization
./scripts/verify-anonymization.sh
```

## 📚 Documentation

- [Quick Start Guide](scripts/README.md)
- [Testing Guide](test-fixtures/README.md)

## 🤝 Contributing

We welcome contributions! Please open an issue or submit a pull request.

## 📄 License

MIT License - see [LICENSE](LICENSE)

## 🔗 Links

- **Website**: https://wozz.io
- **Documentation**: https://docs.wozz.io
- **Blog**: https://wozz.io/blog
- **Twitter**: [@wozz_io](https://twitter.com/wozz_io)

## 🆘 Support

- **Email**: support@wozz.io
- **Audit Submissions**: audit@wozz.io
- **Slack**: [Join our community](https://wozz.io/slack)
- **GitHub Issues**: [Report bugs](https://github.com/WozzHQ/wozz/issues)

## 🎯 The Problem We Solve

**Every Kubernetes cluster wastes 30-50% of its budget on:**
- Over-provisioned memory (limits 4x higher than usage)
- Unused CPU capacity
- Missing resource requests (scheduling inefficiency)
- Idle nodes and storage

**Wozz finds this waste BEFORE it costs you money.**

---

**Built with ❤️ for the Kubernetes community**
