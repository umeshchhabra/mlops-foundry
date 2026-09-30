# MLOps Foundry

MLOps Foundry is a practical MLOps platform that runs on your own machine. It
provides shared infrastructure for development repositories: GitOps,
orchestration, experiment tracking, object storage, model-serving APIs, and
observability.

Nothing here needs a cloud account. Docker runs Kind, Kind runs Kubernetes, and
your data stays on the machine running the cluster.

## Prerequisites

Use one of these supported operator environments:

| Area | Requirement |
| --- | --- |
| Operating system | A 64-bit Linux host (AMD64 or ARM64), or Windows 10/11 with a WSL 2 Linux distribution. Run all repository commands from Linux or WSL—not native Windows. |
| Container runtime | Docker Engine on Linux, or Docker Desktop with WSL integration enabled on Windows. The docker command must work inside the Linux/WSL shell. |
| Command-line tools | Bash, Git, Kind, kubectl, and Python 3. Python uses only the standard library; no pip install step is required for platform setup. |
| Machine capacity | At least 8 GB RAM. Four CPU cores and roughly 20 GB of free disk space are recommended for the four-node Kind cluster and container images. |
| Network and ports | Internet access is needed for the initial Argo CD and chart/image downloads. Keep 8080, 8443, 5000, 8090, and 9000–9003 free on the host. |
| Repository access | An account that can clone this private repository. During Argo CD setup, use a separate read-only GitHub token with access to this repository. |
| Persistent data directory | Choose a new, empty Linux filesystem directory for MLOPS_DATA_DIR. Do not use the repository directory, a filesystem root, or a broad shared directory. On Windows, keep it inside the WSL filesystem rather than /mnt/c. |

Helm and a native Windows shell are not prerequisites. The platform uses Bash
for lifecycle commands and Python 3 for structured checks; Argo CD retrieves
Helm charts itself.

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
distribution, install Git, Docker CLI access, Kind, kubectl, and Python 3.
Give Docker Desktop roughly 8 GB of memory and clone the
repository into the Linux filesystem rather than a mounted drive.

~~~bash
cd ~
docker info >/dev/null
kind version
kubectl version --client
python3 --version
# Authenticate Git for this private clone first, if you have not already.
git clone https://github.com/umeshchhabra/mlops-foundry.git
cd mlops-foundry
MLOPS_DATA_DIR="$HOME/.local/share/mlops-foundry" ./scripts/bootstrap-kind.sh
~~~

### Linux host

Install Docker, Git, Kind, kubectl, and Python 3. Use a 64-bit host with at
least 8 GB RAM; an SSD-backed data directory is strongly recommended.

~~~bash
docker info >/dev/null
kind version
kubectl version --client
python3 --version
git clone https://github.com/umeshchhabra/mlops-foundry.git
cd mlops-foundry
MLOPS_DATA_DIR=/mnt/mlops-data ./scripts/bootstrap-kind.sh
~~~

The bootstrap creates the Kind cluster, configures the Kind local-path
provisioner to keep PVC data under MLOPS_DATA_DIR, creates platform claims and
runtime secrets, and builds the MLflow and MinIO images locally. This avoids
depending on an external MinIO container registry during a Kind installation.
It does not install Argo CD,
because that is the point where you supply a read-only GitHub token for this
private repository. Ensure these host ports are unused before creating the
cluster: 8080, 8443, 5000, 8090, and 9000 through 9003.
Choose a new, empty MLOPS_DATA_DIR; bootstrap records an ownership marker there
so its cleanup helper cannot erase an unrelated directory later.

For either host type, continue from the same shell:

~~~bash
kubectl config use-context kind-mlops
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
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

The GitOps Applications intentionally track main. A clean run from an
unmerged branch validates that branch's local bootstrap scripts and Kind
overlay, while Argo CD installs the committed platform manifests from main.
Merge infrastructure manifest changes before treating an Argo CD rebuild as an
end-to-end test of the branch itself.

## Rebuild from scratch

This is destructive. It removes only the named Kind cluster and, when
requested, the supplied MLOPS data directory. It does not delete your Git
checkout, Docker installation, unrelated Kind clusters, or Docker image cache.
It permanently removes Kubernetes resources and platform state: credentials,
MinIO objects, databases, Redis data, dashboards, metrics, and local backups.

From the repository checkout used to run the platform:

~~~bash
# Reuse the exact data directory from the original bootstrap command.
# Example: use /mnt/mlops-data on Linux, or the WSL default below.
export MLOPS_DATA_DIR="$HOME/.local/share/mlops-foundry"
./scripts/destroy-kind.sh --delete-data --confirm
./scripts/bootstrap-kind.sh
kubectl config use-context kind-mlops
~~~

Then run the Argo CD setup block above again. The reset creates new runtime
credentials, so enter the read-only GitHub token and choose a new Airflow
admin password when prompted. Do not save either value in source control,
shell history, or an environment file. The bootstrap creates a marker inside
MLOPS_DATA_DIR; the cleanup helper refuses to remove an unmarked directory.

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
- [scripts/destroy-kind.sh](scripts/destroy-kind.sh) — scoped clean-rebuild helper.

## A note on scope

This is a complete local learning platform, not an internet-facing production
deployment. TLS/ingress, external backup copies, HA, and advanced identity
controls are deliberately left out. Keep it on a trusted home or lab network.
