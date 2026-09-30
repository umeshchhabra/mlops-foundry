#!/usr/bin/env bash
set -euo pipefail

cluster_name="${CLUSTER_NAME:-mlops}"
data_dir="${MLOPS_DATA_DIR:-$HOME/.local/share/mlops-foundry}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: ./scripts/bootstrap-kind.sh [--cluster-name NAME] [--data-dir PATH]

Creates a local Kind cluster, its persistent-volume claims, local MLflow image,
and runtime-only platform secrets. Run this from Linux or WSL.

Environment:
  CLUSTER_NAME    Kind cluster name (default: mlops)
  MLOPS_DATA_DIR  Host directory mounted into Kind (default:
                  ~/.local/share/mlops-foundry)
EOF
}

while (($#)); do
  case "$1" in
    --cluster-name)
      cluster_name="${2:?--cluster-name requires a value}"
      shift 2
      ;;
    --data-dir)
      data_dir="${2:?--data-dir requires a value}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for command in docker kind kubectl python3 realpath; do
  command -v "$command" >/dev/null || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 1
  }
done

case "$(uname -m)" in
  aarch64|arm64|x86_64|amd64) ;;
  *)
    printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

data_dir="$(realpath -m -- "$data_dir")"
home_dir="$(realpath -m -- "$HOME")"
case "$data_dir" in
  /|"$home_dir"|/home|/mnt|/var|/usr|/etc|/root|/opt|/run|/tmp|/boot|/bin|/sbin|/lib|/lib32|/lib64|/proc|/sys|/dev)
    printf 'Refusing unsafe data directory: %s\n' "$data_dir" >&2
    exit 2
    ;;
esac
if [[ "$data_dir" =~ ^/mnt/[^/]+$ ]]; then
  printf 'Refusing filesystem-root data directory: %s\n' "$data_dir" >&2
  exit 2
fi
case "$data_dir" in
  "$root"|"$root"/*)
    printf 'Refusing repository path as data directory: %s\n' "$data_dir" >&2
    exit 2
    ;;
esac
mkdir -p "$data_dir"
data_marker="$data_dir/.mlops-foundry-data"
if [[ ! -e "$data_marker" ]]; then
  if [[ -n "$(find "$data_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    printf 'Refusing non-empty uninitialized data directory: %s\n' "$data_dir" >&2
    exit 2
  fi
  printf '%s\n' 'mlops-foundry-kind-data-v1' > "$data_marker"
fi

config="$(mktemp)"
trap 'rm -f "$config"' EXIT
python3 - "$root/infra/bootstrap/kind/kind.yaml.tpl" "$config" "$data_dir" <<'PY'
from pathlib import Path
import json
import sys

template, destination, data_dir = map(Path, sys.argv[1:])
destination.write_text(
    template.read_text().replace("__MLOPS_DATA_DIR__", json.dumps(str(data_dir))),
    encoding="utf-8",
)
PY

context="kind-$cluster_name"
kind create cluster --name "$cluster_name" --config "$config"
kubectl config use-context "$context" >/dev/null
kubectl --context "$context" -n local-path-storage wait \
  --for=condition=Available deployment/local-path-provisioner --timeout=2m
kubectl --context "$context" apply -f "$root/infra/platform/overlays/kind/storage.yaml"
kubectl --context "$context" -n local-path-storage rollout restart deployment/local-path-provisioner >/dev/null
kubectl --context "$context" -n local-path-storage rollout status deployment/local-path-provisioner --timeout=2m >/dev/null
python3 "$root/scripts/configure-monitoring-network.py" --context "$context"

# The core manifests reference local images. Building on the target host
# selects its native CPU architecture, then Kind distributes them to every node.
docker build --tag mlflow:3.4.0-psycopg2 --file "$root/images/mlflow/Dockerfile" "$root/images/mlflow"
kind load docker-image mlflow:3.4.0-psycopg2 --name "$cluster_name"
docker build --tag mlops-minio:2025-09-07 --file "$root/images/minio/Dockerfile" "$root/images/minio"
kind load docker-image mlops-minio:2025-09-07 --name "$cluster_name"

python3 "$root/scripts/configure-platform-secrets.py" --context "$context"
printf '%s\n' 'Cluster, storage claims, local image, and runtime-only secrets are ready. Configure Argo CD next.'
