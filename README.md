# MLOps Foundry

MLOps Foundry is a small, practical MLOps platform that runs on your own machine. It provides shared infrastructure for development repositories: GitOps, orchestration, experiment tracking, object storage, model serving APIs, and observability.

Nothing here needs a cloud account. Docker runs Kind, Kind runs Kubernetes, and your data stays on the machine running the cluster.

## What is running

| Service | Why it is here |
| --- | --- |
| Argo CD | Watches this repository and applies infrastructure changes to Kubernetes. |
| Helm | Supplies upstream Airflow, Prometheus, Grafana, KServe, and cert-manager charts. |
| PostgreSQL | Holds MLflow and Airflow metadata. |
| MinIO | Local S3-compatible storage for artifacts, Airflow logs, models, and backups. |
| MLflow | Lets you browse experiments, metrics, parameters, and model artifacts. |
| Airflow | Runs DAGs supplied by development repositories. |
| KServe | Provides Kubernetes APIs and controllers for model-serving workloads. |
| Prometheus and Grafana | Collect and visualize platform metrics. |

Development repositories integrate with the platform like this:

```text
Development repository -> Airflow -> MLflow + MinIO -> KServe -> prediction
                         |                         |
                         +---- Prometheus/Grafana -+
```

Training code, feature definitions, DAGs, datasets, and model-serving manifests belong in their development repositories rather than this infrastructure repository.

The current development workload lives in
[`mlops-foundary-online-retail`](https://github.com/umeshchhabra/mlops-foundary-online-retail).

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
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd wait --for=condition=Available deployment/argocd-server --timeout=5m
pwsh ./scripts/configure-argocd-local.ps1
pwsh ./scripts/configure-argocd-repo.ps1
pwsh ./scripts/configure-airflow-secrets.ps1
kubectl apply -f infra/bootstrap/bootstrap-project.yaml
kubectl apply -f infra/bootstrap/root-application.yaml
pwsh ./health/wait-for-stack.ps1
pwsh ./health/check-stack.ps1
```

The wait helper allows up to 15 minutes for Argo CD to install and reconcile the chart-backed services. If an address does not open, run the health check and inspect the matching Argo CD Application.

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
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd wait --for=condition=Available deployment/argocd-server --timeout=5m
pwsh ./scripts/configure-argocd-local.ps1
pwsh ./scripts/configure-argocd-repo.ps1
pwsh ./scripts/configure-airflow-secrets.ps1
kubectl apply -f infra/bootstrap/bootstrap-project.yaml
kubectl apply -f infra/bootstrap/root-application.yaml
pwsh ./health/wait-for-stack.ps1
pwsh ./health/check-stack.ps1
```

For Raspberry Pi details and architecture checks, see [`docs/linux-kind.md`](docs/linux-kind.md).

## A short day-to-day guide

Check the platform whenever you change infrastructure:

```powershell
pwsh ./health/check-stack.ps1
```

Connect a development repository by supplying its Airflow DAGs, MLflow client
configuration, feature-store definitions, and KServe workload manifests. The
platform remains independent of any one dataset or model.

## Useful deeper references

- [`docs/airflow.md`](docs/airflow.md) — Airflow deployment and secret setup.
- [`infra/platform/kserve/README.md`](infra/platform/kserve/README.md) — KServe platform boundary.
- [`infra/platform/backup/README.md`](infra/platform/backup/README.md) — backups and restore helper.
- [`health/README.md`](health/README.md) — what the health check validates.

## A note on scope

This is a complete local learning platform, not an internet-facing production deployment. TLS/ingress, external backup copies, HA, and advanced identity controls are deliberately left out. Keep it on a trusted home or lab network.
