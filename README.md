# Flagship

Flagship is a repo-native experimentation loop for an AI SWE workflow:

- define an experiment in your repo
- analyze cohorts from PostHog via MCP
- let Codex propose treatment iterations
- enforce budget and policy gates
- ship changes through PRs only

## What this repo contains

- Skill package: `.flagship/skill/`
- Experiment manifests: `.flagship/experiments/`
- Experiment runtime state: `.flagship/state/`
- Daily reports: `.flagship/reports/<yyyy-mm-dd>/`
- Decision ledger: `.flagship/ledger/`
- Global scheduler workflow: `.github/workflows/flagship-loop.yml`

## Prerequisites

1. A GitHub repository with Actions enabled.
2. PostHog MCP endpoint and API key.
3. OpenAI API key for Codex action runs.
4. At least one experiment manifest and matching state file.

## How to Use Flagship

1. Configure GitHub environment secrets (`OPENAI_API_KEY`, `POSTHOG_API_KEY`, `POSTHOG_MCP_URL`).
2. In Codex, ask to create a new Flagship experiment.
3. Commit the generated manifest in `.flagship/experiments/` and state file in `.flagship/state/`.
4. Trigger `.github/workflows/flagship-loop.yml` manually once, then rely on daily schedule.
5. Review the PR created or updated on `codex/flagship/<experiment_id>`.
6. Check outputs in `.flagship/reports/<yyyy-mm-dd>/` and `.flagship/ledger/`.

## GitHub setup

Create a GitHub Environment named `flagship` and add secrets:

- `OPENAI_API_KEY`
- `POSTHOG_API_KEY`
- `POSTHOG_MCP_URL`

The workflow uses environment-scoped secrets by default.

## Create an experiment with Codex

In Codex, run a prompt like:

```text
Use the flagship skill and create a new flagship experiment for onboarding activation.
```

The create flow should write:

- `.flagship/experiments/<experiment_id>.yaml`
- `.flagship/state/<experiment_id>.yaml`

## Manifest example

Create `.flagship/experiments/onboarding-copy-v1.yaml`:

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

## State example

Create `.flagship/state/onboarding-copy-v1.yaml`:

```yaml
spent_usd_total: 0
budget_remaining_usd: 1000
last_run_at_utc: null
last_decision: HOLD
current_rollout_percent: 0
open_pr_number: null
```

## Run the loop

The workflow is scheduled daily and can also be started manually from GitHub Actions:

- Workflow file: `.github/workflows/flagship-loop.yml`
- Branch pattern for updates: `codex/flagship/<experiment_id>`

Per active experiment, the loop:

1. validates the manifest
2. configures Codex home + PostHog MCP
3. runs Codex analysis
4. normalizes cohort metrics
5. runs deterministic policy gates
6. runs Codex iterate mode only if final action is `ITERATE`
7. writes decision report + ledger entry
8. opens/updates a PR

## Policy and budget rules

- Immutable fields after creation:
  - `objective`
  - `primary_kpi`
  - `max_budget_usd`
- Budget hard stop when remaining budget is `<= 0` (final action forced to `STOP`).
- Guardrail and sample-size failures force `HOLD`.
- All repository changes are PR-only.

## Script usage (local)

```bash
chmod +x .flagship/skill/scripts/*.sh
```

Validate manifest:

```bash
.flagship/skill/scripts/validate_manifest.sh --manifest .flagship/experiments/onboarding-copy-v1.yaml
```

Normalize metrics:

```bash
.flagship/skill/scripts/fetch_metrics.sh \
  --manifest .flagship/experiments/onboarding-copy-v1.yaml \
  --mcp-output /path/to/raw-mcp.json \
  --output /tmp/metrics.json
```

Evaluate policy:

```bash
.flagship/skill/scripts/evaluate_policy.sh \
  --manifest .flagship/experiments/onboarding-copy-v1.yaml \
  --metrics /tmp/metrics.json \
  --budget /tmp/budget.json \
  --recommendation /tmp/recommendation.json \
  --output /tmp/decision.json
```

## References

- Skill instructions: `.flagship/skill/SKILL.md`
- Schema reference: `.flagship/skill/references/experiment-schema.md`
- PostHog MCP flow: `.flagship/skill/references/posthog-mcp-queries.md`
- Policy gates: `.flagship/skill/references/policy-gates.md`
