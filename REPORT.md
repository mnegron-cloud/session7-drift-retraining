# Session 7 report: drift and retraining

Fraud API, model `fraud-classifier` v2 (threshold 0.000702, served with the lab threshold 0.005).
Reference: 20,000 rows of healthy production traffic (`data/processed/reference.csv`).
Tests: K-S and PSI (10 quantile bins) per feature, chi-squared on amount bands.
Thresholds: PSI 0.1 = alert, PSI 0.25 = retrain (exit code 3). Details and commands: [SOLUTIONS.md](SOLUTIONS.md).

## 1. Drift reports (500 requests each)

| Run | Max PSI (feature) | K-S | Chi² amount | Exit | Drift type |
| --- | ----------------- | --- | ----------- | ---- | ---------- |
| Baseline | 0.035 (v20) | no p < 0.01 | p = 0.99 | 0 | none |
| Data drift (`--drift 0.8`) | **2.21 (v1)**, v2 1.14, v4 1.11, v3 0.77, amount 0.32 | p down to 1e-101 | p = 8e-29 | **3** | **data drift**: P(X) moved, P(y\|X) unchanged |
| Concept drift (`--fraud-shift 0.7`) | 0.034 (v22) | no p < 0.01 | p = 0.71 | 0 | **concept drift**: P(y\|X) moved, inputs did not |

K-S p-values show that a difference is *certain*; PSI shows how *large* it is. Concept drift is
invisible to every input test, because only the link between inputs and frauds changed, and
only labels reveal it. With labels (100 confirmed frauds), recall fell from **0.58 to 0.20** and
the Prometheus alert `RecallDrop` went pending and then **firing** (value 0.20), while PSI stayed at 0.035.
With the guide's 500 requests there were too few labels (0 frauds confirmed): the alert stayed inactive.

## 2. The unit-bug case: no retraining

`--amount-scale 100` gives exit code **3** (amount PSI 5.85), the same verdict as real drift.
Diagnosis: median amount **1,500** vs 15.90 in the baseline (×100), every other feature stable,
13 requests rejected by the schema (amount > 50,000 €). These are the same transactions sent in
cents. Following the runbook (Drift, step 2), this is fixed at the source (the sender of the
payload), not by retraining. Retraining would teach the model the wrong unit. Check after the fix:
median amount back near 16, amount PSI < 0.1, exit code 0, no 422 errors.

## 3. Drift-triggered retraining

`retrain_on_drift.sh` starts `train.yml` only on exit code 3 (never `||`, which would also start
it on any error). It stays silent on the baseline (exit 0). On the data-drift log it ran
`gh workflow run train.yml -f reason="drift PSI 2.214"`:
[run 44714125745](https://github.com/mnegron-cloud/session7-drift-retraining/actions/runs/44714125745),
summary title `Retraining: drift PSI 2.214`. Data, training, gate and export passed:
golden ROC AUC **0.891** (≥ 0.85), PR AUC **0.529** (≥ 0.50), recall 0.91, gate **pass**.
The `publish` job was left waiting for approval in `production` on purpose (see 4).

## 4. What the retraining changed, and what it did not

The new model has the same decision threshold (0.000702) and exactly the same metrics as the
run before it. It is version 1 only because the runner has its own SQLite MLflow, separate from
the local registry (v2). The training reads `data/processed/train.csv`, the same chronological
split, so it learned **nothing new** from the drifted traffic: the pipeline is proven, but nothing adapted.

**Open question.** Training should add the recent production window with confirmed labels:
the API's `feedback` events (`actual_fraud`) joined with their `prediction` events. Export them on
a schedule to a labelled CSV, version it with DVC and push it to a remote that the CI runner can
reach (cloud S3 with credentials as Actions secrets, not the localhost SeaweedFS), then `dvc pull` in the workflow.

## 5. Known limits

- Same data, same model: the retraining reproduces the pipeline; it does not adapt.
- Two registries: the CI model lives in the runner's MLflow; evidence is the Actions summary and artifacts.
- Exit code 3 says drift, not cause: the unit bug gives the same code.
- The reference is a choice: against `train.csv`, normal traffic gives exit 3 (v1 0.93, v3 0.88,
  v28 0.67). That gap is between two periods of the dataset, not a change in current traffic.
- PSI 0.1 / 0.25 are rules of thumb, and PSI depends on the number of bins (10 here); with
  500 requests, about 50 per bin, small PSI values (< 0.05) are mostly sampling noise.
