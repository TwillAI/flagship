# Flagship

Flagship is a repo-native experimentation loop for an AI SWE workflow:

- define an experiment in your repo
- analyze cohorts from PostHog via MCP
- let Codex propose treatment iterations
- enforce budget and policy gates
- ship changes through PRs only

## What this repo contains

- Skill package: `.agents/skills/flagship/`
- Experiment manifests: `.flagship/experiments/`
- Experiment runtime state: `.flagship/state/`
- Daily reports: `.flagship/reports/<yyyy-mm-dd>/`
- Decision ledger: `.flagship/ledger/`
- Workflow template: `.agents/skills/flagship/assets/flagship-loop.yml.tmpl`
- Generated scheduler workflow: `.github/workflows/flagship-loop.yml`

## Prerequisites

1. A GitHub repository with Actions enabled.
2. PostHog MCP endpoint and API key.
3. OpenAI API key for Codex action runs.
4. At least one experiment manifest and matching state file.

## How to Use Flagship

1. Configure GitHub environment secrets (`OPENAI_API_KEY`, `POSTHOG_API_KEY`, `POSTHOG_MCP_URL`).
2. In Codex, ask to create a new Flagship experiment. The skill should detect your current feature-flag provider first.
3. Commit the generated manifest in `.flagship/experiments/` and state file in `.flagship/state/`.
4. Let the skill generate `.github/workflows/flagship-loop.yml` from the template, then trigger it manually once.
5. Review the PR created or updated on `codex/flagship/<experiment_id>`.
6. Check outputs in `.flagship/reports/<yyyy-mm-dd>/` and `.flagship/ledger/`.

## High-Level Flow (with Example)

Think of Flagship as a daily experiment operator that loops between code and data.

```text
You define experiment -> GitHub Action runs daily -> Codex analyzes cohorts (PostHog MCP)
-> Policy gates decide safe action -> Codex proposes treatment updates (if allowed)
-> PR is updated -> You review/merge -> Repeat until winner or stop
```

Example projection:

1. You create `onboarding-copy-v1` with a `$1000` budget and KPI `activation_24h_rate`.
2. Day 1 run: sample is too low, policy returns `HOLD`.
3. Day 3 run: enough traffic, treatment outperforms control, policy returns `ITERATE`, PR is updated with copy improvements.
4. Day 5 run: treatment still wins and guardrails are healthy, PR gets another safe iteration.
5. Day 8 run: budget is nearly exhausted or KPI plateaus, final action becomes `KEEP_TREATMENT` or `STOP`.
6. You merge the final PR and mark experiment status accordingly.

## Provider Detection and MCP Setup

Flagship should not blindly assume PostHog flags on day 1.

During experiment creation, the skill should:

1. Inspect the repo for an existing feature-flag provider.
2. Reuse existing provider if clearly present.
3. Default to PostHog only if no provider is detected.

If defaulting to PostHog:

- Local/dev setup can use:
  - `npx @posthog/wizard mcp add`
- GitHub Actions uses API-key auth in Codex MCP config (already handled in the workflow).
- The only manual step is creating and storing a PostHog MCP-compatible API key as `POSTHOG_API_KEY`.

## Hybrid Source of Truth

Flagship uses a hybrid model, not filesystem-only and not PostHog-only.

- PostHog experiment object is the source of truth for:
  - exposure assignment
  - experiment results and lifecycle in PostHog
- Repo manifest/state is the source of truth for:
  - budget cap and spend tracking
  - guardrail policy gates
  - PR workflow and automation state

Practical rule:

1. Create or link a PostHog experiment and store IDs in manifest.
2. Read results from PostHog in daily runs.
3. If critical settings drift between PostHog and manifest, force `HOLD`.

## GitHub setup

Create a GitHub Environment named `flagship` and add secrets:

- `OPENAI_API_KEY`
- `POSTHOG_API_KEY`
- `POSTHOG_MCP_URL`

The workflow uses environment-scoped secrets by default.

## Workflow Template and Generation

Flagship treats the GitHub Action as generated project code.

- Template lives in the skill: `.agents/skills/flagship/assets/flagship-loop.yml.tmpl`
- Generated workflow target: `.github/workflows/flagship-loop.yml`

During `create` mode, the agent should generate or update the target workflow from the template.

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
  provider: posthog
  key: onboarding.copy_variant
  control_variant: control
  treatment_variant: treatment
posthog:
  project_id: "12345"
  experiment_id: "9876"
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

The generated workflow is scheduled daily and can also be started manually from GitHub Actions:

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
chmod +x .agents/skills/flagship/scripts/*.sh
```

Validate manifest:

```bash
.agents/skills/flagship/scripts/validate_manifest.sh --manifest .flagship/experiments/onboarding-copy-v1.yaml
```

Normalize metrics:

```bash
.agents/skills/flagship/scripts/fetch_metrics.sh \
  --manifest .flagship/experiments/onboarding-copy-v1.yaml \
  --mcp-output /path/to/raw-mcp.json \
  --output /tmp/metrics.json
```

Evaluate policy:

```bash
.agents/skills/flagship/scripts/evaluate_policy.sh \
  --manifest .flagship/experiments/onboarding-copy-v1.yaml \
  --metrics /tmp/metrics.json \
  --budget /tmp/budget.json \
  --recommendation /tmp/recommendation.json \
  --output /tmp/decision.json
```

## References

- Skill instructions: `.agents/skills/flagship/SKILL.md`
- Schema reference: `.agents/skills/flagship/references/experiment-schema.md`
- PostHog MCP flow: `.agents/skills/flagship/references/posthog-mcp-queries.md`
- Policy gates: `.agents/skills/flagship/references/policy-gates.md`
- Provider + hybrid model: `.agents/skills/flagship/references/provider-and-hybrid.md`
