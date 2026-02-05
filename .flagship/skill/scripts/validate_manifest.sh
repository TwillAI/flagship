#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  validate_manifest.sh --manifest <path> [--previous <path>] [--output <path>]

Description:
  Validate required experiment manifest fields and immutable field constraints.
EOF
}

manifest=""
previous=""
output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) manifest="$2"; shift 2 ;;
    --previous) previous="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$manifest" ]]; then
  echo "Missing required argument: --manifest" >&2
  usage
  exit 1
fi

python3 - "$manifest" "$previous" "$output" <<'PY'
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
previous_path = Path(sys.argv[2]) if sys.argv[2] else None
output_path = Path(sys.argv[3]) if sys.argv[3] else None

manifest = load_yaml(manifest_path) or {}
errors = []

required_root = [
    "experiment_id",
    "title",
    "objective",
    "primary_kpi",
    "guardrails",
    "max_budget_usd",
    "posthog",
    "feature_flag",
    "status",
    "created_at_utc",
]

for field in required_root:
    if field not in manifest:
        errors.append(f"Missing required field: {field}")

feature_flag = manifest.get("feature_flag", {}) or {}
for field in ["key", "control_variant", "treatment_variant"]:
    if field not in feature_flag:
        errors.append(f"Missing required field: feature_flag.{field}")

posthog = manifest.get("posthog", {}) or {}
if "project_id" not in posthog:
    errors.append("Missing required field: posthog.project_id")

cohorts = posthog.get("cohorts", {}) or {}
for field in ["control", "treatment"]:
    if field not in cohorts:
        errors.append(f"Missing required field: posthog.cohorts.{field}")

allowed_status = {"draft", "active", "paused", "winner_selected", "completed", "stopped"}
status = manifest.get("status")
if status not in allowed_status:
    errors.append(f"Invalid status: {status}. Allowed: {sorted(allowed_status)}")

budget = manifest.get("max_budget_usd")
if budget is None:
    errors.append("max_budget_usd cannot be null")
else:
    try:
        if float(budget) <= 0:
            errors.append("max_budget_usd must be greater than 0")
    except (TypeError, ValueError):
        errors.append("max_budget_usd must be numeric")

if previous_path:
    prev = load_yaml(previous_path) or {}
    for immutable_key in ["objective", "primary_kpi", "max_budget_usd"]:
        if prev.get(immutable_key) != manifest.get(immutable_key):
            errors.append(
                f"Immutable field changed: {immutable_key} "
                f"(old={prev.get(immutable_key)!r}, new={manifest.get(immutable_key)!r})"
            )

result = {
    "valid": len(errors) == 0,
    "errors": errors,
    "manifest_path": str(manifest_path),
}

payload = json.dumps(result, indent=2, sort_keys=True) + "\n"

if output_path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(payload)

sys.stdout.write(payload)
sys.exit(0 if result["valid"] else 1)
PY
