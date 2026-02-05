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
}

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n")
print(str(output_path))
PY
