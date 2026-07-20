#!/usr/bin/env python3
"""
CI Check: Allowlist test vector validation
Validates that allowlist profiles correctly implement the intersection merge algorithm.
"""

import sys
import yaml
import json
import re
from pathlib import Path
from typing import List, Dict, Set


def load_profile(path: Path) -> Dict:
    """Load an allowlist profile YAML file."""
    with open(path, 'r') as f:
        return yaml.safe_load(f)


def compute_effective_allowlist(agent_set: Set[str], sandbox_set: Set[str], 
                               role_set: Set[str], platform_llm_routes: Set[str]) -> Set[str]:
    """
    Compute effective allowlist using intersection merge algorithm.
    
    Pseudocode (normative):
      base = agent_set ∩ sandbox_set
      if role_set non-empty: base = base ∩ role_set
      effective = base ∪ platform_llm_routes
      empty base before platform = deny-all except platform LLM routes
    """
    # Step 1: Intersect agent and sandbox sets
    base = agent_set & sandbox_set
    
    # Step 2: Intersect with role set if non-empty (skip if empty/omitted)
    if role_set:  # Only intersect if role_set is explicitly set and non-empty
        base = base & role_set
    
    # Step 3: Union with platform LLM routes
    effective = base | platform_llm_routes
    
    return effective


def load_test_vector_profile(vector: Dict) -> Set[str]:
    """Extract host set from test vector profile reference."""
    # This would expand the profile from the allowlists directory
    # For now, we use the hosts directly from the test vector
    return set(vector.get('agent_hosts', []))


def expand_profile(profile_name: str, profiles_dir: Path) -> Set[str]:
    """Expand a profile name to its host list."""
    profile_map = {
        'coding_standard': profiles_dir / 'coding_standard.yaml',
        'container_build': profiles_dir / 'container_build.yaml',
        'llm_only': profiles_dir / 'llm_only.yaml',
        'custom': None  # Custom uses inline hosts
    }
    
    if profile_name in profile_map and profile_map[profile_name]:
        profile = load_profile(profile_map[profile_name])
        return set(profile.get('hosts', []))
    return set()


def validate_test_vector(vector: Dict, profiles_dir: Path) -> tuple[bool, str]:
    """Validate a single test vector."""
    vector_name = vector.get('name', 'unnamed')
    
    # Get agent set (expand profile or use inline hosts)
    agent_profile = vector.get('agent_profile')
    agent_hosts = vector.get('agent_hosts', [])
    if agent_profile:
        agent_set = expand_profile(agent_profile, profiles_dir)
    else:
        agent_set = set(agent_hosts)
    
    # Get sandbox set (expand profile or use inline hosts)
    sandbox_profile = vector.get('sandbox_profile')
    sandbox_hosts = vector.get('sandbox_hosts', [])
    if sandbox_profile:
        sandbox_set = expand_profile(sandbox_profile, profiles_dir)
    else:
        sandbox_set = set(sandbox_hosts)
    
    # Get role set
    role_set = set(vector.get('role_required_network', []))
    
    # Get platform routes
    platform_routes = set(vector.get('platform_llm_routes', []))
    
    # Compute effective allowlist
    actual = compute_effective_allowlist(agent_set, sandbox_set, role_set, platform_routes)
    
    # Compare with expected (before platform union for most cases)
    expected_before_platform = set(vector.get('expected_effective_before_platform', []))
    expected = set(vector.get('expected_effective', []))
    
    if expected:
        # Full expected includes platform routes
        expected_set = expected
    else:
        # Expected is before platform union
        expected_set = expected_before_platform | platform_routes
    
    if actual != expected_set:
        return False, f"{vector_name}: expected {sorted(expected_set)}, got {sorted(actual)}"
    
    return True, f"{vector_name}: OK"


def main():
    if len(sys.argv) < 2:
        print("Usage: check_allowlist_merge.py <profile1.yaml> [profile2.yaml ...]")
        sys.exit(1)
    
    profiles_dir = Path('docs/contract/allowlists')
    
    all_passed = True
    for profile_path in sys.argv[1:]:
        path = Path(profile_path)
        if not path.exists():
            continue
            
        profile = load_profile(path)
        test_vectors = profile.get('test_vectors', [])
        
        if not test_vectors:
            print(f"WARN: {path.name} has no test_vectors - cannot validate")
            continue
        
        print(f"Validating {path.name}...")
        for vector in test_vectors:
            passed, message = validate_test_vector(vector, profiles_dir)
            print(f"  {message}")
            if not passed:
                all_passed = False
    
    if all_passed:
        print("\nAll allowlist test vectors passed!")
        sys.exit(0)
    else:
        print("\nSome test vectors failed!")
        sys.exit(1)


if __name__ == '__main__':
    main()