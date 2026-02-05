#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  evaluate_policy.sh \
    --manifest <path> \
    --metrics <path> \
    --budget <path> \
    --recommendation <path|literal> \
    --output <path> \
    [--min-sample <n>] \
    [--guardrail-max-degradation <decimal>]

Description:
  Evaluate deterministic policy gates and emit final Flagship decision payload.
EOF
}

manifest=""
metrics=""
budget=""
recommendation=""
output=""
min_sample="500"
guardrail_max_degradation="2.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) manifest="$2"; shift 2 ;;
    --metrics) metrics="$2"; shift 2 ;;
    --budget) budget="$2"; shift 2 ;;
    --recommendation) recommendation="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --min-sample) min_sample="$2"; shift 2 ;;
    --guardrail-max-degradation) guardrail_max_degradation="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$manifest" || -z "$metrics" || -z "$budget" || -z "$recommendation" || -z "$output" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

python3 - "$manifest" "$metrics" "$budget" "$recommendation" "$output" "$min_sample" "$guardrail_max_degradation" <<'PY'
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
metrics_path = Path(sys.argv[2])
budget_path = Path(sys.argv[3])
recommendation_arg = sys.argv[4]
output_path = Path(sys.argv[5])
min_sample = int(sys.argv[6])
guardrail_max = float(sys.argv[7])

manifest = load_yaml(manifest_path) or {}
metrics = json.loads(metrics_path.read_text())
budget = json.loads(budget_path.read_text())

rec_path = Path(recommendation_arg)
if rec_path.exists():
    recommendation_raw = json.loads(rec_path.read_text())
else:
    recommendation_raw = {
        "agent_recommendation": recommendation_arg,
        "confidence": 0.5,
        "reasoning_summary": "Literal recommendation input",
    }

allowed_recommendations = {"ITERATE", "KEEP_TREATMENT", "KEEP_CONTROL", "HOLD", "STOP"}
fail_reasons = []

budget_before = float(
    budget.get("budget_remaining_usd", budget.get("remaining_usd", budget.get("budget_before_usd", 0.0)))
)
if budget_before <= 0:
    fail_reasons.append("Budget hard stop: remaining budget <= 0")

control_n = int(metrics.get("sample_size_control", 0))
treatment_n = int(metrics.get("sample_size_treatment", 0))
if control_n < min_sample or treatment_n < min_sample:
    fail_reasons.append(
        f"Minimum sample not met: control={control_n}, treatment={treatment_n}, required={min_sample}"
    )

guardrail_config = {}
for entry in manifest.get("guardrails", []) or []:
    if not isinstance(entry, dict):
        continue
    name = entry.get("name")
    if not name:
        continue
    guardrail_config[name] = {
        "direction": entry.get("direction", "lower_is_better"),
        "max_degradation_pct": float(entry.get("max_degradation_pct", guardrail_max)),
    }

raw_guardrails = metrics.get("raw_guardrails", {}) or {}
raw_control = raw_guardrails.get("control", {}) or {}
raw_treatment = raw_guardrails.get("treatment", {}) or {}

for key, delta in (metrics.get("guardrail_deltas", {}) or {}).items():
    cfg = guardrail_config.get(
        key,
        {"direction": "lower_is_better", "max_degradation_pct": guardrail_max},
    )
    direction = cfg["direction"]
    limit_pct = float(cfg["max_degradation_pct"])

    c_val = raw_control.get(key)
    t_val = raw_treatment.get(key)
    if c_val is not None and t_val is not None:
        c_val = float(c_val)
        t_val = float(t_val)
        signed_delta = t_val - c_val
        pct_delta = abs((signed_delta / c_val) * 100.0) if c_val != 0 else (100.0 if signed_delta != 0 else 0.0)

        if direction == "lower_is_better" and signed_delta > 0 and pct_delta > limit_pct:
            fail_reasons.append(
                f"Guardrail breach: {key} degraded by {pct_delta:.4f}% (limit={limit_pct:.4f}%)"
            )
        elif direction == "higher_is_better" and signed_delta < 0 and pct_delta > limit_pct:
            fail_reasons.append(
                f"Guardrail breach: {key} degraded by {pct_delta:.4f}% (limit={limit_pct:.4f}%)"
            )
        elif direction not in {"lower_is_better", "higher_is_better"} and pct_delta > limit_pct:
            fail_reasons.append(
                f"Guardrail breach: {key} moved by {pct_delta:.4f}% (limit={limit_pct:.4f}%)"
            )
    else:
        if float(delta) > guardrail_max:
            fail_reasons.append(
                f"Guardrail breach: {key} delta={float(delta):.6f} exceeds fallback limit={guardrail_max:.6f}"
            )

agent_recommendation = str(recommendation_raw.get("agent_recommendation", "HOLD")).upper()
if agent_recommendation not in allowed_recommendations:
    fail_reasons.append(f"Invalid recommendation: {agent_recommendation}")
    agent_recommendation = "HOLD"

if budget_before <= 0:
    final_action = "STOP"
elif fail_reasons:
    final_action = "HOLD"
else:
    final_action = agent_recommendation

policy_result = "PASS" if not fail_reasons else "FAIL"

payload = {
    "experiment_id": manifest.get("experiment_id"),
    "window_start_utc": metrics.get("window_start_utc"),
    "window_end_utc": metrics.get("window_end_utc"),
    "kpi_control": metrics.get("kpi_control"),
    "kpi_treatment": metrics.get("kpi_treatment"),
    "guardrail_deltas": metrics.get("guardrail_deltas", {}),
    "agent_recommendation": agent_recommendation,
    "policy_result": policy_result,
    "policy_fail_reasons": fail_reasons,
    "final_action": final_action,
    "budget_before_usd": budget_before,
    "budget_after_usd": budget_before,
    "confidence": float(recommendation_raw.get("confidence", 0.5)),
}

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
print(str(output_path))
PY
