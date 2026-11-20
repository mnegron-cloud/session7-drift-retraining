# Session 7: Drift and retraining, solutions

Lab guide: [docs/sessions/s7.md](docs/sessions/s7.md). Course README: [README.md](README.md).

Windows (Git Bash): there is no `make`, so run the `uv run ...` line of each Makefile target.
`export UV_LINK_MODE=copy` first (OneDrive blocks uv's hardlinks). Seeds are fixed (`--seed`)
so every number below can be reproduced.

## 0. Setup

```bash
uv sync && uv run pytest -q          # 18 passed
uv run python -m fraud.reference     # reference: 20000 rows
```

Terminal A (the API, lab threshold):

```bash
DECISION_THRESHOLD=0.005 PREDICTION_LOG_PATH=logs/predictions.jsonl MODEL_URI=model \
  uv run uvicorn fraud.api.main:app --port 8000
```

## 1-4. The four runs

```bash
uv run python -m fraud.simulate --n 500 --seed 1                    # 1. baseline
uv run python -m fraud.simulate --n 500 --drift 0.8 --seed 2        # 2. data drift
uv run python -m fraud.simulate --n 500 --fraud-shift 0.7 --seed 3  # 3. concept drift
uv run python -m fraud.simulate --n 500 --amount-scale 100 --seed 4 # 4. unit bug
# after each: uv run python -m fraud.drift --current logs/predictions.jsonl ; echo $?
# then mv logs/predictions.jsonl logs/<name>.jsonl
```

| Run | Max PSI | Top feature | Chi² (amount band) | Exit | Drift type |
| --- | ------- | ----------- | ------------------ | ---- | ---------- |
| Baseline | 0.035 | v20 | p = 0.99 | 0 | none |
| Data drift | **2.214** | v1 (then v2, v4, v3, amount) | p = 8e-29 | **3** | data drift, P(X) |
| Concept drift | 0.034 | v22 | p = 0.71 | 0 | concept drift, P(y\|X) |
| Unit bug | **5.847** | amount only | p ≈ 0 | **3** | not drift: upstream bug |

Reports kept in `reports/`: `baseline.json`, `data_drift.json`, `concept_drift.json`,
`unit_bug.json`, plus Evidently `baseline.html` and `data_drift.html`.

**2.3 K-S vs PSI (v1, data drift).** K-S p = 1e-77 only says the sample is large enough to be
sure the distributions differ. PSI = 2.21 says how *much* they differ (> 0.25 = major shift).
A tiny p-value with a small PSI means a big sample, not a big change.

**2.4** This is **data drift**: P(X) moved (v1, v2, v4, v3, amount shifted) while the link
between inputs and fraud, P(y|X), did not change.

**3.1 Prediction:** no input test fires; only the outcome layer (recall) can see it. Confirmed: exit 0.

**3.4 RecallDrop.** Prometheus was not running (Docker off), and the 500-request run carries
only 2 labelled frauds: **not enough labels** (the alert needs ≥ 5 in 15 min). A larger labelled
run (1,000 requests, 10 % frauds, all labels returned, `--feedback-rate 1.0`) shows the effect
from the logs directly:

| Traffic | Labelled frauds | Recall | Max PSI |
| ------- | --------------- | ------ | ------- |
| Normal | 100 | 0.58 | 0.035 |
| `--fraud-shift 0.7` | 100 | **0.20** | 0.035 |

**3.5** No input test can see concept drift because the inputs have the same distribution;
only the link between inputs and frauds changed, and only labels reveal that link.

**4.3 Diagnosis.** Median amount = **1,500** vs 15.90 in the baseline (×~100), every other
feature is stable, and 13 requests were rejected (422: amount > 50,000 € limit of the schema).
This is the same transactions sent in cents, not real drift. Per the runbook (Drift, step 2),
an upstream bug is fixed at the source: **no retraining**. Retraining on it would teach the
model wrong amounts.

**4.4 Fix.** Fix the sender (the upstream service that builds the payload) to send euros, and
add a contract check at the API boundary. Verify by replaying traffic: median amount back near
16, amount PSI < 0.1, `fraud.drift` exit 0, zero 422s.

## 5. Trigger

[retrain_on_drift.sh](retrain_on_drift.sh) chains on exit code 3 only, never `||` (any other
failure, such as a missing file, would also start a training run).

```bash
bash -n retrain_on_drift.sh                         # no output: syntax OK
CURRENT=logs/baseline.jsonl bash retrain_on_drift.sh # max PSI = 0.035 -> ok, no workflow
bash retrain_on_drift.sh                             # logs/drift.jsonl -> reason=drift PSI 2.214
gh run list --workflow train.yml --limit 3 && gh run watch
```

Repo: https://github.com/mnegron-cloud/session7-drift-retraining (environment `production`
with a required reviewer). The trigger printed `max PSI = 2.214 -> RETRAIN` and
`reason=drift PSI 2.214`, and `gh` created the run:
[Actions run 44714125745](https://github.com/mnegron-cloud/session7-drift-retraining/actions/runs/44714125745)
(event `workflow_dispatch`). The `train` job passed data, training, gate and export; `publish`
was **left waiting for approval** in `production` on purpose: the retrained model is identical
to the one already served (Part 6), so publishing a new image would change nothing. The earlier run started by the first push was cancelled
so the drift run was the one under test (both share the `train` concurrency group).

## 6. What the retraining changed, and what it did not

| | Served before | Drift-triggered retraining |
| --- | --- | --- |
| Version | `fraud-classifier` v2 (local MLflow) | v1 (SQLite MLflow on the runner) |
| Decision threshold | 0.000702 | 0.000702 |
| Golden ROC AUC / PR AUC | — | 0.891 / 0.529 |
| Golden recall | — | 0.91 |
| Gate (≥ 0.85 / ≥ 0.50) | — | **pass** |

The version numbers differ only because there are two registries (local v2, runner v1); the
threshold is identical and the push-triggered run before it gave exactly the same metrics.
The new model is the same model: retraining changed the run id, nothing else.

**6.3** The training reads `data/processed/train.csv`, the same chronological split. It learned
**nothing new** from the drifted traffic: same data, same params, same seed, so the same model.
The run proves the pipeline works, not that the model adapted.

**6.4** The training set should include the recent production window **with confirmed labels**:
the `feedback` events (`actual_fraud`) joined with their `prediction` events from the API logs.
Export them on a schedule to a labelled CSV, version it with DVC and push it to the S3 remote;
the CI runner pulls it with `dvc pull` (needs a remote reachable from GitHub and credentials as
Actions secrets, not the localhost SeaweedFS of this lab).

## 7. Training split as reference (optional)

```bash
uv run python -m fraud.drift --reference data/processed/train.csv --current logs/baseline.jsonl
```

Exit **3** on normal traffic: v1 PSI 0.93, v3 0.88, v28 0.67. This measures the gap between two
**periods** of the dataset (the chronological split), not a change in the traffic served now.
That is why the reference is a healthy production window.

## Known limits

- Same data, same model: CI retraining reproduces the pipeline, nothing adapts.
- Two registries: the CI run uses SQLite MLflow on the runner; evidence is the Actions summary
  and the `model` / `reports` artifacts, not http://localhost:5000.
- Exit code 3 says drift, not cause: the unit bug gives the same code (Part 4).
- The reference is a choice: the train split gives the opposite verdict (Part 7).
- PSI thresholds 0.1 / 0.25 are rules of thumb, and PSI depends on the number of bins (10 here).
