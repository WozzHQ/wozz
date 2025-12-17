#!/usr/bin/env python3
"""
Wozz Layer 5: Financial Linter (PR Bot)
Detects expensive Kubernetes resource changes in Pull Requests.
"""

import os
import re
import sys
import subprocess
import json
from typing import List, Dict, Tuple, Optional
import requests

# Pricing constants (monthly)
MEMORY_COST_PER_GB = 4.0  # $/GB/month
CPU_COST_PER_CORE = 20.0  # $/vCPU/month

def parse_resource_value(value: str, resource_type: str) -> float:
    """Convert K8s resource strings to numeric values."""
    if not value:
        return 0.0
    
    value = value.strip()
    
    if resource_type == "memory":
        # Memory: 8Gi, 4096Mi, 2G, etc.
        if value.endswith("Gi"):
            return float(value[:-2])
        elif value.endswith("G"):
            return float(value[:-1])
        elif value.endswith("Mi"):
            return float(value[:-2]) / 1024
        elif value.endswith("M"):
            return float(value[:-1]) / 1024
        elif value.endswith("Ki"):
            return float(value[:-2]) / (1024 * 1024)
        elif value.endswith("K"):
            return float(value[:-1]) / (1024 * 1024)
        else:
            # Assume bytes
            return float(value) / (1024 * 1024 * 1024)
    
    elif resource_type == "cpu":
        # CPU: 2, 500m, 0.5, etc.
        if value.endswith("m"):
            return float(value[:-1]) / 1000
        else:
            return float(value)
    
    return 0.0

def calculate_annual_cost(memory_gb: float, cpu_cores: float) -> float:
    """Calculate annual infrastructure cost."""
    monthly_cost = (memory_gb * MEMORY_COST_PER_GB) + (cpu_cores * CPU_COST_PER_CORE)
    return monthly_cost * 12

def extract_resources_from_yaml(yaml_content: str, file_path: str) -> Dict[str, Dict]:
    """
    Extract resource requests and replica info from Kubernetes YAML.
    Returns dict of {resource_name: {memory: X, cpu: Y, min_replicas: N, max_replicas: M}}
    """
    resources = {}

    # Split YAML into separate documents (separated by ---)
    documents = yaml_content.split('\n---\n')

    # Regex patterns for resource extraction
    memory_pattern = r'requests:\s*\n(?:[^\n]*\n)*?\s*memory:\s*["\']?([^"\'\n]+)["\']?'
    cpu_pattern = r'requests:\s*\n(?:[^\n]*\n)*?\s*cpu:\s*["\']?([^"\'\n]+)["\']?'

    # Extract resource name and type
    name_pattern = r'metadata:\s*\n\s*name:\s*["\']?([a-zA-Z0-9-]+)["\']?'
    kind_pattern = r'kind:\s*([A-Za-z]+)'

    # Replica patterns
    replicas_pattern = r'(?:^|\n)replicas:\s*(\d+)'
    min_replicas_pattern = r'minReplicas:\s*(\d+)'
    max_replicas_pattern = r'maxReplicas:\s*(\d+)'

    # Process each document separately
    for doc_index, document in enumerate(documents):
        if not document.strip():
            continue

        # Extract resource name and kind
        resource_name = f"resource-{doc_index}"
        name_match = re.search(name_pattern, document)
        if name_match:
            resource_name = name_match.group(1)

        kind_match = re.search(kind_pattern, document)
        resource_kind = kind_match.group(1) if kind_match else "Unknown"

        # Extract memory and cpu independently
        memory_match = re.search(memory_pattern, document)
        cpu_match = re.search(cpu_pattern, document)

        if memory_match or cpu_match:
            memory_gb = 0.0
            cpu_cores = 0.0

            if memory_match:
                memory_gb = parse_resource_value(memory_match.group(1), "memory")
            if cpu_match:
                cpu_cores = parse_resource_value(cpu_match.group(1), "cpu")

            # Extract replica information
            min_replicas = 1
            max_replicas = 1

            # Check for HPA (HorizontalPodAutoscaler)
            if resource_kind == "HorizontalPodAutoscaler":
                min_match = re.search(min_replicas_pattern, document)
                max_match = re.search(max_replicas_pattern, document)
                if min_match:
                    min_replicas = int(min_match.group(1))
                if max_match:
                    max_replicas = int(max_match.group(1))
            else:
                # Check for static replicas in Deployment/StatefulSet
                replicas_match = re.search(replicas_pattern, document)
                if replicas_match:
                    replicas = int(replicas_match.group(1))
                    min_replicas = replicas
                    max_replicas = replicas

            resources[f"{resource_name}@{file_path}"] = {
                "memory": memory_gb,
                "cpu": cpu_cores,
                "min_replicas": min_replicas,
                "max_replicas": max_replicas,
                "kind": resource_kind
            }

    return resources

def get_changed_files(base_sha: str, head_sha: str) -> List[str]:
    """Get list of changed YAML/Helm files in the PR."""
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", base_sha, head_sha],
            capture_output=True,
            text=True,
            check=True
        )
        
        files = result.stdout.strip().split("\n")
        # Filter for Kubernetes manifests
        k8s_files = [
            f for f in files
            if f.endswith(('.yaml', '.yml', '.helm'))
            and os.path.exists(f)
        ]
        return k8s_files
    
    except subprocess.CalledProcessError as e:
        print(f"Error getting changed files: {e}")
        return []

def get_file_diff(file_path: str, base_sha: str, head_sha: str) -> Tuple[Optional[str], Optional[str]]:
    """Get old and new content for a file."""
    try:
        # Get old version
        old_content = subprocess.run(
            ["git", "show", f"{base_sha}:{file_path}"],
            capture_output=True,
            text=True
        ).stdout
        
        # Get new version
        new_content = subprocess.run(
            ["git", "show", f"{head_sha}:{file_path}"],
            capture_output=True,
            text=True
        ).stdout
        
        return old_content, new_content
    
    except Exception as e:
        print(f"Error getting diff for {file_path}: {e}")
        return None, None

def analyze_pr_costs(base_sha: str, head_sha: str) -> List[Dict]:
    """Analyze all changed files and calculate cost impacts with risk ranges."""
    changed_files = get_changed_files(base_sha, head_sha)
    print(f"Found {len(changed_files)} changed Kubernetes manifest(s)")

    cost_changes = []

    for file_path in changed_files:
        print(f"Analyzing {file_path}...")

        old_content, new_content = get_file_diff(file_path, base_sha, head_sha)

        if not old_content or not new_content:
            continue

        old_resources = extract_resources_from_yaml(old_content, file_path)
        new_resources = extract_resources_from_yaml(new_content, file_path)

        # Compare resources
        all_resource_names = set(old_resources.keys()) | set(new_resources.keys())

        for resource_name in all_resource_names:
            old_res = old_resources.get(resource_name, {
                "memory": 0, "cpu": 0, "min_replicas": 1, "max_replicas": 1, "kind": "Unknown"
            })
            new_res = new_resources.get(resource_name, {
                "memory": 0, "cpu": 0, "min_replicas": 1, "max_replicas": 1, "kind": "Unknown"
            })

            # Calculate per-pod costs
            old_cost_per_pod = calculate_annual_cost(old_res["memory"], old_res["cpu"])
            new_cost_per_pod = calculate_annual_cost(new_res["memory"], new_res["cpu"])

            # Calculate min/max costs based on replicas
            old_min_cost = old_cost_per_pod * old_res["min_replicas"]
            old_max_cost = old_cost_per_pod * old_res["max_replicas"]
            new_min_cost = new_cost_per_pod * new_res["min_replicas"]
            new_max_cost = new_cost_per_pod * new_res["max_replicas"]

            # Cost diff ranges
            min_cost_diff = new_min_cost - old_min_cost
            max_cost_diff = new_max_cost - old_max_cost

            # Use the worst case (max) for threshold checks
            if abs(max_cost_diff) > 1:  # Only report changes > $1/year
                has_range = new_res["min_replicas"] != new_res["max_replicas"]

                cost_changes.append({
                    "resource": resource_name.split("@")[0],
                    "file": file_path,
                    "old_memory": old_res["memory"],
                    "new_memory": new_res["memory"],
                    "old_cpu": old_res["cpu"],
                    "new_cpu": new_res["cpu"],
                    "old_min_replicas": old_res["min_replicas"],
                    "old_max_replicas": old_res["max_replicas"],
                    "new_min_replicas": new_res["min_replicas"],
                    "new_max_replicas": new_res["max_replicas"],
                    "min_cost_diff": min_cost_diff,
                    "max_cost_diff": max_cost_diff,
                    "has_range": has_range,
                    "kind": new_res.get("kind", "Unknown")
                })

    return cost_changes

def format_cost(cost: float) -> str:
    """Format cost with sign and currency."""
    sign = "+" if cost > 0 else ""
    return f"{sign}${abs(cost):,.0f}/yr"

def get_trend_arrow(cost_diff: float) -> str:
    """Get trend arrow emoji based on cost change."""
    if cost_diff > 1000:
        return "🔴"  # Critical increase
    elif cost_diff > 100:
        return "🟡"  # Moderate increase
    elif cost_diff > 0:
        return "🟢"  # Small increase
    elif cost_diff < -1000:
        return "💚"  # Large savings
    elif cost_diff < -100:
        return "⬇️"  # Moderate savings
    else:
        return "⬇️"  # Small savings

def format_cost_range(min_cost: float, max_cost: float, has_range: bool) -> str:
    """Format cost as a range if applicable."""
    if not has_range or abs(min_cost - max_cost) < 1:
        # Single value
        sign = "+" if max_cost > 0 else ""
        return f"{sign}${abs(max_cost):,.0f}/yr"
    else:
        # Range
        sign_min = "+" if min_cost > 0 else ""
        sign_max = "+" if max_cost > 0 else ""
        return f"{sign_min}${abs(min_cost):,.0f} to {sign_max}${abs(max_cost):,.0f}/yr"

def create_pr_comment(cost_changes: List[Dict], threshold: float, api_key: str = "", repo_full_name: str = "") -> str:
    """Generate formatted PR comment with cost risk ranges."""
    # Calculate total impact using worst-case (max) scenarios
    total_min_impact = sum(change["min_cost_diff"] for change in cost_changes)
    total_max_impact = sum(change["max_cost_diff"] for change in cost_changes)
    has_any_range = any(change["has_range"] for change in cost_changes)

    if abs(total_max_impact) < threshold:
        return ""  # Below threshold, don't comment

    # Determine severity based on worst case
    if total_max_impact > threshold * 5:
        emoji = "🚨"
        severity = "CRITICAL"
    elif total_max_impact > threshold * 2:
        emoji = "⚠️"
        severity = "HIGH"
    else:
        emoji = "💰"
        severity = "MODERATE"

    total_impact_str = format_cost_range(total_min_impact, total_max_impact, has_any_range)

    comment = f"""## {emoji} Wozz Cost Alert: {severity} Impact

This PR changes cloud infrastructure costs by **{total_impact_str}**.

"""

    if has_any_range:
        comment += "_Cost shown as range due to autoscaling (min-max replicas)._\n\n"

    comment += """<details>
<summary><strong>📊 Cost Breakdown by Resource</strong></summary>

| Resource | File | Old Config | New Config | Annual Impact |
|:---------|:-----|:-----------|:-----------|:--------------|
"""

    # Sort by worst-case cost impact (descending)
    cost_changes_sorted = sorted(cost_changes, key=lambda x: abs(x["max_cost_diff"]), reverse=True)

    for change in cost_changes_sorted:
        old_spec = f"{change['old_memory']:.1f}Gi / {change['old_cpu']:.2f} CPU"
        new_spec = f"{change['new_memory']:.1f}Gi / {change['new_cpu']:.2f} CPU"

        # Add replica info if it changed or has a range
        if change['has_range']:
            old_spec += f" × {change['old_min_replicas']}-{change['old_max_replicas']} replicas"
            new_spec += f" × {change['new_min_replicas']}-{change['new_max_replicas']} replicas"
        elif change['new_min_replicas'] > 1:
            old_spec += f" × {change['old_min_replicas']}"
            new_spec += f" × {change['new_min_replicas']}"

        trend = get_trend_arrow(change["max_cost_diff"])
        impact = format_cost_range(change["min_cost_diff"], change["max_cost_diff"], change["has_range"])

        comment += f"| `{change['resource']}` | `{change['file']}` | {old_spec} | {new_spec} | {trend} **{impact}** |\n"

    comment += "\n</details>\n\n"

    # Recommendations
    if total_max_impact > 0:
        comment += """### 🔍 Recommendations

1. **Validate necessity**: Are these increased resource requests required?
2. **Check actual usage**: Use `kubectl top` to see current utilization
3. **Consider alternatives**: Can you optimize the application instead?
4. **Test in staging**: Verify the new limits are actually needed

"""
    
    comment += "\n---\n\n"
    
    # Add SaaS upsell footer if no API key
    if not api_key or api_key.strip() == "":
        comment += f"""### 📉 Want to reduce false positives?

Connect this repo to Wozz to enable:
- **AI-powered analysis** - Ignore necessary changes (JVM upgrades, scaling events)
- **Historical cost tracking** - See trends over time on your dashboard
- **Team-wide ignore rules** - Centralized configuration for your organization

[**Connect {repo_full_name} to Wozz →**](https://wozz.io/connect?repo={repo_full_name})

---

"""
    else:
        comment += "✅ **Connected to Wozz Cloud** - Enhanced analysis enabled\n\n---\n\n"
    
    comment += '<sub>Powered by <a href="https://wozz.io">Wozz</a> | <a href="https://github.com/WozzHQ/wozz">Open Source</a></sub>\n'
    
    return comment

def post_pr_comment(comment: str, pr_number: int, repo_owner: str, repo_name: str, token: str):
    """Post comment to GitHub PR."""
    url = f"https://api.github.com/repos/{repo_owner}/{repo_name}/issues/{pr_number}/comments"
    
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json"
    }
    
    data = {"body": comment}
    
    response = requests.post(url, headers=headers, json=data)
    
    if response.status_code == 201:
        print("✓ Successfully posted cost analysis to PR")
    else:
        print(f"✗ Failed to post comment: {response.status_code}")
        print(response.text)

def main():
    """Main execution flow."""
    print("🛡️  Wozz Layer 5: Financial Linter")
    print("=" * 50)
    
    # Get environment variables
    github_token = os.getenv("GITHUB_TOKEN")
    cost_threshold = float(os.getenv("COST_THRESHOLD", "50"))
    pr_number = os.getenv("PR_NUMBER")
    repo_owner = os.getenv("REPO_OWNER")
    repo_name = os.getenv("REPO_NAME")
    repo_full_name = os.getenv("REPO_FULL_NAME", f"{repo_owner}/{repo_name}")
    base_sha = os.getenv("BASE_SHA")
    head_sha = os.getenv("HEAD_SHA")
    working_dir = os.getenv("WORKING_DIR", ".")
    api_key = os.getenv("WOZZ_API_KEY", "")
    
    # Validate inputs
    if not all([github_token, pr_number, repo_owner, repo_name, base_sha, head_sha]):
        print("Error: Missing required environment variables")
        sys.exit(1)
    
    try:
        pr_number = int(pr_number)
    except ValueError:
        print("Error: PR_NUMBER must be a number")
        sys.exit(1)
    
    # Change to working directory
    if working_dir != ".":
        os.chdir(working_dir)
    
    print(f"Analyzing PR #{pr_number} in {repo_owner}/{repo_name}")
    print(f"Cost threshold: ${cost_threshold}/year")
    
    if api_key and api_key.strip():
        print("✓ Connected to Wozz Cloud - Enhanced analysis enabled")
    else:
        print("ℹ️  Running in local mode (connect to Wozz for AI analysis)")
    
    print()
    
    # Analyze costs
    cost_changes = analyze_pr_costs(base_sha, head_sha)

    if not cost_changes:
        print("✓ No significant cost changes detected")
        sys.exit(0)

    # Calculate total impact ranges
    total_min_impact = sum(change["min_cost_diff"] for change in cost_changes)
    total_max_impact = sum(change["max_cost_diff"] for change in cost_changes)
    has_any_range = any(change["has_range"] for change in cost_changes)

    impact_str = format_cost_range(total_min_impact, total_max_impact, has_any_range)
    print(f"\n📊 Total annual cost impact: {impact_str}")

    # Use worst case (max) for threshold checks
    if abs(total_max_impact) >= cost_threshold:
        comment = create_pr_comment(cost_changes, cost_threshold, api_key, repo_full_name)
        if comment:
            post_pr_comment(comment, pr_number, repo_owner, repo_name, github_token)
            print(f"\n⚠️  Cost impact exceeds threshold (${cost_threshold}/year)")
            sys.exit(1)  # Exit with error to mark check as failed
    else:
        print(f"✓ Cost impact below threshold (${cost_threshold}/year)")

    sys.exit(0)

if __name__ == "__main__":
    main()
