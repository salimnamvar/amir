# CI/CD Pipeline Contract

## Purpose

Automated verification that prevents broken code from reaching main.
Every commit must pass ALL checks before merge.

---

# Rules Awareness

You MUST follow these rule sets:

## Shared Rules (all projects)

- `shared/rules/git/*` — Git workflow rules
- `shared/rules/git/conventional-commits.md` — Commit message rules
- `shared/rules/git/gitflow.md` — Branch strategy rules
- `shared/rules/software-design/quality/cicd.md` — CI/CD standards

## Project Rules

- `rules/agent.md` — Agent compliance rules
- `rules/cicd.md` — CI/CD pipeline rules

## Rule References

When setting up CI/CD, reference:
- `@rules/git/conventional-commits.md`
- `@rules/git/gitflow.md`
- `@rules/software-design/quality/cicd.md`

---

## Pipeline Stages

### Stage 1: Code Quality (blocking)

```bash
# Lint
ruff check src/ tests/
ruff format --check src/ tests/

# Type check
pyright

# Custom checks
scripts/lint.sh  # a-prefix, single-return, imports, google-style
```

**Gate:** All checks pass. No warnings.

### Stage 2: Unit Tests (blocking)

```bash
pytest tests/ -v --tb=short
```

**Gate:** All tests pass. Coverage ≥ 80%.

### Stage 3: Integration Tests (blocking)

```bash
pytest tests/integration/ -v
```

**Gate:** All integration tests pass.

### Stage 4: CLI Smoke Tests (blocking)

```bash
# Install
pip install -e ".[dev]"

# Smoke tests
arian --help
arian  # default behavior
arian --task bug_fix
arian --max-tokens 1000  # MUST enforce budget
arian -o /tmp/arian-test.md
arian -v

# Verify output
test -f /tmp/arian-test.md
grep "Arian Context Manifest" /tmp/arian-test.md
grep "task: bug_fix" /tmp/arian-test.md
```

**Gate:** All smoke tests pass. Budget enforced.

### Stage 5: Output Validation (blocking)

```bash
# Generate context for own repo
cd /path/to/arian
arian --max-tokens 5000 -o /tmp/validation.md

# Validate output
python -c "
import sys
content = open('/tmp/validation.md').read()
checks = [
    ('Manifest', '# Arian Context Manifest' in content),
    ('Task', 'task:' in content),
    ('Files', 'files:' in content),
    ('Tokens', 'tokens:' in content),
    ('No abs paths', '/home/' not in content),
    ('Directory tree', 'Repository Structure' in content),
    ('Summary', '## Summary' in content),
]
failed = [name for name, ok in checks if not ok]
if failed:
    print(f'FAILED: {failed}')
    sys.exit(1)
print('All output checks passed')
"
```

**Gate:** Output validation passes.

---

## Pipeline Configuration

### GitHub Actions

```yaml
name: CI/CD

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.13'
      - run: pip install -e ".[dev]"
      - run: ruff check src/ tests/
      - run: ruff format --check src/ tests/
      - run: pyright

  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.13'
      - run: pip install -e ".[dev]"
      - run: pytest tests/ -v --tb=short

  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.13'
      - run: pip install -e ".[dev]"
      - run: pytest tests/integration/ -v

  cli-smoke:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.13'
      - run: pip install -e ".[dev]"
      - run: arian --help
      - run: arian --max-tokens 1000
      - run: arian --task bug_fix
```

---

## Pre-Commit Hooks

Run locally before every commit:

```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "Running pre-commit checks..."

# Lint
ruff check src/ tests/ || exit 1
ruff format --check src/ tests/ || exit 1

# Type check
pyright || exit 1

# Unit tests
pytest tests/ -x -q || exit 1

echo "Pre-commit checks passed"
```

---

## Release Verification

Before tagging a release:

1. All CI stages pass
2. QA Engineer signs off on CLI smoke tests
3. Tech Lead approves architecture compliance
4. Output validation passes on real repository
5. Documentation is up to date

---

## Failure Handling

| Stage | Failure Action |
|-------|----------------|
| Code Quality | Block merge, fix lint |
| Unit Tests | Block merge, fix test |
| Integration Tests | Block merge, fix integration |
| CLI Smoke | Block merge, fix CLI |
| Output Validation | Block merge, fix output |

**No exceptions.** If it fails, it doesn't ship.

---

## Monitoring

After release, monitor:

- `arian --help` works on fresh install
- `arian` generates valid context
- `arian --max-tokens` is enforced
- No user-reported crashes
