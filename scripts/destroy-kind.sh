#!/usr/bin/env bash
set -euo pipefail

cluster_name="${CLUSTER_NAME:-mlops}"
data_dir="${MLOPS_DATA_DIR:-$HOME/.local/share/mlops-foundry}"
delete_data=false
confirmed=false

usage() {
  cat <<'EOF'
Usage: ./scripts/destroy-kind.sh [--cluster-name NAME] [--data-dir PATH] [--delete-data] --confirm

Deletes only the named Kind cluster. Add --delete-data to also permanently
remove the supplied MLOPS data directory. The script refuses broad filesystem
targets and requires --confirm so it cannot run accidentally.
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
    --delete-data)
      delete_data=true
      shift
      ;;
    --confirm)
      confirmed=true
      shift
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

command -v kind >/dev/null || {
  printf '%s\n' 'Missing required command: kind' >&2
  exit 1
}

if [[ "$confirmed" != true ]]; then
  printf '%s\n' 'Refusing to delete without --confirm.' >&2
  exit 2
fi

if [[ "$delete_data" == true ]]; then
  command -v realpath >/dev/null || {
    printf '%s\n' 'Missing required command: realpath' >&2
    exit 1
  }
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
  marker="$data_dir/.mlops-foundry-data"
  if [[ ! -f "$marker" ]] || [[ "$(head -n 1 "$marker")" != 'mlops-foundry-kind-data-v1' ]]; then
    printf 'Refusing to delete data directory without the MLOps Foundry marker: %s\n' "$data_dir" >&2
    exit 2
  fi
fi

printf 'Deleting Kind cluster: %s\n' "$cluster_name"
if kind get clusters | grep -Fxq "$cluster_name"; then
  kind delete cluster --name "$cluster_name"
else
  printf 'Kind cluster %s does not exist; continuing.\n' "$cluster_name"
fi

if [[ "$delete_data" == true && -e "$data_dir" ]]; then
  printf 'Deleting MLOPS data directory: %s\n' "$data_dir"
  rm -rf --one-file-system -- "$data_dir"
fi

printf '%s\n' 'MLOps Foundry cleanup completed.'
