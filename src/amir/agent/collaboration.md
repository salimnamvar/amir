# Engineering Collaboration Contract

## Team Structure

See `team-config.yaml` for role definitions and assignments.

| Role | Primary Responsibility |
|------|----------------------|
| Tech Lead | Architecture, design decisions, code review |
| Coder | Implementation, unit tests, integration tests |
| QA Engineer | CLI smoke tests, output validation, release verification |
| DevOps | CI/CD pipeline, pre-commit hooks, release tagging |

---

## Workflow

```
Tech Lead
    │
    │ 1. Design Decision
    │    - Architecture
    │    - Acceptance Criteria
    │    - Forbidden Approaches
    ↓
Coder
    │
    │ 2. Implementation
    │    - Write code
    │    - Write tests
    │    - Run unit tests
    │    - Run integration tests
    │    - Run CLI smoke tests
    │    - Verify output
    ↓
Tech Lead
    │
    │ 3. Code Review
    │    - Architecture compliance
    │    - Parameter tracing
    │    - Test coverage
    │    - CLI verification
    ↓
QA Engineer
    │
    │ 4. Release Verification
    │    - CLI smoke tests
    │    - Output validation
    │    - Regression matrix
    │    - Edge cases
    ↓
DevOps
    │
    │ 5. Release
    │    - CI pipeline passes
    │    - Tags release
    │    - Pushes to main
    ↓
Release
```

---

## Gate Rules

### Gate 1: Design Approval (Tech Lead → Coder)

Coder MUST NOT start implementation until:
- [ ] Architecture decision documented
- [ ] Acceptance criteria defined
- [ ] Forbidden approaches listed
- [ ] Test strategy agreed

### Gate 2: Implementation Complete (Coder → Tech Lead)

Tech Lead MUST NOT review until:
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] CLI smoke tests run
- [ ] Output verified manually

### Gate 3: Review Complete (Tech Lead → QA Engineer)

QA verification MUST NOT be skipped:
- [ ] Tech Lead approved architecture compliance
- [ ] All parameters traced
- [ ] No known issues

### Gate 4: Release Ready (QA Engineer → DevOps)

Release MUST NOT happen until:
- [ ] All CI stages pass
- [ ] CLI smoke tests pass
- [ ] Output validation passes
- [ ] Regression matrix passes
- [ ] Documentation updated

---

## Verification Responsibilities

| What | Who Verifies | How |
|------|-------------|-----|
| Architecture compliance | Tech Lead | Code review |
| Unit test coverage | Coder | pytest |
| Integration test coverage | Coder | pytest |
| CLI behavior | QA Engineer | Manual + automated |
| Token budget enforcement | QA Engineer | `arian --max-tokens 1000` |
| Output format | QA Engineer | Content inspection |
| Error handling | QA Engineer | Edge case testing |
| Documentation | Tech Lead | Review |
| CI pipeline | DevOps | GitHub Actions |
| Pre-commit hooks | DevOps | Local verification |

---

## Escalation Path

```
Issue found
    │
    ├── Code issue → Coder fixes
    ├── Architecture issue → Tech Lead decides
    ├── Test gap → Coder adds test
    ├── CLI issue → Coder fixes, QA Engineer verifies
    ├── Output issue → Coder fixes, QA Engineer verifies
    ├── CI issue → DevOps fixes pipeline
    └── Release blocker → All roles collaborate
```

---

## Forbidden Behaviors

| Role | MUST NOT |
|------|----------|
| Tech Lead | Approve without running CLI |
| Tech Lead | Accept "tests pass" without verifying output |
| QA Engineer | Skip smoke tests |
| Coder | Mark complete without CLI verification |
| Coder | Leave parameters unused |
| DevOps | Merge with failing CI |
| Anyone | Skip gate rules |

---

## Communication Protocol

### Handoff Protocol

When handing off work, use the template in `task-handoff.md`.

### Daily Standup

Each role reports:
1. What I did yesterday
2. What I'm doing today
3. What's blocking me

---

## Success Metrics

| Metric | Target | Owner |
|--------|--------|-------|
| CI pass rate | 100% | DevOps |
| Test coverage | ≥ 80% | Coder |
| CLI smoke tests | 100% pass | QA Engineer |
| Budget enforcement | 100% enforced | QA Engineer |
| Output validation | 100% pass | QA Engineer |
| Release defects | 0 critical | All |

---

## No Role May Replace Another

- Tech Lead does NOT code (even if faster)
- Coder does NOT decide architecture (even if obvious)
- QA Engineer does NOT fix bugs
- DevOps does NOT skip CI checks
- Everyone follows the process
- Gate rules are mandatory
