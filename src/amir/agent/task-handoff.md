# Task Handoff Template

Use this template when handing off work between roles.

---

## Tech Lead → Coder (Design Handoff)

```
## Task: <task name>

### Status
DESIGN APPROVED — Ready for implementation

### Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

### Implementation Constraints
- Must not change <existing interface>
- Must use <existing pattern>
- Must add tests for all new code

### Forbidden Approaches
- Do not <forbidden thing>
- Do not <forbidden thing>

### Test Strategy
- Unit tests for: <list functions>
- Integration test: <describe scenario>
- CLI verification: <describe what to run>

### Files to Modify
- src/arian/... (description)
- tests/... (description)

### Questions for Coder
- Any clarifications needed
```

---

## Coder → Tech Lead (Implementation Handoff)

```
## Task: <task name>

### Status
IMPLEMENTATION COMPLETE — Ready for review

### Changed Files
- src/arian/service/planner.py (added _enforce_budget)
- tests/integration/test_budget.py (new test)

### Verification

#### Unit Tests
```
pytest tests/service/planner/ -v
# 12 passed
```

#### Integration Tests
```
pytest tests/integration/ -v
# 5 passed
```

#### CLI Verification
```
arian --help                           ✓
arian                                  ✓
arian --max-tokens 1000                ✓ (output ≤ 1000 tokens)
arian --task bug_fix                   ✓
arian -v                               ✓
```

### Tech Lead Review Needed
- [ ] Architecture compliance for budget enforcement
- [ ] Parameter tracing: --max_tokens → TokenBudget → _plan_chunks

### Known Issues
- None
```

---

## Tech Lead → QA Engineer (Review Feedback)

```
## Review: <task name>

### Status
APPROVED / REJECTED / CHANGES REQUESTED

### Checklist
- [x] CLI --help works
- [x] Default behavior works
- [x] All parameters respected
- [ ] Token budget enforced ← FAILED
- [x] Integration tests pass

### Issues Found
1. CRITICAL: --max-tokens not enforced
   - Location: context_planner.py:386
   - Fix: Add budget check in _plan_chunks()

### Required Changes
- Fix issue #1
- Add integration test for budget enforcement
- Re-run CLI verification

### Approved Changes
- None
```

---

## QA Engineer → DevOps (Release Verification)

```
## Release Verification: v0.1.0

### Status
READY / BLOCKED

### Smoke Tests
- [x] arian --help
- [x] arian (default)
- [x] arian --task bug_fix
- [x] arian --max-tokens 1000 (budget enforced)
- [x] arian -o /tmp/test.md
- [x] arian -v

### Output Validation
- [x] Manifest present
- [x] No absolute paths
- [x] Directory tree hierarchical
- [x] Summary section present
- [x] Token count ≤ max_tokens

### Regression Matrix
- [x] Empty repo
- [x] Single file
- [x] Large repo (153 files)
- [x] No Python files
- [x] Deep nesting

### Approval
Released by: QA Engineer
Date: <date>
```
