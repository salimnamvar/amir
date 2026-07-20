# Contract CI Checks

Normative checks that MUST run on every change under `docs/contract/`.

## Required checks

1. **No schema field dumps in markdown**  
   Fail if `docs/specification/**/*.md` or `docs/story/**/*.md` embed full JSON Schema property blocks (heuristic: lines matching `^\s{2,}type:\s` adjacent to `^\s{2,}properties:` dumps). Contracts are the sole structural authority.

2. **Allowlist test vectors**  
   Expand profiles from `docs/contract/allowlists/*.yaml` and validate `test_vectors` against `schemas/runtime/allowlist-merge.schema.yaml` intersection algorithm.

3. **Coercion approval structural rule**  
   Schema validation must reject Artifact instances with `observation_method=synthesized` without `coercion_approval_id`.

4. **Docker production ban**  
   Schema validation must reject Sandbox instances with `environment=production` and `runtime=docker`. Omitting `environment` must fail (required field).

5. **Shared enum consistency**  
   Diff failure-category / observation-method enums against `schemas/shared-enums.schema.yaml` definitions.

## Suggested entrypoints (implementation)

```bash
# Validate all YAML schemas parse
find docs/contract/schemas -name '*.yaml' -print0 | xargs -0 -n1 python -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))'

# Allowlist merge unit tests (from coding_standard test_vectors)
python tools/ci/check_allowlist_merge.py docs/contract/allowlists/coding_standard.yaml

# Markdown drift heuristic
python tools/ci/check_no_schema_dumps.py docs/specification docs/story
```

These scripts may be added during implementation; this file defines the **required** check surface for freeze.
