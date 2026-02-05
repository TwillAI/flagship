# Experiment Schema

This reference defines the required YAML schema for Flagship experiments.

## Manifest Path

`.flagship/experiments/<experiment_id>.yaml`

## Required Manifest Fields

```yaml
experiment_id: onboarding-copy-v1
title: Improve onboarding first-run activation
objective: Increase onboarding activation within 24 hours
primary_kpi: activation_24h_rate
guardrails:
  - name: onboarding_completion_time_p95
    direction: lower_is_better
    max_degradation_pct: 2.0
  - name: error_rate
    direction: lower_is_better
    max_degradation_pct: 1.0
max_budget_usd: 1000
feature_flag:
  key: onboarding.copy_variant
  control_variant: control
  treatment_variant: treatment
posthog:
  project_id: "12345"
  cohorts:
    control: "1122"
    treatment: "3344"
status: active
created_at_utc: "2026-02-05T00:00:00Z"
```

## Status Values

- `draft`
- `active`
- `paused`
- `winner_selected`
- `completed`
- `stopped`

## Immutable Fields

After first commit, these fields must not change:

- `objective`
- `primary_kpi`
- `max_budget_usd`

## State Path

`.flagship/state/<experiment_id>.yaml`

## Required State Fields

```yaml
spent_usd_total: 0
budget_remaining_usd: 1000
last_run_at_utc: null
last_decision: HOLD
current_rollout_percent: 0
open_pr_number: null
```

## Report Path

`.flagship/reports/<yyyy-mm-dd>/<experiment_id>.json`

Decision reports must follow the schema defined in `SKILL.md`.
