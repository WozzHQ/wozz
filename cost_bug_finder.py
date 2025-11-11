#!/usr/bin/env python3
"""
Cloud Cost Bug Finder - A CLI tool to detect potential N+1 cost bugs
in Python code by finding get_object/head_object calls inside loops.
"""

import argparse
import ast
import sys
from pathlib import Path
from typing import List


class CostBugFinder(ast.NodeVisitor):
    """AST visitor that finds get_object/head_object calls inside loops."""
    
    def __init__(self, file_path: str):
        self.file_path = file_path
        self.loop_depth = 0
        self.bugs_found = []
    
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
                    self.bugs_found.append({
                        'line': node.lineno,
                        'method': method_name
                    })
        
        # Continue visiting child nodes
        self.generic_visit(node)


def analyze_file(file_path: str) -> List[dict]:
    """Analyze a single Python file for cost bugs."""
    path = Path(file_path)
    
    if not path.exists():
        print(f"Error: File not found: {file_path}", file=sys.stderr)
        return []
    
    if not path.is_file():
        print(f"Error: Not a file: {file_path}", file=sys.stderr)
        return []
    
    try:
        with open(path, 'r', encoding='utf-8') as f:
            source_code = f.read()
    except Exception as e:
        print(f"Error reading file {file_path}: {e}", file=sys.stderr)
        return []
    
    try:
        tree = ast.parse(source_code, filename=file_path)
    except SyntaxError as e:
        print(f"Error parsing {file_path}: {e}", file=sys.stderr)
        return []
    
    finder = CostBugFinder(file_path)
    finder.visit(tree)
    
    return finder.bugs_found


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
    
    total_bugs = 0
    
    for file_path in args.files:
        bugs = analyze_file(file_path)
        
        for bug in bugs:
            print(
                f"[COST-001] {file_path}:{bug['line']} - "
                f"Found a potential N+1 cost bug: '{bug['method']}' call inside a loop."
            )
            total_bugs += 1
    
    if total_bugs == 0:
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()

