# CI/CD Rules

## Pipeline Requirements

### Stage 1: Code Quality (blocking)

- ruff check must pass
- ruff format must pass
- pyright must pass
- Custom lint must pass (scripts/lint.sh)

### Stage 2: Unit Tests (blocking)

- All tests must pass
- Coverage ≥ 80%

### Stage 3: Integration Tests (blocking)

- All integration tests must pass

### Stage 4: CLI Smoke Tests (blocking)

```bash
arian --help
arian  # default behavior
arian --task bug_fix
arian --max-tokens 1000  # MUST enforce budget
arian -o /tmp/test.md
arian -v
```

### Stage 5: Output Validation (blocking)

- Manifest present
- No absolute paths
- Directory tree hierarchical
- Token count ≤ max_tokens

## Pre-Commit Rules

Every commit must pass:

1. Lint check
2. Format check
3. Type check
4. Unit tests (quick)

## Branch Rules

- main: protected, requires PR + all checks
- develop: requires PR + all checks
- feature/*: can push directly, CI runs on push

## Release Rules

Before tagging release:

1. All CI stages pass
2. QA Engineer signs off
3. Tech Lead approves
4. Documentation updated
5. CHANGELOG updated
