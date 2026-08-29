#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-mlops}"
MLOPS_DATA_DIR="${MLOPS_DATA_DIR:-/opt/mlops-data}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for command in docker kind kubectl helm openssl; do
  command -v "$command" >/dev/null || { echo "Missing: $command"; exit 1; }
done
case "$(uname -m)" in
  aarch64|arm64|x86_64|amd64) ;;
  *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

sudo mkdir -p "$MLOPS_DATA_DIR"
sudo chown "$(id -u):$(id -g)" "$MLOPS_DATA_DIR"
config="$(mktemp)"
trap 'rm -f "$config"' EXIT
sed "s|__MLOPS_DATA_DIR__|$MLOPS_DATA_DIR|g" "$ROOT/infra/bootstrap/kind/kind-linux.yaml.tpl" > "$config"
kind create cluster --name "$CLUSTER_NAME" --config "$config"
kubectl apply -f "$ROOT/infra/platform/overlays/kind-linux/storage.yaml"

# The core manifests reference this local image. Building on the target host
# selects its native CPU architecture, then Kind distributes it to every node.
docker build --tag mlflow:3.4.0-psycopg2 --file "$ROOT/images/mlflow/Dockerfile" "$ROOT/images/mlflow"
kind load docker-image mlflow:3.4.0-psycopg2 --name "$CLUSTER_NAME"

random() {
  openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32
}
postgres_password="$(random)"; airflow_password="$(random)"; minio_password="$(random)"
kubectl create secret generic platform-secrets -n mlops \
  --from-literal=POSTGRES_USER=mlflow --from-literal=POSTGRES_PASSWORD="$postgres_password" \
  --from-literal=AIRFLOW_DB_PASSWORD="$airflow_password" \
  --from-literal=AIRFLOW_DB_URI="postgresql+psycopg2://airflow:$airflow_password@postgres:5432/airflow" \
  --from-literal=MLFLOW_DB_URI="postgresql+psycopg2://mlflow:$postgres_password@postgres:5432/mlflow" \
  --from-literal=MINIO_ROOT_USER=mlops-admin --from-literal=MINIO_ROOT_PASSWORD="$minio_password" \
  --from-literal=AWS_ACCESS_KEY_ID=mlops-admin --from-literal=AWS_SECRET_ACCESS_KEY="$minio_password" \
  --from-literal=GRAFANA_ADMIN_USER=admin --from-literal=GRAFANA_ADMIN_PASSWORD="$(random)"
echo 'Cluster, storage claims, native MLflow image, and runtime secrets created. Configure Argo CD next.'
