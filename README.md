# MLOps Foundry

MLOps Foundry is a practical MLOps platform that runs on your own machine. It
provides shared infrastructure for development repositories: GitOps,
orchestration, experiment tracking, object storage, model-serving APIs, and
observability.

Nothing here needs a cloud account. Docker runs Kind, Kind runs Kubernetes, and
your data stays on the machine running the cluster.

## What this platform does for you

MLOps Foundry is a shared MLOps platform: Kubernetes/GitOps, MinIO,
PostgreSQL, Redis, Airflow, MLflow, KServe, Prometheus, and Grafana. It owns
platform reliability, storage, observability, backups, access boundaries, and
service availability—not a model, dataset, DAG, or deployed application.

When a new training project needs support, the platform team provisions only
the requested shared-service resources, such as a dedicated MinIO bucket, an
MLflow experiment, an Airflow pool, and Feast configuration. Training teams
keep their pipelines and model workloads in their own repositories, allowing
this platform to support many independent projects without being tied to one.

## What is running

| Service | Why it is here |
| --- | --- |
| Argo CD | Watches this repository and applies infrastructure changes to Kubernetes. |
| Helm | Supplies upstream Airflow, Prometheus, Grafana, KServe, and cert-manager charts. |
| PostgreSQL | Holds MLflow and Airflow metadata. |
| MinIO | Local S3-compatible storage for artifacts, Airflow logs, models, Feast data, and backups. |
| Redis | Persistent shared online feature store, logically separated by Feast project. |
| MLflow | Lets you browse experiments, metrics, parameters, and model artifacts. |
| Airflow | Runs DAGs supplied by development repositories. |
| KServe | Provides Kubernetes APIs and controllers for model-serving workloads. |
| Prometheus and Grafana | Collect and visualize platform metrics. |

Development repositories integrate with the platform like this:

~~~text
Development repository -> Airflow -> MLflow + MinIO -> KServe -> prediction
                         |              |
                         +-> Feast -> Redis
                         |              |
                         +------ Prometheus/Grafana
~~~

The infrastructure repository owns the shared platform: Kubernetes setup,
GitOps, storage, Redis, MinIO, PostgreSQL, Airflow, MLflow, KServe, monitoring,
network policies, backups, and runtime-secret bootstrap. It deliberately does
not contain a model, dataset, training DAG, feature definition, or deployed
Feast server for any individual project.

Each development repository is a tenant of that platform. It supplies its own
training code, Airflow DAGs, feature definitions, and KServe workloads. For
Feast, onboarding creates a separate MinIO bucket per project, while Redis
remains shared and Feast uses the project name to separate online feature data.

## Open the platform

| Service | Address | Notes |
| --- | --- | --- |
| Argo CD | http://localhost:8080 | GitOps status and sync view. |
| MLflow | http://localhost:5000 | Experiments, runs, metrics, and artifacts. |
| Prometheus | http://localhost:9002 | Metrics queries. |
| Grafana | http://localhost:9003 | Dashboards; user is admin. |
| MinIO console | http://localhost:9001 | Buckets and artifacts; user is mlops-admin. |
| MinIO S3 API | http://localhost:9000 | Used by applications, not normally a browser page. |
| Airflow | http://localhost:8090 | Training DAGs; user is admin. |

Passwords are created only in Kubernetes. Retrieve all platform usernames and
passwords locally instead of putting them in a shell history, document, or
chat:

~~~bash
./scripts/show-platform-credentials.sh
~~~

The helper reads Argo CD, Airflow, Grafana, MinIO, Redis, and PostgreSQL
credentials from the current cluster. It prints them only to your terminal and
does not write them to disk. MLflow and Prometheus currently have no login.

## First setup

The repository has one operator interface: Bash for lifecycle commands and
Python 3 for structured Kubernetes checks. It runs unchanged on Linux or in a
WSL 2 distribution on a Windows host.

### Windows host with WSL 2

Install Docker Desktop with WSL integration enabled. In your Linux
distribution, install Git, Docker CLI access, Kind, kubectl, Helm, and Python
3. Give Docker Desktop roughly 8 GB of memory and clone the
repository into the Linux filesystem rather than a mounted drive.

~~~bash
git clone https://github.com/umeshchhabra/mlops-foundry.git
cd mlops-foundry
MLOPS_DATA_DIR="$HOME/.local/share/mlops-foundry" ./scripts/bootstrap-kind.sh
~~~

### Linux host

Install Docker, Git, Kind, kubectl, Helm, and Python 3. Use a 64-bit host with
at least 8 GB RAM; an SSD-backed data directory is strongly recommended.

~~~bash
git clone https://github.com/umeshchhabra/mlops-foundry.git
cd mlops-foundry
MLOPS_DATA_DIR=/mnt/mlops-data ./scripts/bootstrap-kind.sh
~~~

The bootstrap creates the Kind cluster, persistent-volume claims, local
runtime secrets, and the MLflow image. It does not install Argo CD, because
that is the point where you supply a read-only GitHub token for this private
repository.

For either host type, continue from the same shell:

~~~bash
kubectl create namespace argocd
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd wait --for=condition=Available deployment/argocd-server --timeout=5m
./scripts/configure-argocd-local.sh
python3 ./scripts/configure-argocd-repo.py
python3 ./scripts/configure-airflow-secrets.py
kubectl apply -f infra/bootstrap/bootstrap-project.yaml
kubectl apply -f infra/bootstrap/root-application.yaml
./health/wait-for-stack.sh
python3 ./health/check-stack.py
~~~

The wait helper allows up to 15 minutes for Argo CD to install and reconcile
the chart-backed services. If an address does not open, run the health check
and inspect the matching Argo CD Application.

For Raspberry Pi details and architecture checks, see
[docs/linux-kind.md](docs/linux-kind.md).

## A short day-to-day guide

Check the platform whenever you change infrastructure:

~~~bash
python3 ./health/check-stack.py
~~~

Connect a development repository by supplying its Airflow DAGs, MLflow client
configuration, feature-store definitions, and KServe workload manifests. The
platform remains independent of any one dataset or model.

When a training team requests support for a new project, the platform team uses
the individual MinIO, MLflow, Airflow, KServe, and Feast operations in
[docs/project-provisioning.md](docs/project-provisioning.md). The guide uses
Bash commands and does not create a project Kubernetes workload.

## Useful deeper references

- [docs/airflow.md](docs/airflow.md) — Airflow deployment and secret setup.
- [docs/project-provisioning.md](docs/project-provisioning.md) — training-team request and platform-team provisioning workflow.
- [infra/platform/kserve/README.md](infra/platform/kserve/README.md) — KServe platform boundary.
- [infra/platform/backup/README.md](infra/platform/backup/README.md) — backups and restore helper.
- [health/README.md](health/README.md) — what the health check validates.

## A note on scope

This is a complete local learning platform, not an internet-facing production
deployment. TLS/ingress, external backup copies, HA, and advanced identity
controls are deliberately left out. Keep it on a trusted home or lab network.
