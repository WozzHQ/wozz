# Privacy Policy

**Effective Date:** November 21, 2024

Wozz is committed to protecting your privacy and maintaining the security of your Kubernetes cluster data.

## What Data We Collect

When you run `wozz-audit.sh` and email us the resulting `.tar.gz` file, we collect:

- **Anonymized resource configurations:** Pod requests/limits, node capacity, PV sizes, service configurations
- **Anonymized usage metrics:** CPU and memory usage from `kubectl top` (if metrics-server is available)
- **Summary statistics:** Count of pods, resources without limits, etc.

**What We DO NOT Collect:**
- Secrets or ConfigMaps
- Environment variables
- Application code or logs
- IP addresses (hashed locally before export)
- Cluster names, pod names, or namespaces (hashed locally before export)
- Any personally identifiable information (PII)

All anonymization happens **locally on your machine** before any data leaves your infrastructure.

## How We Use Your Data

Your anonymized cluster data is used **solely** to:

1. Analyze resource allocation vs. actual usage
2. Identify cost optimization opportunities
3. Generate your customized Savings Report

We do not use your data for any other purpose.

## Data Retention

- **Analysis Period:** We retain your data only while generating your report (typically 24-48 hours)
- **Automatic Deletion:** All submitted data is permanently deleted from our systems within **30 days** of receipt
- **Upon Request:** You may request immediate deletion of your data at any time by emailing support@wozz.io

## Data Sharing

We **DO NOT**:
- Sell your data to third parties
- Share your data with advertisers
- Use your data for marketing purposes
- Aggregate your data with other customers without explicit permission

Your data is confidential and treated as proprietary information.

## Security Measures

- All data transmission via email uses standard TLS encryption
- Data is stored in encrypted cloud storage with restricted access
- Only authorized Wozz personnel have access to submitted audit files
- All data is permanently deleted after the retention period

## Your Rights

You have the right to:
- Request a copy of the data we have about you
- Request immediate deletion of your data
- Opt out of any future communications
- Ask questions about our data handling practices

**Contact:** support@wozz.io

## Open Source Transparency

Our audit script is open source (MIT License). You can:
- Review the code at https://github.com/WozzHQ/wozz
- Verify locally that only anonymized data is collected
- Run the script and inspect the output before sending it to us

## Changes to This Policy

We may update this privacy policy from time to time. Changes will be posted to this file with an updated "Effective Date."

## Contact Us

For privacy questions or concerns:
- **Email:** support@wozz.io
- **GitHub Issues:** https://github.com/WozzHQ/wozz/issues

---

**TL;DR:** We only see anonymized metrics. We use them only to generate your report. We delete everything within 30 days. We never sell or share your data.

