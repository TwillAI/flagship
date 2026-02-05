# PostHog MCP Query Flow

Use the PostHog MCP server for cohort analysis in `analyze` mode.

## Goal

Collect control/treatment metrics for:

- primary KPI value per cohort
- sample size per cohort
- guardrail values per cohort

Normalize these values via `scripts/fetch_metrics.sh`.

## Recommended Sequence

1. Read experiment manifest.
2. Resolve:
- `posthog.project_id`
- `posthog.cohorts.control`
- `posthog.cohorts.treatment`
- `primary_kpi`
- `guardrails[*].name`
3. Query PostHog MCP for the target time window.
4. Save raw MCP response JSON to a file.
5. Run `scripts/fetch_metrics.sh` to normalize.

## Raw JSON Shape Expected by `fetch_metrics.sh`

```json
{
  "window_start_utc": "2026-02-05T00:00:00Z",
  "window_end_utc": "2026-02-06T00:00:00Z",
  "variants": {
    "control": {
      "kpi": 0.214,
      "sample_size": 640,
      "guardrails": {
        "onboarding_completion_time_p95": 112.4,
        "error_rate": 0.011
      }
    },
    "treatment": {
      "kpi": 0.239,
      "sample_size": 618,
      "guardrails": {
        "onboarding_completion_time_p95": 114.2,
        "error_rate": 0.012
      }
    }
  }
}
```

## Notes

- Store API host and credentials in GitHub environment secrets.
- In GitHub Actions, configure Codex MCP via `config.toml`.
- Keep this flow read-only for analysis steps.
