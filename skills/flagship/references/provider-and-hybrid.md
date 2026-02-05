# Provider Detection and Hybrid Source of Truth

Use this reference during `create` and `analyze` modes.

## 1) Feature-Flag Provider Detection

Inspect repository dependencies and config before assuming PostHog.

Common signals:

- PostHog: `posthog-js`, `posthog-node`, `posthog-ruby`, `posthog-python`
- LaunchDarkly: `launchdarkly`, `ldclient`
- Statsig: `statsig`
- Split: `splitio`

If one provider is clearly present, reuse it for flag delivery.

If none is present, default to PostHog for Flagship MVP.

## 2) MCP Bootstrap

### Local development

Preferred Codex setup:

```bash
codex mcp add posthog --url https://mcp.posthog.com/mcp --bearer-token-env-var POSTHOG_API_KEY
```

EU cloud variant:

```bash
codex mcp add posthog --url https://mcp-eu.posthog.com/mcp --bearer-token-env-var POSTHOG_API_KEY
```

OAuth fallback:

```bash
codex mcp add posthog --url https://mcp.posthog.com/mcp
codex mcp login posthog
```

Optional wizard bootstrap:

```bash
npx @posthog/wizard mcp add
```

### GitHub Actions

Use API key auth in `CODEX_HOME/config.toml`:

```toml
[mcp_servers.posthog]
transport = "streamable_http"
url = "${POSTHOG_MCP_URL}"
headers = { Authorization = "Bearer ${POSTHOG_API_KEY}" }
```

Manual step: user creates PostHog MCP-compatible personal API key.

### Readiness Checklist (Use During Create Brainstorm)

Treat MCP readiness as a required checkpoint before writing manifest/state/workflow files.

Run:

```bash
codex mcp list
codex mcp get posthog --json
```

If PostHog MCP is missing, guide setup with one of:

```bash
codex mcp add posthog --url https://mcp.posthog.com/mcp --bearer-token-env-var POSTHOG_API_KEY
```

or:

```bash
codex mcp add posthog --url https://mcp-eu.posthog.com/mcp --bearer-token-env-var POSTHOG_API_KEY
```

Then verify:

```bash
codex mcp get posthog --json
```

For GitHub Actions, instruct user to add these secrets:

- `POSTHOG_MCP_URL`
- `POSTHOG_API_KEY`

Keep secret names aligned with workflow env/config references.

## 3) Hybrid Source of Truth Rules

Treat PostHog and repo metadata as complementary authorities:

- PostHog experiment object:
  - experiment lifecycle in PostHog
  - exposure assignment
  - results computation
- Repo manifest/state:
  - budget ceiling
  - policy gates
  - rollout workflow
  - PR automation mapping

## 4) Required Linkage Metadata

When available, store:

- `feature_flag.provider`
- `feature_flag.key`
- `posthog.project_id`
- `posthog.experiment_id`

If metadata drift is detected between PostHog and manifest on critical fields, force `HOLD`.
