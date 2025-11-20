#!/usr/bin/env python3
"""
Wozz Audit Analyzer
Analyzes audit data to calculate waste and generate recommendations
"""

import json
import sys
import re
from typing import Dict, List, Tuple
from dataclasses import dataclass

@dataclass
class ResourceUsage:
    cpu_request: float
    cpu_limit: float
    cpu_usage: float
    memory_request: float  # in bytes
    memory_limit: float
    memory_usage: float

def parse_cpu(cpu_str: str) -> float:
    """Convert K8s CPU string to millicores"""
    if not cpu_str:
        return 0.0
    
    if cpu_str.endswith('m'):
        return float(cpu_str[:-1])
    else:
        return float(cpu_str) * 1000

def parse_memory(mem_str: str) -> float:
    """Convert K8s memory string to bytes"""
    if not mem_str:
        return 0.0
    
    units = {
        'Ki': 1024,
        'Mi': 1024**2,
        'Gi': 1024**3,
        'Ti': 1024**4,
        'K': 1000,
        'M': 1000**2,
        'G': 1000**3,
        'T': 1000**4,
    }
    
    for unit, multiplier in units.items():
        if mem_str.endswith(unit):
            return float(mem_str[:-len(unit)]) * multiplier
    
    return float(mem_str)

def analyze_audit(audit_dir: str) -> Dict:
    """Analyze audit data and calculate waste"""
    
    # Load pod data
    try:
        with open(f"{audit_dir}/pods-anonymized.json") as f:
            pods_data = json.load(f)
    except FileNotFoundError:
        print("❌ Error: pods-anonymized.json not found")
        sys.exit(1)
    
    findings = {
        'total_pods': 0,
        'total_waste_monthly': 0,
        'recommendations': [],
        'quick_wins': []
    }
    
    # Analyze each pod
    for pod in pods_data.get('items', []):
        findings['total_pods'] += 1
        
        for container in pod.get('spec', {}).get('containers', []):
            resources = container.get('resources', {})
            
            # Check for missing requests
            if not resources.get('requests'):
                findings['recommendations'].append({
                    'type': 'missing_requests',
                    'severity': 'high',
                    'pod': pod.get('metadata', {}).get('name'),
                    'message': 'No resource requests defined - scheduling inefficiency',
                    'estimated_savings': 0
                })
            
            # Check for over-provisioning
            requests = resources.get('requests', {})
            limits = resources.get('limits', {})
            
            if limits.get('memory') and requests.get('memory'):
                limit_bytes = parse_memory(limits['memory'])
                request_bytes = parse_memory(requests['memory'])
                
                if limit_bytes > request_bytes * 4:
                    # Limit is 4x request - likely over-provisioned
                    waste_bytes = (limit_bytes - request_bytes * 1.5)
                    waste_monthly = (waste_bytes / 1024**3) * 10  # Rough $ estimate
                    
                    findings['total_waste_monthly'] += waste_monthly
                    findings['quick_wins'].append({
                        'type': 'over_provisioned_memory',
                        'severity': 'medium',
                        'current_limit': limits['memory'],
                        'recommended_limit': f"{int(request_bytes * 1.5 / 1024**2)}Mi",
                        'estimated_savings': waste_monthly
                    })
    
    return findings

def generate_report(findings: Dict) -> str:
    """Generate human-readable report"""
    
    report = []
    report.append("=" * 60)
    report.append("WOZZ AUDIT ANALYSIS REPORT")
    report.append("=" * 60)
    report.append("")
    report.append(f"Total Pods Analyzed: {findings['total_pods']}")
    report.append(f"Estimated Monthly Waste: ${findings['total_waste_monthly']:.2f}")
    report.append("")
    
    if findings['quick_wins']:
        report.append("QUICK WINS (High Impact, Low Effort):")
        report.append("-" * 60)
        for i, win in enumerate(findings['quick_wins'][:5], 1):
            report.append(f"{i}. {win['type'].replace('_', ' ').title()}")
            report.append(f"   Savings: ${win['estimated_savings']:.2f}/month")
            report.append("")
    
    report.append("=" * 60)
    
    return "\n".join(report)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 analyze-audit.py <audit-directory>")
        sys.exit(1)
    
    audit_dir = sys.argv[1]
    findings = analyze_audit(audit_dir)
    print(generate_report(findings))


