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

variants = raw.get("variants", {})
control = variants.get("control", {})
treatment = variants.get("treatment", {})

manifest_feature_flag = manifest.get("feature_flag", {}) or {}
manifest_posthog = manifest.get("posthog", {}) or {}
raw_experiment = raw.get("experiment", {}) or raw.get("posthog_experiment", {}) or {}

def read_nested(data, dotted):
    cur = data
    for key in dotted.split("."):
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur

def read_raw_experiment(*candidates):
    for key in candidates:
        if "." in key:
            value = read_nested(raw_experiment, key)
        else:
            value = raw_experiment.get(key)
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

control_guardrails = control.get("guardrails", {}) or {}
treatment_guardrails = treatment.get("guardrails", {}) or {}

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
    "kpi_control": float(control.get("kpi", 0.0)),
    "kpi_treatment": float(treatment.get("kpi", 0.0)),
    "sample_size_control": int(control.get("sample_size", 0)),
    "sample_size_treatment": int(treatment.get("sample_size", 0)),
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
