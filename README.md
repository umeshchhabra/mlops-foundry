# MLOps Foundry

MLOps Foundry is a small, practical MLOps platform that runs on your own machine. It is meant for learning and experimenting, but it follows the same shape as a real platform: GitOps manages infrastructure, training records experiments, object storage keeps artifacts, and KServe exposes models.

Nothing here needs a cloud account. Docker runs Kind, Kind runs Kubernetes, and your data stays on the machine running the cluster.

## What is running

| Service | Why it is here |
| --- | --- |
| Argo CD | Watches this repository and applies infrastructure changes to Kubernetes. |
| Helm | Supplies upstream Airflow, Prometheus, Grafana, KServe, and cert-manager charts. |
| PostgreSQL | Holds MLflow and Airflow metadata. |
| MinIO | Local S3-compatible storage for artifacts, Airflow logs, models, and backups. |
| MLflow | Lets you browse experiments, metrics, parameters, and model artifacts. |
| Airflow | Runs the training workflow. |
| Feast | A small local feature-store starter for learning feature definitions and materialization. |
| KServe | Loads a model from MinIO and serves prediction requests in Kubernetes. |
| Prometheus and Grafana | Collect and visualize platform metrics. |

The usual flow is:

```text
DVC / Feast export -> Airflow -> MLflow + MinIO -> KServe -> prediction
                         |                         |
                         +---- Prometheus/Grafana -+
```

The default training DAG also works without a dataset export by using Iris. When a DVC/Feast CSV is placed on the Airflow DAG volume, it records that dataset source in MLflow and uses it instead.

## Open the platform

| Service | Address | Notes |
| --- | --- | --- |
| Argo CD | http://localhost:8080 | GitOps status and sync view. |
| MLflow | http://localhost:5000 | Experiments, runs, metrics, and artifacts. |
| Prometheus | http://localhost:9002 | Metrics queries. |
| Grafana | http://localhost:9003 | Dashboards; user is `admin`. |
| MinIO console | http://localhost:9001 | Buckets and artifacts; user is `mlops-admin`. |
| MinIO S3 API | http://localhost:9000 | Used by applications, not normally a browser page. |
| Airflow | http://localhost:8090 | Training DAGs; user is `admin`. |

Passwords are created only in Kubernetes. Retrieve them locally instead of putting them in a shell history, document, or chat:

```powershell
# Grafana
kubectl -n mlops get secret platform-secrets -o jsonpath="{.data.GRAFANA_ADMIN_PASSWORD}" |
  ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }

# MinIO
kubectl -n mlops get secret platform-secrets -o jsonpath="{.data.MINIO_ROOT_PASSWORD}" |
  ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
```

The KServe example is intentionally local-only. Run this in a separate terminal, then call the prediction API on `localhost:8081`:

```powershell
kubectl -n models port-forward service/sklearn-iris-predictor 8081:80
```

## First setup on Windows

Install Docker Desktop (Linux containers enabled), Git, Kind, kubectl, Helm, and PowerShell 7. Give Docker Desktop roughly 8 GB of memory. Then clone the repository and run:

```powershell
git clone https://github.com/umeshchhabra/mlops-foundry.git
cd mlops-foundry
pwsh ./scripts/bootstrap-kind-windows.ps1 -DataDir C:\mlops-data
```

The script creates the Kind cluster, persistent-volume claims, local runtime secrets, and the MLflow image. It does not install Argo CD, because that is the point where you supply a read-only GitHub token for this private repo.

```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd wait --for=condition=Available deployment/argocd-server --timeout=5m
pwsh ./scripts/configure-argocd-repo.ps1
pwsh ./scripts/configure-airflow-secrets.ps1
kubectl apply -f infra/bootstrap/bootstrap-project.yaml
kubectl apply -f infra/bootstrap/root-application.yaml
pwsh ./scripts/configure-kserve-storage.ps1
pwsh ./health/check-stack.ps1
```

Wait a few minutes after applying the root Application; Argo CD installs and reconciles the chart-backed services in dependency order. If an address does not open, run the health check first and then inspect the matching Argo CD Application.

## First setup on Linux

Install Docker, Git, Kind, kubectl, Helm, OpenSSL, and PowerShell 7. Use a 64-bit host with at least 8 GB RAM; an SSD-backed data directory is strongly recommended.

```bash
git clone https://github.com/umeshchhabra/mlops-foundry.git
cd mlops-foundry
MLOPS_DATA_DIR=/mnt/mlops-data ./scripts/bootstrap-kind-linux.sh
```

Then install and bootstrap Argo CD exactly as above. PowerShell commands work on Linux as long as PowerShell 7 is installed:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd wait --for=condition=Available deployment/argocd-server --timeout=5m
pwsh ./scripts/configure-argocd-repo.ps1
pwsh ./scripts/configure-airflow-secrets.ps1
kubectl apply -f infra/bootstrap/bootstrap-project.yaml
kubectl apply -f infra/bootstrap/root-application.yaml
pwsh ./scripts/configure-kserve-storage.ps1
pwsh ./health/check-stack.ps1
```

For Raspberry Pi details and architecture checks, see [`docs/linux-kind.md`](docs/linux-kind.md).

## A short day-to-day guide

Check the platform whenever you change infrastructure:

```powershell
pwsh ./health/check-stack.ps1
```

Run the Airflow DAG `home_train_and_log` from the Airflow UI. It creates an MLflow run, uploads a model artifact to MinIO, and records the artifact URI. Promote a finished run to KServe with:

```powershell
pwsh ./scripts/promote-mlflow-run.ps1 -RunId <mlflow-run-id>
kubectl apply -f infra/platform/kserve/models/promoted-inferenceservice.yaml
```

For DVC/Feast input, provide a CSV at `/opt/airflow/dags/data/training.csv` with columns `feature_0,feature_1,feature_2,feature_3,target`. The training run will log the source as a DVC input. The small Feast starter lives in [`feature-store/README.md`](feature-store/README.md).

## Useful deeper references

- [`docs/airflow.md`](docs/airflow.md) — Airflow deployment and secret setup.
- [`docs/versioning.md`](docs/versioning.md) — dataset, artifact, and model naming.
- [`infra/platform/kserve/README.md`](infra/platform/kserve/README.md) — KServe example and prediction request.
- [`infra/platform/backup/README.md`](infra/platform/backup/README.md) — backups and restore helper.
- [`health/README.md`](health/README.md) — what the health check validates.

## A note on scope

This is a complete local learning platform, not an internet-facing production deployment. TLS/ingress, external backup copies, HA, and advanced identity controls are deliberately left out. Keep it on a trusted home or lab network.
