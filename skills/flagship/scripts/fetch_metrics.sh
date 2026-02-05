#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  fetch_metrics.sh --manifest <path> --mcp-output <path> --output <path> [--window-start <iso8601>] [--window-end <iso8601>]

Description:
  Normalize raw PostHog MCP metric output into the Flagship metrics schema.
EOF
}

manifest=""
mcp_output=""
output=""
window_start=""
window_end=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) manifest="$2"; shift 2 ;;
    --mcp-output) mcp_output="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --window-start) window_start="$2"; shift 2 ;;
    --window-end) window_end="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$manifest" || -z "$mcp_output" || -z "$output" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

python3 - "$manifest" "$mcp_output" "$output" "$window_start" "$window_end" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

def load_yaml(path: Path):
    try:
        import yaml  # type: ignore
        return yaml.safe_load(path.read_text())
    except ImportError:
        try:
            raw = subprocess.check_output(
                [
                    "ruby",
                    "-ryaml",
                    "-rjson",
                    "-e",
                    "print JSON.dump(YAML.load_file(ARGV[0]))",
                    str(path),
                ],
                text=True,
            )
            return json.loads(raw)
        except Exception as exc:
            print(
                "Unable to parse YAML. Install pyyaml or ensure ruby with psych is available.",
                file=sys.stderr,
            )
            raise exc

manifest_path = Path(sys.argv[1])
mcp_path = Path(sys.argv[2])
output_path = Path(sys.argv[3])
window_start_arg = sys.argv[4]
window_end_arg = sys.argv[5]

manifest = load_yaml(manifest_path)
raw = json.loads(mcp_path.read_text())

manifest_feature_flag = manifest.get("feature_flag", {}) or {}
manifest_posthog = manifest.get("posthog", {}) or {}
raw_experiment = raw.get("experiment", {}) or raw.get("posthog_experiment", {}) or {}

def resolve_variant(container, names):
    if not isinstance(container, dict):
        return {}

    for name in names:
        if name and isinstance(container.get(name), dict):
            return container[name]

    normalized = {str(name).lower() for name in names if name}
    for key, value in container.items():
        if str(key).lower() in normalized and isinstance(value, dict):
            return value

    return {}

def resolve_variants(payload, control_name, treatment_name):
    candidates = [
        payload.get("variants"),
        payload.get("cohorts"),
        payload.get("results"),
        (payload.get("metrics", {}) or {}).get("variants"),
    ]

    control_names = [control_name, "control", "baseline", "a"]
    treatment_names = [treatment_name, "treatment", "variant", "b"]

    control_variant = {}
    treatment_variant = {}
    for container in candidates:
        if not isinstance(container, dict):
            continue

        if not control_variant:
            control_variant = resolve_variant(container, control_names)
        if not treatment_variant:
            treatment_variant = resolve_variant(container, treatment_names)
        if control_variant and treatment_variant:
            break

    return control_variant, treatment_variant

control, treatment = resolve_variants(
    raw,
    manifest_feature_flag.get("control_variant"),
    manifest_feature_flag.get("treatment_variant"),
)

def read_nested(data, dotted):
    cur = data
    for key in dotted.split("."):
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur

def read_raw_experiment(*candidates):
    for source in [raw_experiment, raw]:
        if not isinstance(source, dict):
            continue
        for key in candidates:
            if "." in key:
                value = read_nested(source, key)
            else:
                value = source.get(key)
            if value is not None:
                return value
    return None

drift_reasons = []

def add_drift_reason(field_name, manifest_value, posthog_value):
    if manifest_value is None or posthog_value is None:
        return
    if str(manifest_value) != str(posthog_value):
        drift_reasons.append(
            f"{field_name} mismatch (manifest={manifest_value!r}, posthog={posthog_value!r})"
        )

add_drift_reason(
    "posthog.experiment_id",
    manifest_posthog.get("experiment_id"),
    read_raw_experiment("experiment_id", "id"),
)
add_drift_reason(
    "feature_flag.provider",
    manifest_feature_flag.get("provider"),
    read_raw_experiment("provider"),
)
add_drift_reason(
    "feature_flag.key",
    manifest_feature_flag.get("key"),
    read_raw_experiment("feature_flag_key", "feature_flag.key", "flag.key"),
)
add_drift_reason(
    "feature_flag.control_variant",
    manifest_feature_flag.get("control_variant"),
    read_raw_experiment("control_variant", "variants.control.name"),
)
add_drift_reason(
    "feature_flag.treatment_variant",
    manifest_feature_flag.get("treatment_variant"),
    read_raw_experiment("treatment_variant", "variants.treatment.name"),
)

def read_number(variant, keys, default=0.0):
    if not isinstance(variant, dict):
        return float(default)

    for key in keys:
        value = variant.get(key)
        if value is not None:
            try:
                return float(value)
            except (TypeError, ValueError):
                pass

    nested_metrics = variant.get("metrics", {}) or {}
    if isinstance(nested_metrics, dict):
        for key in keys:
            value = nested_metrics.get(key)
            if value is not None:
                try:
                    return float(value)
                except (TypeError, ValueError):
                    pass

    return float(default)

def read_int(variant, keys, default=0):
    return int(read_number(variant, keys, default=default))

def read_guardrails(variant):
    if not isinstance(variant, dict):
        return {}

    direct = variant.get("guardrails")
    if isinstance(direct, dict):
        return direct

    nested_metrics = variant.get("metrics", {}) or {}
    if isinstance(nested_metrics, dict):
        nested_guardrails = nested_metrics.get("guardrails")
        if isinstance(nested_guardrails, dict):
            return nested_guardrails

    return {}

control_guardrails = read_guardrails(control)
treatment_guardrails = read_guardrails(treatment)

guardrail_names = set(control_guardrails.keys()) | set(treatment_guardrails.keys())
guardrail_deltas = {}
for name in sorted(guardrail_names):
    c_val = control_guardrails.get(name)
    t_val = treatment_guardrails.get(name)
    if c_val is None or t_val is None:
        continue
    guardrail_deltas[name] = float(t_val) - float(c_val)

out = {
    "experiment_id": manifest.get("experiment_id"),
    "window_start_utc": window_start_arg or raw.get("window_start_utc"),
    "window_end_utc": window_end_arg or raw.get("window_end_utc"),
    "kpi_control": read_number(control, ["kpi", "primary_kpi", "value", "metric", "conversion_rate"]),
    "kpi_treatment": read_number(treatment, ["kpi", "primary_kpi", "value", "metric", "conversion_rate"]),
    "sample_size_control": read_int(control, ["sample_size", "n", "count", "users"]),
    "sample_size_treatment": read_int(treatment, ["sample_size", "n", "count", "users"]),
    "guardrail_deltas": guardrail_deltas,
    "raw_guardrails": {
        "control": control_guardrails,
        "treatment": treatment_guardrails,
    },
    "manifest_posthog_drift_detected": len(drift_reasons) > 0,
    "manifest_posthog_drift_reasons": drift_reasons,
}

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n")
print(str(output_path))
PY
