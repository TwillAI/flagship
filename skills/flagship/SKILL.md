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

### Pre-Write Gate (Mandatory)

Do not write any files until required parameters are clarified and explicitly specified by the human.

Required human-confirmed fields before any write:

- Experiment definition (`experiment_id`/title and objective)
- Primary KPI
- Max budget (`max_budget_usd`)
- MCP readiness for the selected feature-flag provider
- GitHub Actions secret setup confirmation for MCP auth

Write-blocked files until gate passes:

- `.flagship/experiments/<experiment_id>.yaml`
- `.flagship/state/<experiment_id>.yaml`
- `.github/workflows/flagship-loop.yml`

If any required field is missing or ambiguous:

- Continue brainstorming with targeted follow-up questions.
- Summarize which fields are still missing.
- Do not scaffold or update files yet.

After all required fields are explicit, restate final values and get a clear human go-ahead, then write files.

### MCP Readiness + GitHub Secret Guidance (Required During Brainstorm)

During `create`, verify MCP readiness before writing files.

1. Check local MCP install for the selected provider.
2. If missing, provide setup commands and wait for human confirmation.
3. Provide GitHub Actions API key setup instructions with exact secret names.
4. Confirm completion before passing the pre-write gate.

For PostHog, use this minimum guidance:

- Local install check:
  - `codex mcp list`
  - `codex mcp get posthog --json`
- If not installed:
  - US cloud (default): `codex mcp add posthog --url https://mcp.posthog.com/mcp --bearer-token-env-var POSTHOG_API_KEY`
  - EU cloud: `codex mcp add posthog --url https://mcp-eu.posthog.com/mcp --bearer-token-env-var POSTHOG_API_KEY`
  - OAuth fallback: `codex mcp add posthog --url https://mcp.posthog.com/mcp` then `codex mcp login posthog`
  - Optional wizard bootstrap: `npx @posthog/wizard mcp add`
  - Re-check: `codex mcp get posthog --json`
- GitHub Actions secrets:
  - Add `POSTHOG_MCP_URL` (PostHog MCP server URL)
  - Add `POSTHOG_API_KEY` (PostHog personal API key with required experiment read scopes)
  - Ensure workflow environment/repo exposes those names unchanged.

### Brainstorm Conversation Style

Use a collaborative conversation, not a rigid intake form.

- Ask one high-leverage question at a time.
- Start with product and user outcome questions before technical setup details.
- Reflect back what the user said in plain language before asking the next question.
- Offer 2 to 3 concrete experiment directions with tradeoffs, then recommend one.
- Avoid dumping a long required-field checklist in one message.
- Use defaults where reasonable and ask only for missing technical IDs at the end.
- Keep tone natural and concise; focus on decision quality, not template completion.

Suggested question flow:

1. Desired behavior change and target user segment.
2. One success KPI and one failure condition.
3. Smallest treatment change that can ship quickly.
4. Guardrail risk that should stop or pause rollout.
5. Technical IDs (PostHog project/cohorts/flag key/variants) only after direction is chosen.

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
     - US cloud (default): `codex mcp add posthog --url https://mcp.posthog.com/mcp --bearer-token-env-var POSTHOG_API_KEY`
     - EU cloud: `codex mcp add posthog --url https://mcp-eu.posthog.com/mcp --bearer-token-env-var POSTHOG_API_KEY`
     - Verify with: `codex mcp get posthog --json`
     - Optional wizard bootstrap: `npx @posthog/wizard mcp add`
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
