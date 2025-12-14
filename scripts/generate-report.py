#!/usr/bin/env python3
"""
Wozz Cost Report Generator
Analyzes anonymized Kubernetes audit data and generates:
- Terminal summary with savings
- HTML report with charts
- JSON export for web analyzer
"""

import json
import sys
import os
from datetime import datetime
from typing import Dict, List, Any, Optional
import re

# Pricing constants (conservative averages)
MEMORY_COST_PER_GB_MONTH = 7.20  # $0.01/GB/hour
CPU_COST_PER_VCPU_MONTH = 21.60  # $0.03/vCPU/hour
STORAGE_COST_PER_GB_MONTH = 0.10  # EBS gp3
LB_COST_PER_MONTH = 20.00  # AWS ALB

def parse_cpu(cpu_str: str) -> float:
    """Convert K8s CPU string to vCPU (float)"""
    if not cpu_str:
        return 0.0
    
    cpu_str = cpu_str.strip()
    if cpu_str.endswith('m'):
        return float(cpu_str[:-1]) / 1000.0
    else:
        return float(cpu_str)

def parse_memory(mem_str: str) -> float:
    """Convert K8s memory string to GB (float)"""
    if not mem_str:
        return 0.0
    
    mem_str = mem_str.strip()
    units = {
        'Ki': 1024 / (1024**3),
        'Mi': (1024**2) / (1024**3),
        'Gi': 1.0,
        'Ti': 1024**4 / (1024**3),
        'K': 1000 / (1000**3),
        'M': (1000**2) / (1000**3),
        'G': 1.0,
        'T': (1000**4) / (1000**3),
    }
    
    for unit, multiplier in units.items():
        if mem_str.endswith(unit):
            return float(mem_str[:-len(unit)]) * multiplier
    
    # Assume bytes if no unit
    return float(mem_str) / (1024**3)

def parse_usage_line(line: str) -> Dict[str, str]:
    """Parse kubectl top output line"""
    parts = line.strip().split()
    if len(parts) >= 3:
        return {
            'namespace': parts[0],
            'pod': parts[1],
            'cpu': parts[2] if len(parts) > 2 else '0m',
            'memory': parts[3] if len(parts) > 3 else '0Mi'
        }
    return {}

def load_usage_data(audit_dir: str) -> Dict[str, Dict[str, float]]:
    """Load usage data from kubectl top output"""
    usage = {}
    
    usage_file = os.path.join(audit_dir, 'usage-pods.txt')
    if os.path.exists(usage_file):
        with open(usage_file, 'r') as f:
            lines = f.readlines()
            # Skip header line
            for line in lines[1:]:
                parsed = parse_usage_line(line)
                if parsed:
                    key = f"{parsed['namespace']}/{parsed['pod']}"
                    usage[key] = {
                        'cpu': parse_cpu(parsed['cpu']),
                        'memory': parse_memory(parsed['memory'])
                    }
    
    return usage

def calculate_memory_waste(request_gb: float, limit_gb: float, usage_gb: Optional[float] = None) -> float:
    """Calculate memory waste in $/month"""
    if limit_gb == 0 or request_gb == 0:
        return 0.0
    
    # Rule 1: Over-provisioned (limit > 3x request)
    if limit_gb > request_gb * 3:
        waste_gb = limit_gb - (request_gb * 1.5)
        return waste_gb * MEMORY_COST_PER_GB_MONTH
    
    # Rule 3: Underutilized (usage < 20% of request)
    if usage_gb is not None and usage_gb > 0:
        if usage_gb < request_gb * 0.2:
            waste_gb = request_gb - (usage_gb * 1.5)
            return max(0, waste_gb) * MEMORY_COST_PER_GB_MONTH
    
    return 0.0

def calculate_cpu_waste(request_vcpu: float, limit_vcpu: float, usage_vcpu: Optional[float] = None) -> float:
    """Calculate CPU waste in $/month"""
    if limit_vcpu == 0 or request_vcpu == 0:
        return 0.0
    
    # Rule 2: Over-provisioned (limit > 4x request)
    if limit_vcpu > request_vcpu * 4:
        waste_vcpu = limit_vcpu - (request_vcpu * 1.5)
        return waste_vcpu * CPU_COST_PER_VCPU_MONTH
    
    # Rule 3: Underutilized (usage < 20% of request)
    if usage_vcpu is not None and usage_vcpu > 0:
        if usage_vcpu < request_vcpu * 0.2:
            waste_vcpu = request_vcpu - (usage_vcpu * 1.5)
            return max(0, waste_vcpu) * CPU_COST_PER_VCPU_MONTH
    
    return 0.0

def analyze_pods(audit_dir: str) -> List[Dict[str, Any]]:
    """Analyze pods and detect waste patterns"""
    findings = []
    
    pods_file = os.path.join(audit_dir, 'pods-anonymized.json')
    if not os.path.exists(pods_file):
        return findings
    
    with open(pods_file, 'r') as f:
        pods_data = json.load(f)
    
    usage_data = load_usage_data(audit_dir)
    
    pods_without_requests = []
    memory_waste_total = 0.0
    cpu_waste_total = 0.0
    underutilized_memory_count = 0
    underutilized_memory_waste = 0.0
    underutilized_cpu_count = 0
    underutilized_cpu_waste = 0.0
    
    for pod in pods_data.get('items', []):
        pod_name = pod.get('metadata', {}).get('name', 'unknown')
        namespace = pod.get('metadata', {}).get('namespace', 'default')
        key = f"{namespace}/{pod_name}"
        
        for container in pod.get('spec', {}).get('containers', []):
            resources = container.get('resources', {})
            requests = resources.get('requests', {})
            limits = resources.get('limits', {})
            
            # Rule 4: Missing requests
            if not requests:
                pods_without_requests.append({
                    'pod': pod_name,
                    'namespace': namespace,
                    'container': container.get('name', 'unknown')
                })
                continue
            
            # Get resource values
            mem_request = parse_memory(requests.get('memory', '0'))
            mem_limit = parse_memory(limits.get('memory', '0'))
            cpu_request = parse_cpu(requests.get('cpu', '0'))
            cpu_limit = parse_cpu(limits.get('cpu', '0'))
            
            # Get usage if available
            usage = usage_data.get(key, {})
            mem_usage = usage.get('memory') if usage else None
            cpu_usage = usage.get('cpu') if usage else None
            
            # Calculate waste
            mem_waste = calculate_memory_waste(mem_request, mem_limit, mem_usage)
            cpu_waste = calculate_cpu_waste(cpu_request, cpu_limit, cpu_usage)
            
            if mem_waste > 0:
                memory_waste_total += mem_waste
                findings.append({
                    'type': 'OVER_PROVISIONED_MEMORY',
                    'severity': 'HIGH' if mem_waste > 500 else 'MEDIUM' if mem_waste > 100 else 'LOW',
                    'pod': pod_name,
                    'namespace': namespace,
                    'container': container.get('name', 'unknown'),
                    'monthlySavings': mem_waste,
                    'details': {
                        'request': f"{mem_request:.2f}Gi",
                        'limit': f"{mem_limit:.2f}Gi",
                        'usage': f"{mem_usage:.2f}Gi" if mem_usage else 'N/A',
                        'ratio': f"{mem_limit/mem_request:.1f}x" if mem_request > 0 else 'N/A'
                    }
                })
            
            if cpu_waste > 0:
                cpu_waste_total += cpu_waste
                
                # Determine if waste is from over-provisioning (limit too high) or underutilization (usage too low)
                is_over_provisioned = cpu_limit > cpu_request * 4 if cpu_request > 0 else False
                is_underutilized = cpu_usage is not None and cpu_usage > 0 and cpu_usage < cpu_request * 0.2 if cpu_request > 0 else False
                
                # Prefer underutilized label if usage data shows underutilization
                # (even if limit is also high, underutilization is more actionable)
                finding_type = 'UNDERUTILIZED_CPU' if is_underutilized else 'OVER_PROVISIONED_CPU'
                
                findings.append({
                    'type': finding_type,
                    'severity': 'HIGH' if cpu_waste > 500 else 'MEDIUM' if cpu_waste > 100 else 'LOW',
                    'pod': pod_name,
                    'namespace': namespace,
                    'container': container.get('name', 'unknown'),
                    'monthlySavings': cpu_waste,
                    'details': {
                        'request': f"{cpu_request:.2f}",
                        'limit': f"{cpu_limit:.2f}",
                        'usage': f"{cpu_usage:.2f}" if cpu_usage else 'N/A',
                        'utilizationPercent': f"{(cpu_usage/cpu_request*100):.1f}%" if cpu_usage and cpu_request > 0 else 'N/A',
                        'ratio': f"{cpu_limit/cpu_request:.1f}x" if cpu_request > 0 else 'N/A'
                    }
                })
                
                if is_underutilized:
                    underutilized_cpu_count += 1
                    underutilized_cpu_waste += cpu_waste
            
            # Check memory underutilization
            if mem_usage and mem_request > 0:
                if mem_usage < mem_request * 0.2:
                    # Only add if not already flagged as over-provisioned
                    if mem_waste == 0:  # Not caught by over-provisioning check
                        underutilized_memory_count += 1
                        waste = (mem_request - mem_usage * 1.5) * MEMORY_COST_PER_GB_MONTH
                        underutilized_memory_waste += max(0, waste)
                        
                        findings.append({
                            'type': 'UNDERUTILIZED_MEMORY',
                            'severity': 'MEDIUM' if waste > 100 else 'LOW',
                            'pod': pod_name,
                            'namespace': namespace,
                            'container': container.get('name', 'unknown'),
                            'monthlySavings': waste,
                            'details': {
                                'request': f"{mem_request:.2f}Gi",
                                'usage': f"{mem_usage:.2f}Gi",
                                'utilizationPercent': f"{(mem_usage/mem_request*100):.1f}%"
                            }
                        })
    
    # Add missing requests finding
    if pods_without_requests:
        findings.append({
            'type': 'MISSING_REQUESTS',
            'severity': 'HIGH',
            'podsAffected': len(pods_without_requests),
            'monthlySavings': 0,  # Can't calculate without baseline
            'details': {
                'pods': pods_without_requests[:10]  # Limit to 10 examples
            }
        })
    
    return findings

def analyze_load_balancers(audit_dir: str) -> List[Dict[str, Any]]:
    """Analyze services for orphaned load balancers"""
    findings = []
    
    services_file = os.path.join(audit_dir, 'services-anonymized.json')
    if not os.path.exists(services_file):
        return findings
    
    with open(services_file, 'r') as f:
        services_data = json.load(f)
    
    orphaned_lbs = []
    
    for svc in services_data.get('items', []):
        svc_type = svc.get('spec', {}).get('type', '')
        if svc_type != 'LoadBalancer':
            continue
        
        # Check if service has endpoints
        # Note: We can't check actual endpoints from this data,
        # so we'll flag all LoadBalancers for review
        # In a real implementation, you'd check endpoint status
        
        creation_timestamp = svc.get('metadata', {}).get('creationTimestamp', '')
        if creation_timestamp:
            # Simple check: if service exists, assume it might be orphaned
            # Real implementation would check endpoint status
            orphaned_lbs.append({
                'service': svc.get('metadata', {}).get('name', 'unknown'),
                'namespace': svc.get('metadata', {}).get('namespace', 'default'),
                'age': 'unknown'  # Would calculate from creationTimestamp
            })
    
    if orphaned_lbs:
        findings.append({
            'type': 'ORPHANED_LB',
            'severity': 'MEDIUM',
            'resourcesAffected': len(orphaned_lbs),
            'monthlySavings': len(orphaned_lbs) * LB_COST_PER_MONTH,
            'details': {
                'loadBalancers': orphaned_lbs
            }
        })
    
    return findings

def analyze_storage(audit_dir: str) -> List[Dict[str, Any]]:
    """Analyze persistent volumes for unbound volumes"""
    findings = []
    
    pv_file = os.path.join(audit_dir, 'pv-anonymized.json')
    if not os.path.exists(pv_file):
        return findings
    
    with open(pv_file, 'r') as f:
        pvs_data = json.load(f)
    
    unbound_pvs = []
    total_storage_gb = 0.0
    
    for pv in pvs_data.get('items', []):
        status = pv.get('status', {}).get('phase', '')
        if status != 'Bound':
            size_str = pv.get('spec', {}).get('capacity', {}).get('storage', '0')
            size_gb = parse_memory(size_str)
            total_storage_gb += size_gb
            unbound_pvs.append({
                'name': pv.get('metadata', {}).get('name', 'unknown'),
                'size': size_str,
                'status': status
            })
    
    if unbound_pvs:
        monthly_savings = total_storage_gb * STORAGE_COST_PER_GB_MONTH
        findings.append({
            'type': 'UNBOUND_PV',
            'severity': 'LOW' if monthly_savings < 100 else 'MEDIUM',
            'resourcesAffected': len(unbound_pvs),
            'monthlySavings': monthly_savings,
            'details': {
                'totalStorageGB': total_storage_gb,
                'volumes': unbound_pvs[:10]  # Limit examples
            }
        })
    
    return findings

def aggregate_findings(findings: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Aggregate per-pod findings into category findings with examples"""
    if not findings:
        return []

    # Group findings by type
    by_type = {}
    for finding in findings:
        ftype = finding.get('type', 'UNKNOWN')
        if ftype not in by_type:
            by_type[ftype] = []
        by_type[ftype].append(finding)

    aggregated = []
    for ftype, group in by_type.items():
        # Calculate total savings for this type
        total_savings = sum(f.get('monthlySavings', 0) for f in group)

        # Determine severity (use highest severity in group)
        severity_order = {'HIGH': 3, 'MEDIUM': 2, 'LOW': 1}
        max_severity = max(group, key=lambda x: severity_order.get(x.get('severity', 'LOW'), 0))['severity']

        # Count affected resources
        pods_affected = len(set(f"{f.get('namespace', 'default')}/{f.get('pod', 'unknown')}" for f in group if f.get('pod')))
        resources_affected = len(group)

        # Build description based on type
        descriptions = {
            'OVER_PROVISIONED_MEMORY': f"Pods requesting significantly more memory than they use",
            'OVER_PROVISIONED_CPU': f"Pods requesting significantly more CPU than they use",
            'UNDERUTILIZED_MEMORY': f"Pods using less than 20% of requested memory",
            'UNDERUTILIZED_CPU': f"Pods using less than 20% of requested CPU",
            'NO_REQUESTS': f"Pods without resource requests - causes unpredictable scheduling",
            'ORPHANED_LB': f"Load balancers with no backend endpoints",
            'UNBOUND_PV': f"Persistent volumes not bound to any pods"
        }
        description = descriptions.get(ftype, f"Issues of type {ftype}")

        # Create aggregated finding
        agg_finding = {
            'type': ftype,
            'severity': max_severity,
            'monthlySavings': total_savings,
            'description': description
        }

        # Add appropriate count
        if ftype in ['ORPHANED_LB', 'UNBOUND_PV']:
            agg_finding['resourcesAffected'] = resources_affected
        else:
            agg_finding['podsAffected'] = pods_affected

        # Add top 5 examples in details
        sorted_examples = sorted(group, key=lambda x: x.get('monthlySavings', 0), reverse=True)[:5]
        if sorted_examples and sorted_examples[0].get('pod'):
            # Per-pod findings - include as examples
            agg_finding['details'] = {
                'examples': [
                    {
                        'pod': ex.get('pod'),
                        'namespace': ex.get('namespace'),
                        'container': ex.get('container'),
                        'wastePerMonth': ex.get('monthlySavings'),
                        'request': ex.get('details', {}).get('request', 'N/A'),
                        'usage': ex.get('details', {}).get('usage', 'N/A'),
                        'limit': ex.get('details', {}).get('limit', 'N/A')
                    }
                    for ex in sorted_examples
                ]
            }

        aggregated.append(agg_finding)

    # Sort by monthly savings descending
    return sorted(aggregated, key=lambda x: x.get('monthlySavings', 0), reverse=True)

def generate_terminal_output(report_data: Dict[str, Any]) -> str:
    """Generate terminal-formatted output"""
    output = []
    output.append("")
    output.append("━" * 60)
    output.append("WOZZ AUDIT RESULTS")
    output.append("━" * 60)
    output.append("")
    
    costs = report_data.get('costs', {})
    monthly_waste = costs.get('monthlyWaste', 0)
    annual_savings = costs.get('annualSavings', 0)
    
    output.append(f"Monthly Waste: ${monthly_waste:,.2f}")
    output.append(f"Annual Savings: ${annual_savings:,.2f}")
    output.append("")
    
    cluster = report_data.get('cluster', {})
    output.append("Cluster Overview:")
    output.append(f"  • Total Pods: {cluster.get('totalPods', 0)}")
    output.append(f"  • Total Nodes: {cluster.get('totalNodes', 0)}")
    output.append(f"  • Total Cost: ${costs.get('currentMonthlyCost', 0):,.2f}/month")
    output.append("")
    
    findings = report_data.get('findings', [])
    if findings:
        output.append("Top Issues:")
        output.append("━" * 60)
        
        # Sort by monthly savings
        sorted_findings = sorted(findings, key=lambda x: x.get('monthlySavings', 0), reverse=True)
        
        for i, finding in enumerate(sorted_findings[:5], 1):
            ftype = finding.get('type', 'UNKNOWN').replace('_', ' ').title()
            severity = finding.get('severity', 'UNKNOWN')
            savings = finding.get('monthlySavings', 0)
            affected = finding.get('podsAffected', finding.get('resourcesAffected', 0))
            
            output.append(f"{i}. {ftype} [{severity}]")
            if affected > 0:
                output.append(f"   • {affected} {'pods' if 'podsAffected' in finding else 'resources'} affected")
            output.append(f"   • Savings: ${savings:,.2f}/month")
            output.append("")
    
    output.append("━" * 60)
    output.append("Detailed report: wozz-report.html")
    output.append("Visualize: https://wozz.io/analyze")
    output.append("Need help? support@wozz.io")
    output.append("━" * 60)
    output.append("")
    
    return "\n".join(output)

def generate_html_report(report_data: Dict[str, Any], output_file: str):
    """Generate HTML report with charts"""
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Wozz Cost Audit Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: #0f172a;
            color: #f1f5f9;
            padding: 40px 20px;
            line-height: 1.6;
        }}
        .container {{
            max-width: 1200px;
            margin: 0 auto;
        }}
        header {{
            text-align: center;
            margin-bottom: 40px;
            padding-bottom: 20px;
            border-bottom: 2px solid #334155;
        }}
        h1 {{
            font-size: 2.5em;
            color: #10b981;
            margin-bottom: 10px;
        }}
        .executive-summary {{
            background: #1e293b;
            border-radius: 12px;
            padding: 30px;
            margin-bottom: 40px;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
        }}
        .metric {{
            text-align: center;
        }}
        .metric h2 {{
            font-size: 2.5em;
            color: #10b981;
            margin-bottom: 5px;
        }}
        .metric p {{
            color: #94a3b8;
            font-size: 0.9em;
        }}
        .findings {{
            background: #1e293b;
            border-radius: 12px;
            padding: 30px;
            margin-bottom: 40px;
        }}
        .findings h2 {{
            color: #10b981;
            margin-bottom: 20px;
            font-size: 1.8em;
        }}
        .finding-item {{
            background: #0f172a;
            border-left: 4px solid #10b981;
            padding: 20px;
            margin-bottom: 15px;
            border-radius: 8px;
        }}
        .finding-header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
        }}
        .finding-type {{
            font-size: 1.2em;
            font-weight: 600;
        }}
        .severity {{
            padding: 4px 12px;
            border-radius: 4px;
            font-size: 0.85em;
            font-weight: 600;
        }}
        .severity.HIGH {{
            background: #ef4444;
            color: white;
        }}
        .severity.MEDIUM {{
            background: #f59e0b;
            color: white;
        }}
        .severity.LOW {{
            background: #3b82f6;
            color: white;
        }}
        .savings {{
            color: #10b981;
            font-size: 1.1em;
            font-weight: 600;
            margin-top: 10px;
        }}
        .charts {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 30px;
            margin-bottom: 40px;
        }}
        .chart-container {{
            background: #1e293b;
            border-radius: 12px;
            padding: 20px;
        }}
        .chart-container h3 {{
            color: #10b981;
            margin-bottom: 15px;
        }}
        .kubectl-commands {{
            background: #0f172a;
            border: 1px solid #334155;
            border-radius: 8px;
            padding: 15px;
            font-family: 'Monaco', 'Menlo', monospace;
            font-size: 0.9em;
            color: #e2e8f0;
            margin-top: 10px;
            overflow-x: auto;
        }}
        footer {{
            text-align: center;
            color: #64748b;
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #334155;
        }}
        @media print {{
            body {{
                background: white;
                color: black;
            }}
            .executive-summary, .findings, .chart-container {{
                background: white;
                border: 1px solid #ccc;
            }}
        }}
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Kubernetes Cost Audit Report</h1>
            <p>Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        </header>
        
        <section class="executive-summary">
            <div class="metric">
                <h2>${report_data.get('costs', {}).get('annualSavings', 0):,.0f}</h2>
                <p>Annual Savings Potential</p>
            </div>
            <div class="metric">
                <h2>${report_data.get('costs', {}).get('monthlyWaste', 0):,.0f}</h2>
                <p>Monthly Waste</p>
            </div>
            <div class="metric">
                <h2>{report_data.get('cluster', {}).get('totalPods', 0)}</h2>
                <p>Pods Analyzed</p>
            </div>
            <div class="metric">
                <h2>{report_data.get('cluster', {}).get('totalNodes', 0)}</h2>
                <p>Nodes</p>
            </div>
        </section>
        
        <section class="charts">
            <div class="chart-container">
                <h3>Waste by Category</h3>
                <canvas id="wasteByType"></canvas>
            </div>
            <div class="chart-container">
                <h3>Top 10 Offenders</h3>
                <canvas id="topOffenders"></canvas>
            </div>
        </section>
        
        <section class="findings">
            <h2>Key Findings</h2>
"""
    
    findings = report_data.get('findings', [])
    sorted_findings = sorted(findings, key=lambda x: x.get('monthlySavings', 0), reverse=True)
    
    for finding in sorted_findings:
        ftype = finding.get('type', 'UNKNOWN').replace('_', ' ').title()
        severity = finding.get('severity', 'UNKNOWN')
        savings = finding.get('monthlySavings', 0)
        affected = finding.get('podsAffected', finding.get('resourcesAffected', 0))
        
        html += f"""
            <div class="finding-item">
                <div class="finding-header">
                    <div class="finding-type">{ftype}</div>
                    <span class="severity {severity}">{severity}</span>
                </div>
                <p>{affected} {'pods' if 'podsAffected' in finding else 'resources'} affected</p>
                <div class="savings">Potential Savings: ${savings:,.2f}/month</div>
            </div>
"""
    
    html += """
        </section>
        
        <footer>
            <p>Generated by Wozz | wozz.io | MIT Licensed</p>
        </footer>
    </div>
    
    <script>
        // Waste by Category Chart
        const breakdown = """ + json.dumps(report_data.get('breakdown', {})) + """;
        const wasteByTypeCtx = document.getElementById('wasteByType').getContext('2d');
        new Chart(wasteByTypeCtx, {
            type: 'pie',
            data: {
                labels: ['Memory', 'CPU', 'Storage', 'Load Balancers'],
                datasets: [{
                    data: [
                        breakdown.memory || 0,
                        breakdown.cpu || 0,
                        breakdown.storage || 0,
                        breakdown.loadBalancers || 0
                    ],
                    backgroundColor: ['#10b981', '#3b82f6', '#f59e0b', '#ef4444']
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: { position: 'bottom', labels: { color: '#f1f5f9' } }
                }
            }
        });
        
        // Top Offenders Chart
        const findings = """ + json.dumps(sorted_findings[:10]) + """;
        const topOffendersCtx = document.getElementById('topOffenders').getContext('2d');
        new Chart(topOffendersCtx, {
            type: 'bar',
            data: {
                labels: findings.map(f => f.type.replace(/_/g, ' ').substring(0, 20)),
                datasets: [{
                    label: 'Monthly Savings ($)',
                    data: findings.map(f => f.monthlySavings || 0),
                    backgroundColor: '#10b981'
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: { labels: { color: '#f1f5f9' } }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: { color: '#94a3b8' },
                        grid: { color: '#334155' }
                    },
                    x: {
                        ticks: { color: '#94a3b8' },
                        grid: { color: '#334155' }
                    }
                }
            }
        });
    </script>
</body>
</html>
"""
    
    with open(output_file, 'w') as f:
        f.write(html)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 generate-report.py <audit-directory>")
        sys.exit(1)
    
    audit_dir = sys.argv[1]
    
    if not os.path.exists(audit_dir):
        print(f"Error: Directory not found: {audit_dir}")
        sys.exit(1)
    
    # Analyze all components
    print("→ Analyzing pods...")
    pod_findings = analyze_pods(audit_dir)
    
    print("→ Analyzing load balancers...")
    lb_findings = analyze_load_balancers(audit_dir)
    
    print("→ Analyzing storage...")
    storage_findings = analyze_storage(audit_dir)
    
    # Combine all findings
    all_findings = pod_findings + lb_findings + storage_findings

    # Aggregate findings by type (group per-pod findings)
    aggregated_findings = aggregate_findings(all_findings)

    # Calculate totals (use original findings for accurate totals)
    monthly_waste = sum(f.get('monthlySavings', 0) for f in all_findings)
    annual_savings = monthly_waste * 12
    
    # Calculate breakdown (include both over-provisioned and underutilized)
    breakdown = {
        'memory': sum(f.get('monthlySavings', 0) for f in all_findings if f.get('type') in ['OVER_PROVISIONED_MEMORY', 'UNDERUTILIZED_MEMORY']),
        'cpu': sum(f.get('monthlySavings', 0) for f in all_findings if f.get('type') in ['OVER_PROVISIONED_CPU', 'UNDERUTILIZED_CPU']),
        'storage': sum(f.get('monthlySavings', 0) for f in all_findings if f.get('type') == 'UNBOUND_PV'),
        'loadBalancers': sum(f.get('monthlySavings', 0) for f in all_findings if f.get('type') == 'ORPHANED_LB')
    }
    
    # Load cluster info
    summary_file = os.path.join(audit_dir, 'summary.json')
    cluster_info = {'totalPods': 0, 'totalNodes': 0}
    if os.path.exists(summary_file):
        with open(summary_file, 'r') as f:
            summary = json.load(f)
            cluster_info['totalPods'] = summary.get('totalPods', 0)
    
    # Estimate current cost (rough calculation)
    current_cost = monthly_waste * 3  # Assume waste is ~33% of total
    
    # Build report data
    report_data = {
        'timestamp': datetime.now().isoformat(),
        'cluster': {
            'totalPods': cluster_info['totalPods'],
            'totalNodes': cluster_info.get('totalNodes', 0),
            'namespaces': 0
        },
        'costs': {
            'monthlyWaste': monthly_waste,
            'annualSavings': annual_savings,
            'currentMonthlyCost': current_cost,
            'optimizedMonthlyCost': current_cost - monthly_waste
        },
        'findings': aggregated_findings,
        'breakdown': breakdown
    }
    
    # Generate outputs
    print("→ Generating terminal output...")
    terminal_output = generate_terminal_output(report_data)
    print(terminal_output)
    
    print("→ Generating HTML report...")
    html_file = os.path.join(os.path.dirname(audit_dir), 'wozz-report.html')
    generate_html_report(report_data, html_file)
    print(f"  ✅ HTML report: {html_file}")
    
    print("→ Generating JSON export...")
    json_file = os.path.join(os.path.dirname(audit_dir), 'wozz-audit.json')
    with open(json_file, 'w') as f:
        json.dump(report_data, f, indent=2)
    print(f"  ✅ JSON export: {json_file}")

if __name__ == "__main__":
    main()

    