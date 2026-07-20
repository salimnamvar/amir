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
   Domain schemas MUST `$ref` `schemas/shared-enums.schema.yaml#/$defs/*` for FailureCategory /
   TerminalFailureCategory / ValidatorFailureCategory / ParserStrategy / OutputMode where applicable.
   Inline re-declaration of those enums is a CI failure.

6. **Parser default chain order**  
   `interfaces/parser-registry.yaml` `default_strategy_chain` MUST use fixed `prefixItems` order:
   structured_output → tool_call_interception → markdown_block → workspace_observation.
   Permutations and `llm_coercion` in the default chain must fail validation.

7. **Task validation_budget required**  
   Reject Task instances missing `validation_budget` with at least one of max_tokens/max_usd.

8. **CostLease active bindings**  
   Reject active CostLease without `scope` and `agent_session_id`; reject revoked without
   cancellation_reason + revocation_revision + revocation_timestamp.

9. **Allowlist profiles present**  
   Every SandboxPolicy profile enum value (`llm_only`, `coding_standard`, `container_build`, `custom`) must have
   expansion source under `allowlists/` except `custom` (inline).

## CI Check Entrypoints

```bash
# Validate all YAML schemas parse
find docs/contract/schemas -name '*.yaml' -print0 | xargs -0 -n1 python -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))'

# Allowlist merge unit tests (all profiles with test_vectors)
python tools/ci/check_allowlist_merge.py docs/contract/allowlists/*.yaml

# Markdown drift heuristic
python tools/ci/check_no_schema_dumps.py docs/specification docs/story
```

These scripts are provided in `tools/ci/` and run as part of the contract validation pipeline.
