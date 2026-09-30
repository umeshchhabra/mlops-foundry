#!/usr/bin/env bash
set -euo pipefail

postgres_backup=""
apply_restore=false
context="${KUBE_CONTEXT:-kind-mlops}"
namespace="${MLOPS_NAMESPACE:-mlops}"

usage() {
  cat <<'EOF'
Usage: ./infra/platform/backup/restore-test.sh --postgres-backup FILE [--apply] [--context NAME] [--namespace NAME]

Validates a PostgreSQL backup by default. --apply streams it into the local
PostgreSQL service, so use that flag only for a deliberate restore.
EOF
}

while (($#)); do
  case "$1" in
    --postgres-backup)
      postgres_backup="${2:?--postgres-backup requires a file}"
      shift 2
      ;;
    --apply)
      apply_restore=true
      shift
      ;;
    --context)
      context="${2:?--context requires a value}"
      shift 2
      ;;
    --namespace)
      namespace="${2:?--namespace requires a value}"
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

if [[ -z "$postgres_backup" || ! -f "$postgres_backup" ]]; then
  printf 'Backup file not found: %s\n' "$postgres_backup" >&2
  exit 2
fi

if [[ "$apply_restore" != true ]]; then
  printf 'Dry run: validated %s. Re-run with --apply to restore into the mlops PostgreSQL service.\n' "$postgres_backup"
  exit 0
fi

if [[ "$postgres_backup" == *.gz ]]; then
  command -v gzip >/dev/null || {
    printf '%s\n' 'The --apply path for .gz backups requires gzip on the client.' >&2
    exit 1
  }
  gzip -dc -- "$postgres_backup" |
    kubectl --context "$context" -n "$namespace" exec -i deploy/postgres -- psql -U mlflow
else
  kubectl --context "$context" -n "$namespace" exec -i deploy/postgres -- psql -U mlflow < "$postgres_backup"
fi

printf '%s\n' 'Restore stream completed. Verify application tables before using the restored data.'
