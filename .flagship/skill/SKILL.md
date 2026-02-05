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

## Create Mode

Run a structured brainstorm, then write files:

- Manifest: `.flagship/experiments/<experiment_id>.yaml`
- State: `.flagship/state/<experiment_id>.yaml`
- Optional workflow update: `.github/workflows/flagship-loop.yml`

Capture at minimum:

- Objective
- Primary KPI
- Guardrails
- Max budget (default `1000`)
- Feature flag key with control/treatment variants
- PostHog project and cohort ids

Use schema rules from `references/experiment-schema.md`.

## Analyze Mode

Load the experiment manifest and read cohort metrics via PostHog MCP.
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
