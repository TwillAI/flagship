# Flagship: 5-Slide Technical Deck

## Slide 1 - Problem and Opportunity

**Title:** Move Product Experimentation From Ad Hoc to Systematic

- Teams want faster product iteration, but experiment execution is fragmented across tools and manual steps.
- Typical failure modes: unclear ownership, weak guardrails, and slow code-to-learning loops.
- Flagship turns experimentation into a repo-native engineering workflow with explicit controls.
- Outcome: ship more validated product changes with less operational risk.

## Slide 2 - What Flagship Is

**Title:** Repo-Native Experiment Engine for Product Teams

- One repeatable lifecycle: `create` -> `analyze` -> `iterate`.
- Codex generates experiment setup, code proposals, and decision artifacts.
- GitHub Actions runs the daily analyze loop and recommends next action.
- Engineers stay in control through PR review and merge at every code change.

## Slide 3 - How the Workflow Runs

**Title:** Human-in-the-Loop Automation

- In Codex chat (`create`): define objective/KPI/budget, then generate experiment scaffolding and initial A/B code behind a feature flag.
- Open **PR #1** for the initial implementation (Flow A control vs Flow B treatment); human review and merge required.
- GitHub Actions loop (`analyze`): fetch metrics via PostHog MCP, run deterministic policy gates, produce `final_action`.
- If `final_action = ITERATE`, generate follow-up treatment changes and open another PR; human merge required again.

## Slide 4 - Safety and Governance

**Title:** Fast Iteration Without Losing Control

- Immutable core fields after creation: `objective`, `primary_kpi`, `max_budget_usd`.
- Cumulative budget hard stop per experiment.
- Deterministic policy gates always run; any gate failure or drift forces `HOLD`.
- Full audit trail in repo artifacts: manifest, state, reports, and ledger.

## Slide 5 - Value and Adoption Plan

**Title:** Engineering Value in 30 Days

- **Speed:** reduce idea-to-PR and PR-to-decision latency with a repeatable loop.
- **Quality:** improve decision confidence via explicit KPI + guardrail enforcement.
- **Risk:** keep humans in approval path while automating analysis and iteration proposals.
- Pilot plan: run one onboarding experiment, track cycle time + KPI lift + guardrail incidents, then scale by template.
