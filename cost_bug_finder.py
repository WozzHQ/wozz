#!/usr/bin/env python3
"""
Cloud Cost Bug Finder - A CLI tool to detect potential N+1 cost bugs
in Python code by finding get_object/head_object calls inside loops.
"""

import abc
import argparse
import ast
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Finding:
    """Represents a cost bug finding."""
    line_number: int
    rule_id: str
    description: str
    estimated_cost: float
    severity: str


class BaseRule(abc.ABC):
    """Abstract base class for cost bug detection rules."""
    
    @abc.abstractmethod
    def evaluate(self, code_ast: ast.AST, context: dict) -> list[Finding]:
        """
        Evaluate the AST against this rule and return a list of findings.
        
        Args:
            code_ast: The parsed AST of the code
            context: Dictionary containing cost and configuration data
            
        Returns:
            List of Finding objects representing detected issues
        """
        pass


class NPlusOneAPICallRule(BaseRule):
    """Rule to detect N+1 API calls (get_object/head_object inside loops)."""
    
    def evaluate(self, code_ast: ast.AST, context: dict) -> list[Finding]:
        """
        Find get_object or head_object calls inside For or While loops.
        
        Args:
            code_ast: The parsed AST of the code
            context: Dictionary containing AWS cost information
            
        Returns:
            List of Finding objects for detected N+1 API call bugs
        """
        class Visitor(ast.NodeVisitor):
            """Nested AST visitor to find N+1 API call patterns."""
            
            def __init__(self, ctx: dict):
                self.context = ctx
                self.loop_depth = 0
                self.findings: list[Finding] = []
            
            def visit_For(self, node: ast.For):
                """Visit a For loop node."""
                self.loop_depth += 1
                self.generic_visit(node)
                self.loop_depth -= 1
            
            def visit_While(self, node: ast.While):
                """Visit a While loop node."""
                self.loop_depth += 1
                self.generic_visit(node)
                self.loop_depth -= 1
            
            def visit_Call(self, node: ast.Call):
                """Visit a function call node."""
                # Only check calls when we're inside a loop
                if self.loop_depth > 0:
                    # Check if this is a method call (attribute access)
                    if isinstance(node.func, ast.Attribute):
                        method_name = node.func.attr
                        if method_name in ('get_object', 'head_object'):
                            # Calculate estimated cost from context
                            api_cost = self.context.get("aws.s3.get_object.api_cost", 0.0004)
                            data_transfer_gb_guess = 0.01  # 10MB
                            data_cost_per_gb = self.context.get("aws.pricing.data_transfer_out", 0.09)
                            estimated_cost = api_cost + (data_cost_per_gb * data_transfer_gb_guess)
                            
                            finding = Finding(
                                line_number=node.lineno,
                                rule_id="W001",
                                description="N+1 API call in loop",
                                estimated_cost=estimated_cost,
                                severity="HIGH"
                            )
                            self.findings.append(finding)
                
                # Continue visiting child nodes
                self.generic_visit(node)
        
        visitor = Visitor(context)
        visitor.visit(code_ast)
        return visitor.findings


def main():
    """Main entry point for the CLI tool."""
    parser = argparse.ArgumentParser(
        description='Find cloud cost bugs in Python files (get_object/head_object calls inside loops)'
    )
    parser.add_argument(
        'files',
        nargs='+',
        help='Python file paths to analyze'
    )
    
    args = parser.parse_args()
    
    # Default context with AWS cost information
    DEFAULT_CONTEXT = {
        "aws.s3.get_object.api_cost": 0.0004,
        "aws.pricing.data_transfer_out": 0.09
    }
    
    # Initialize all rules
    rules = [NPlusOneAPICallRule()]
    
    all_findings: list[Finding] = []
    
    # Process each file
    for file_path in args.files:
        path = Path(file_path)
        
        try:
            if not path.exists():
                raise FileNotFoundError(f"File not found: {file_path}")
            
            if not path.is_file():
                print(f"Error: Not a file: {file_path}", file=sys.stderr)
                continue
            
            with open(path, 'r', encoding='utf-8') as f:
                source_code = f.read()
            
            ast_tree = ast.parse(source_code, filename=file_path)
            
            # Run all rules on the AST
            for rule in rules:
                all_findings.extend(rule.evaluate(ast_tree, DEFAULT_CONTEXT))
        
        except FileNotFoundError as e:
            print(f"Error: {e}", file=sys.stderr)
            continue
        except SyntaxError as e:
            print(f"Error parsing {file_path}: {e}", file=sys.stderr)
            continue
        except Exception as e:
            print(f"Error reading file {file_path}: {e}", file=sys.stderr)
            continue
    
    # Print all findings as a structured list
    if all_findings:
        print("\n=== Cost Bug Findings ===\n")
        for finding in all_findings:
            print(
                f"[{finding.rule_id}] Line {finding.line_number}: {finding.description}\n"
                f"  Severity: {finding.severity}\n"
                f"  Estimated Cost: ${finding.estimated_cost:.6f}\n"
            )
        sys.exit(1)
    else:
        print("No cost bugs found.")
        sys.exit(0)


if __name__ == '__main__':
    main()
