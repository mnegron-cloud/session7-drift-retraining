#!/usr/bin/env bash
# Drift-triggered retraining (S7, part 5). Starts train.yml only on exit code 3 (PSI > psi_retrain),
# never with ||: any other failure of the drift command must not start a training run.
# Run it only after diagnosing the cause (a unit bug also gives exit code 3).
CURRENT=${CURRENT:-logs/drift.jsonl}
uv run python -m fraud.drift --current "$CURRENT"
code=$?
if [ "$code" -eq 3 ]; then
  psi=$(uv run python -c 'import json; print(round(json.load(open("reports/drift.json"))["max_psi"], 3))')
  echo "reason=drift PSI $psi"
  gh workflow run train.yml -f reason="drift PSI $psi"
fi
