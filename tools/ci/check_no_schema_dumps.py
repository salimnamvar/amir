#!/usr/bin/env python3
"""
CI Check: No schema field dumps in markdown
This script detects if markdown files contain embedded YAML schema structures.
"""

import sys
import re
from pathlib import Path


def check_file(filepath: Path) -> tuple[bool, str]:
    """Check a single file for schema dumps."""
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    violations = []
    previous_line_had_properties = False
    previous_property_indent = 0
    
    for i, line in enumerate(lines, 1):
        # Track if previous line had properties: with indented type: field
        if re.match(r'^\s+properties:', line):
            previous_line_had_properties = True
            # Get the indent of the properties line
            previous_property_indent = len(line) - len(line.lstrip())
        
        # Check for schema field dumps (type: adjacent to properties:)
        if re.match(r'^\s{2,}type:\s', line) and previous_line_had_properties:
            # Only flag if it looks like structural schema (has required:, enum:, etc.)
            if i < len(lines) and re.match(r'^\s{2,}properties:', lines[i]):
                violations.append(f"line {i}: embedded schema structure detected")
        
        # Reset for next check
        if not line.strip():
            previous_line_had_properties = False
    
    return len(violations) == 0, violations


def main():
    dirs_to_check = ['docs/specification', 'docs/story']
    
    all_passed = True
    for check_dir in dirs_to_check:
        dir_path = Path(check_dir)
        if not dir_path.exists():
            continue
            
        for md_file in dir_path.rglob('*.md'):
            passed, violations = check_file(md_file)
            if not passed:
                all_passed = False
                print(f"FAIL: {md_file}")
                for v in violations:
                    print(f"  {v}")
    
    if all_passed:
        print("No schema dumps in markdown files - OK")
        sys.exit(0)
    else:
        print("\nSchema dumps detected in markdown - FAIL")
        sys.exit(1)


if __name__ == '__main__':
    main()