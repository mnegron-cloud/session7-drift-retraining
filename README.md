# MLOPS

Running project for the **MLOps & Model Deployment** course (M2, 24 hours over 9 sessions).

You start from an already-trained credit card fraud classifier and turn it into a
production service: versioned data and models, CI/CD with an evaluation gate, a REST API
on Kubernetes, four-layer monitoring, drift detection with retraining, and canary
deployment with rollback. Every session extends the same repository: never restart from
scratch, since reproducibility is the point of the course.

The model is trained on the Kaggle
[Credit Card Fraud Detection](https://www.kaggle.com/datasets/mlg-ulb/creditcardfraud)
dataset: 284,807 card transactions over two days, of which 0.17 % are frauds. Building
a better model is out of scope; the course is about operating it.

Everything runs on your machine with Docker: no cloud account is needed.

**Contents:** [Prerequisites](#prerequisites) · [Installation](#installation) ·
[Devcontainer alternative](#alternative-devcontainer) · [Commands](#commands) · [Sessions](#sessions) · [Reference](#reference)

## Prerequisites

### Accounts

| Account | Why |
| ------- | --- |
| [GitHub](https://github.com) | Your group's repository, GitHub Actions (CI/CD), image registry (GHCR) |
| [Kaggle](https://www.kaggle.com) | Download the dataset. Free. Create an API token **before S1** (see [Installation](#3-kaggle-api-token)) |

### Tools

| Tool | Version | Used for |
| ---- | ------- | -------- |
| [uv](https://docs.astral.sh/uv/getting-started/installation/) | 0.10 or later | Python, dependencies and virtual environment |
| [Python](https://www.python.org/downloads/) | 3.14 | Installed by uv if missing (`uv python install 3.14`) |
| [Git](https://git-scm.com/downloads) | recent | Code versioning |
| [Docker](https://docs.docker.com/get-docker/) with Compose v2 | recent | Services, API image, Kubernetes cluster |
| GNU `make` | any | Shortcuts (`make help`). Preinstalled on macOS and Linux |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | 0.29 | Local Kubernetes cluster (from S5) |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | recent | Deployments, canary, rollback (from S5) |
| [GitHub CLI](https://cli.github.com) (`gh`) | recent | Trigger the retraining workflow (S7) |

On Windows, work inside WSL 2. Plan for 4 CPU cores, 16 GB of RAM and about 20 GB of
free disk space.

If the local installation fails (often on Windows), use the
[devcontainer alternative](#alternative-devcontainer): it only needs Docker.

These ports must be free: 3000, 5000, 8000, 8080, 8333, 8888, 9090, 9333 (see
[Services](#services)).

### Knowledge

Terminal use, Git and GitHub Actions basics, Docker basics (build, run, push), reading
and writing YAML, and the Python quality toolchain (virtual environments, tests, linting).

## Installation

Do steps 1 to 6 once, before S1. Steps 7 and 8 are done together in S1.

### 1. Clone the repository

```bash
git clone <your group's repository URL> mlops
cd mlops
```

### 2. Install the Python dependencies

```bash
uv sync          # creates .venv with the exact versions of uv.lock (and Python 3.14 if needed)
uv run pytest -q # quick check: all tests pass, no data needed
```

`uv run <command>` runs a command inside the project environment. The `make` shortcuts
already use it.

### 3. Kaggle API token

1. On kaggle.com, open **Settings**, section **API**, and create a new token.
2. Save it where the download tool looks for it:

    ```bash
    mkdir -p ~/.kaggle
    echo "<your token>" > ~/.kaggle/access_token
    chmod 600 ~/.kaggle/access_token
    ```

    Alternatives: `export KAGGLE_API_TOKEN=<token>` in your shell, or the legacy
    `~/.kaggle/kaggle.json` file (username + key).

Never commit the token: anyone who has it can use your Kaggle account.

### 4. Local configuration

```bash
cp .env.example .env    # S3 credentials, Grafana password, SeaweedFS version
```

The default values work as they are. `.env` is read by `docker compose` and is
git-ignored.

### 5. Start the services

```bash
make up                 # S3, MLflow, Postgres, Prometheus, Grafana
docker compose ps       # every service "running", except s3-init which exits once buckets exist
```

#### Services

| Service | URL | Role |
| ------- | --- | ---- |
| MLflow | http://localhost:5000 | Experiment tracking + Model Registry |
| S3 API | http://localhost:8333 | DVC remote + MLflow artifacts. API only: a browser gets "AccessDenied", that is expected |
| S3 file browser | http://localhost:8888/buckets/ | Browse the `dvc` and `mlflow` buckets |
| SeaweedFS status | http://localhost:9333 | Storage cluster status |
| API | http://localhost:8000/docs | Scoring API (from S4) |
| API in Kubernetes | http://localhost:8080 | Same API, served by kind (from S5) |
| Prometheus | http://localhost:9090 | Metrics and alerts (from S6) |
| Grafana | http://localhost:3000 | 4-layer dashboard, login admin / admin (from S6) |

### 6. DVC credentials

DVC needs the credentials of the local S3 (`S3_ACCESS_KEY` / `S3_SECRET_KEY` in `.env`,
`mlops` / `mlops-secret` by default):

```bash
uv run dvc remote modify --local storage access_key_id mlops
uv run dvc remote modify --local storage secret_access_key mlops-secret
```

They are written to `.dvc/config.local`, which is git-ignored. Without them, DVC fails
with `Unable to locate credentials`.

### 7. Download and version the data (S1)

```bash
make download                            # Kaggle -> data/raw/creditcard.csv (~150 MB)
uv run dvc add data/raw/creditcard.csv   # creates data/raw/creditcard.csv.dvc
git add data/raw/creditcard.csv.dvc data/raw/.gitignore
git commit -m "Track raw Kaggle dataset with DVC"
uv run dvc push                          # upload the file to the S3 remote
```

Only the small `.dvc` file goes to Git; the CSV itself goes to S3. A teammate gets the
exact same file with `uv run dvc pull`, without going through Kaggle.

### 8. Run the full pipeline (S1-S2)

```bash
make pipeline     # split -> train -> evaluate (dvc repro)
```

The new run appears in MLflow (http://localhost:5000). If the evaluation gate passes,
the model version gets the `staging` alias in the Model Registry.

## Alternative: devcontainer

Use it if the local installation does not work on your machine. A devcontainer is a
development environment described in the repository (`.devcontainer/`): your editor opens
the project *inside* a Docker container that already holds uv, Python 3.14, Docker,
kind, kubectl and the GitHub CLI. The only tool you need on your machine is Docker.

It is heavier than the local installation: Docker runs inside Docker, so give Docker
Desktop at least 8 GB of memory.

**With VS Code**

1. Install Docker and the VS Code extension
   [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers).
2. Open the repository folder in VS Code, then run the command
   **Dev Containers: Reopen in Container** (Cmd/Ctrl+Shift+P).
3. Wait for the first build (several minutes). The setup script installs the Python
   dependencies, kind, creates `.env` and sets the DVC credentials
   (installation steps 2, 4 and 6).
4. Set the Kaggle token (step 3): `export KAGGLE_API_TOKEN=<token>` in the container
   terminal, or save it in `~/.kaggle/access_token` inside the container.
5. Continue from step 5 (`make up`) in the VS Code terminal. The service ports are
   forwarded to your machine: the URLs of the [Services](#services) table work as is.

**With GitHub Codespaces**

On the repository page: **Code > Codespaces > Create codespace**. The same environment
runs on a GitHub machine and opens in the browser. It uses your account's free
Codespaces quota, which a 4-core machine consumes quickly: stop the codespace after
each session. Store the Kaggle token as a Codespaces secret named `KAGGLE_API_TOKEN`
(*GitHub Settings > Codespaces > Secrets*).

## Commands

`make help` lists them all. Each target is a shortcut for a `uv run ...` command shown in
the `Makefile`.

| Area | Command | What it does |
| ---- | ------- | ------------ |
| Environment | `make install` | Install the exact dependencies of `uv.lock` |
| | `make lock` | Update `uv.lock` after editing `pyproject.toml` |
| Services | `make up` / `make down` | Start / stop the Docker services (data is kept in volumes) |
| Data | `make download` | Download the Kaggle dataset into `data/raw/` |
| | `make data` | Chronological split into `data/processed/` |
| Model | `make pipeline` | Full DVC pipeline: split, train, evaluate |
| | `make train` | Train and register a new model version in MLflow |
| | `make evaluate` | Evaluation gate on the golden set; promotes to `@staging` if it passes |
| | `make export` | Download the `@staging` model into `./model` |
| Quality | `make test` / `make lint` | Tests / Ruff |
| Serving | `make api` | Run the API locally on port 8000 |
| | `make image VERSION=v1` | Build the `fraud-api:v1` Docker image, model included |
| | `make load` | One-minute load test with Locust (results in `reports/load_*`) |
| Kubernetes | `make kind-up` / `make kind-down` | Create / delete the local cluster |
| | `make kind-deploy VERSION=v1` | Load the image into kind and deploy it |
| Monitoring | `make simulate` | Send 500 realistic requests to the API |
| | `make simulate-drift` | Same, with data drift |
| | `make drift` | Drift tests on the API logs + Evidently report |

Useful DVC commands:

```bash
uv run dvc status -c        # what differs between your local cache and the S3 remote
uv run dvc diff HEAD~1      # data added, modified or deleted since the previous commit
uv run dvc dag              # pipeline graph
uv run dvc pull             # get the data versions referenced by the current commit
```

## Sessions

Each session adds one layer to the same repository. What you build in a session is
needed by the next one.

| Session | Topic | You leave with |
| ------- | ----- | -------------- |
| S1 | Introduction, reproducibility | Dataset versioned with DVC, services running |
| S2 | MLflow tracking and Model Registry | A reproducible model in `@staging` |
| S3 | CI/CD for ML | GitHub Actions workflows with an evaluation gate |
| S4 | Serving with FastAPI | A tested, containerised scoring API |
| S5 | Kubernetes and load | The API on kind, with a latency report |
| S6 | Four-layer monitoring | A Grafana dashboard and a firing alert |
| S7 | Drift and retraining | Drift-triggered retraining |
| S8 | Deployment patterns and rollback | A canary run, a timed rollback, an incident report |
| S9 | Project defence | — |

### S1 · Introduction and reproducibility

Why MLOps: what separates a notebook from a service in production. The three things to
version: code, data and model.

- Set up the repository and the services ([Installation](#installation), steps 1 to 6).
- Docker refresher: build and run an image.
- Download the dataset, version it with DVC, push it to S3 (step 7).
- Explore the S3 buckets and the `.dvc` file: what Git stores, what S3 stores.

**Deliverable:** the dataset tracked by DVC and pushed to the remote.

### S2 · MLflow: tracking and Model Registry

Experiment tracking (parameters, metrics, artifacts), the Model Registry and its aliases,
what a reproducible artifact must contain (preprocessing + model + signature).

- Run `make pipeline` and read the run in MLflow: parameters, metrics, tags (commit, data hash).
- Change a parameter in `params.yaml`, run again, compare the two runs.
- Promote the best version to `@staging`.
- Reproducibility test: a teammate retrains from a commit hash and the DVC data version.

**Deliverable:** a model version in `@staging` that a teammate can reproduce.

### S3 · CI/CD for ML

The shape of an ML pipeline: lint and tests, data validation, training, evaluation gate,
promotion, manual approval for production. Keeping CI costs under control.

- `ci.yml`: lint and tests on every push.
- `train.yml`: training, gate (ROC AUC and PR AUC on the golden set), Docker image,
  manual approval through a GitHub environment.
- Make the gate fail on purpose and watch the pipeline stop.

**Deliverable:** green workflows, and one run blocked by the gate.

### S4 · Serving with FastAPI

A served model is an API contract: input validation with Pydantic, health check, request
logging.

- Run `make api` and try `POST /predict` from http://localhost:8000/docs.
- Send invalid inputs and read the 422 errors.
- Check that the customer id is hashed in the logs (`logs/predictions.jsonl`).
- Build the image with `make image`: the model is inside.

**Deliverable:** a containerised API that serves the `@staging` model, with passing tests.

### S5 · Kubernetes and load

Kubernetes basics (pod, Deployment, Service, replicas, probes). The latency budget:
P95 ≤ 200 ms, and where the milliseconds go. Cost per 1,000 predictions. Batch and
streaming serving are presented but not practised.

- `make kind-up`, then `make kind-deploy`: the `/health` endpoint drives the probes.
- Load test with 1 replica, then 3 (`kubectl scale`), and compare P95 latencies.

**Deliverable:** a half-page report: P95 and throughput at 1 and 3 replicas, main
latency item, estimated cost.

### S6 · Four-layer monitoring

The four layers: infrastructure (latency, errors), input distribution, prediction
distribution, business outcome. Structured JSON logs. Alert versus runbook.

- Open the Grafana dashboard and read the four layers.
- `make simulate` for normal traffic, then `make simulate-drift`.
- Watch an alert fire in Prometheus and follow its runbook (`docs/runbooks.md`).

**Deliverable:** the dashboard with real traffic and at least one alert fired.

### S7 · Drift and retraining

Data drift, concept drift and label drift. Kolmogorov-Smirnov, chi-squared and PSI: what
each test can and cannot see. Retraining cadences: scheduled, drift-triggered,
performance-triggered, and the hybrid default.

- `make drift` on normal traffic, then on drifted traffic; read the Evidently report.
- Simulate concept drift (`--fraud-shift`): input tests stay silent, only recall drops.
- Wire PSI > 0.25 to the retraining workflow (`gh workflow run train.yml`).

**Deliverable:** a retraining run triggered by drift, visible in GitHub Actions (its MLflow lives on the runner, see the known limits of `docs/sessions/s7.md`).

### S8 · Deployment patterns and rollback

Canary, A/B testing, shadow mode, multi-armed bandits. Rollback discipline and
time-to-recovery. How to write an incident report.

- Deploy v2 next to v1 with `k8s/canary.yaml` (9 replicas of v1 for 1 of v2, about 10 % of traffic).
- Degrade v2 on purpose, then roll back and time it (target: under 5 minutes).
- Write a half-page incident report. Lab guide: `docs/sessions/s8.md`. Course wrap-up and defence instructions.

**Deliverable:** the rollback procedure and the incident report.

## Reference

### Data

| Column | Content |
| ------ | ------- |
| `Time` | Seconds elapsed since the first transaction of the dataset |
| `V1` … `V28` | Anonymised features (PCA components of the original data) |
| `Amount` | Transaction amount |
| `Class` | 1 = fraud, 0 = legitimate |

Columns are renamed once at ingestion (`time`, `v1`…`v28`, `amount`, `is_fraud`, see
`src/fraud/data.py`). The licence and the citation requested by the authors are on the
Kaggle page. Never commit the CSV to Git: it is versioned with DVC.

**Chronological split.** `make data` sorts by `time` and cuts the data into three
consecutive periods, never at random: the model learns from the past and is judged on
the future, as in production.

| File | Share | Use |
| ---- | ----- | --- |
| `data/processed/train.csv` | first 70 % | Training and choice of the decision threshold |
| `data/processed/golden.csv` | next 15 % | Frozen set for the evaluation gate |
| `data/processed/current.csv` | last 15 % | "Production" traffic replayed by `fraud.simulate` |

**Simulated traffic.** `fraud.simulate` replays `current.csv` against the API and sends
back part of the labels, as a fraud team would after investigation. With 0.17 % frauds,
500 requests hold about one fraud, so traffic is resampled to 2 % frauds by default
(`--fraud-share`). `--drift 0.8` creates data drift (amounts and some components move);
`--fraud-shift 0.7` creates concept drift (70 % of frauds copy legitimate transactions:
inputs barely change, only recall drops).

### Repository structure

```
src/fraud/
  data.py           Kaggle download, chronological split, simulated drifts
  features.py       preprocessing + model in a single sklearn pipeline
  train.py          training, MLflow logging, new version in the Registry
  evaluate.py       evaluation gate on the golden set -> @staging alias
  export_model.py   Registry -> ./model (baked into the Docker image)
  drift.py          K-S, chi-squared, PSI + Evidently report
  simulate.py       replays current.csv against the API, with drift and delayed labels
  api/              FastAPI: Pydantic, /health, Prometheus metrics, JSON logs
tests/              data, model, API, drift (on fake Kaggle-shaped data)
docker-compose.yml  shared services
Dockerfile          API image (model included)
docker/mlflow/      MLflow server image
k8s/                kind cluster, v1 Deployment, Service, v2 canary
infra/              S3 config, Prometheus (+ alerts), Grafana (provisioned dashboard)
loadtest/           Locust
.github/workflows/  ci.yml (lint + tests), train.yml (gate + image + approval)
.devcontainer/      alternative environment in Docker (see Alternative: devcontainer)
pyproject.toml      dependencies
uv.lock             exact versions of all dependencies (commit it)
dvc.yaml            reproducible pipeline
params.yaml         all parameters (split, model, gate, drift thresholds)
docs/runbooks.md    one section per alert
```

### CI secrets

GitHub Actions cannot reach the DVC remote, which runs on your machine. The `train.yml`
workflow therefore downloads the data from Kaggle: add a repository secret
`KAGGLE_API_TOKEN` (*Settings > Secrets and variables > Actions*). The `ci.yml` workflow
does not need it: the tests use a small fake file with the same columns.

For the manual approval step, create an environment named `production` with required
reviewers (*Settings > Environments*).

### Technical choices

- **SeaweedFS rather than MinIO**: MinIO has not published community Docker images since late 2025.
- **Two gate metrics**: ROC AUC ≥ 0.85 (syllabus) and PR AUC (average precision). With 0.17 % fraud, ROC AUC stays high even for a weak model; PR AUC is the one that drops.
- **Model baked into the image**: one image is one model version. The Kubernetes pod does not need to reach MLflow, and a rollback means redeploying the previous image.
- **skops serialization** (MLflow 3 default): only types declared as trusted are loaded back, unlike pickle.
- **Decision threshold chosen at training time**: the highest threshold that keeps 80 % recall on the validation slice (`train.min_recall`). It is stored with the model version and read by the API, so a new model never runs with the previous model's threshold. `DECISION_THRESHOLD` overrides it.
