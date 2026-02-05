# Policy Gates

Deterministic policy gates run after agent analysis. They can override the recommendation.

## Inputs

- Manifest YAML
- Normalized metrics JSON
- Budget snapshot JSON
- Agent recommendation JSON

## Gates

1. Budget hard stop
- Fail if remaining budget is `<= 0`.
- Force final action to `STOP`.

2. Minimum sample size
- Fail if either cohort sample is below threshold.
- Default threshold: `500`.
- Force final action to `HOLD`.

3. Guardrail degradation
- Fail if any guardrail delta exceeds max degradation.
- Use per-guardrail `max_degradation_pct` from manifest when present.
- Compare degradation as percentage change from control baseline.
- Default fallback max degradation: `2.0` (%).
- Force final action to `HOLD`.

4. PostHog/manifest drift
- Fail if critical metadata mismatches between PostHog experiment metadata and manifest metadata.
- Critical fields include:
  - `posthog.experiment_id`
  - `feature_flag.provider`
  - `feature_flag.key`
  - `feature_flag.control_variant`
  - `feature_flag.treatment_variant`
- Force final action to `HOLD`.

5. Recommendation validity
- Fail if recommendation is not one of:
  - `ITERATE`
  - `KEEP_TREATMENT`
  - `KEEP_CONTROL`
  - `HOLD`
  - `STOP`
- Force final action to `HOLD`.

## Output

`PASS|FAIL` with final action and reason list.

### Final Action Logic

- If budget gate fails: `STOP`.
- Else if any gate fails: `HOLD`.
- Else: use agent recommendation.
