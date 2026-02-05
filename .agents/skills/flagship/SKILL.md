---
name: flagship
description: Build and operate budget-bounded product experiments in a software repository. Use this skill when asked to create, manage, analyze, or iterate feature-flag experiments with cohorts, PostHog MCP, Codex CLI, or GitHub Actions experiment loops.
---

# Flagship

Run one experiment lifecycle in three modes: `create`, `analyze`, `iterate`.

## Core Rules

- Use one primary KPI and optional guardrails.
- Treat `objective`, `primary_kpi`, and `max_budget_usd` as immutable after creation.
- Enforce a cumulative per-experiment budget hard stop.
- Keep repository mutations PR-only.
- Run deterministic policy gates after analysis. Override to `HOLD` on any gate failure.
- Use a hybrid source-of-truth model:
  - PostHog experiment object is authoritative for exposure assignment and experiment results.
  - Repository manifest/state is authoritative for budget, guardrails, rollout policy, and PR workflow.

## Create Mode

Run a structured brainstorm, then write files:

- Manifest: `.flagship/experiments/<experiment_id>.yaml`
- State: `.flagship/state/<experiment_id>.yaml`
- Generated workflow: `.github/workflows/flagship-loop.yml`

Capture at minimum:

- Objective
- Primary KPI
- Guardrails
- Max budget (default `1000`)
- Feature flag key with control/treatment variants
- PostHog project and cohort ids

Before finalizing manifest fields, determine feature-flag provider and MCP readiness.

### Workflow Generation

Generate the GitHub Actions workflow from the skill template:

- Template source: `assets/flagship-loop.yml.tmpl`
- Target output: `.github/workflows/flagship-loop.yml`

Rules:

1. If target workflow does not exist, create it from the template.
2. If target workflow exists, update it to preserve custom repository details while keeping the core Flagship loop behavior.
3. Do not treat the workflow file in the repository as static reference documentation; the agent should own generating/updating it.

### Provider Detection and MCP Bootstrap

1. Detect current feature-flag system from repository code/config:
   - Check dependencies and references for providers such as PostHog, LaunchDarkly, Statsig, Split, or homegrown flags.
2. If a provider is already in use:
   - Reuse that provider for flag rollout in this experiment.
   - Keep provider metadata in the manifest.
3. If no provider is clearly installed:
   - Default to PostHog for MVP.
   - Add a TODO/plan for product SDK instrumentation in app code if missing.
   - Attempt PostHog MCP setup in developer environments with:
     - `npx @posthog/wizard mcp add`
   - For GitHub Actions, configure PostHog MCP in Codex `config.toml` with:
     - `url = "${POSTHOG_MCP_URL}"`
     - `headers = { Authorization = "Bearer ${POSTHOG_API_KEY}" }`
   - Treat API key creation as manual setup owned by the user.

### Hybrid Data Model Requirements

- Persist PostHog experiment identifiers in manifest metadata (for example `posthog.experiment_id`) once created.
- Persist feature-flag provider metadata (for example `feature_flag.provider`).
- On each analyze run:
  - Read results from PostHog experiment APIs/tools.
  - Compare critical settings between PostHog and manifest.
  - If drift is detected, set final action to `HOLD` and require review.

Use schema rules from `references/experiment-schema.md`.

## Analyze Mode

Load the experiment manifest and read experiment metrics via PostHog MCP.
Normalize metrics into one JSON document using `scripts/fetch_metrics.sh`.
Generate an agent recommendation JSON containing:

- `agent_recommendation`
- `confidence`
- `reasoning_summary`

Run deterministic policy gates with `scripts/evaluate_policy.sh`.
Never skip policy gates.

## Iterate Mode

When final action is `ITERATE`, propose code changes for the treatment path.
Prepare a PR-ready change summary with:

- Hypothesis and KPI expectation
- Files changed
- Guardrail impact risks
- Rollback note

Do not mutate core manifest fields. Update report and state only.

## Expected Output Paths

- Manifest: `.flagship/experiments/<experiment_id>.yaml`
- State: `.flagship/state/<experiment_id>.yaml`
- Report: `.flagship/reports/<yyyy-mm-dd>/<experiment_id>.json`
- Ledger: `.flagship/ledger/<experiment_id>.jsonl`

## Decision Payload Schema

Return JSON with exactly these fields:

- `experiment_id`
- `window_start_utc`
- `window_end_utc`
- `kpi_control`
- `kpi_treatment`
- `guardrail_deltas`
- `agent_recommendation`
- `policy_result`
- `policy_fail_reasons`
- `final_action`
- `budget_before_usd`
- `budget_after_usd`
- `confidence`

Use references:

- `references/experiment-schema.md`
- `references/posthog-mcp-queries.md`
- `references/policy-gates.md`
- `references/provider-and-hybrid.md`
