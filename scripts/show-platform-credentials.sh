#!/usr/bin/env bash
set -euo pipefail

context="${KUBE_CONTEXT:-kind-mlops}"
namespace="${MLOPS_NAMESPACE:-mlops}"

secret_value() {
  local secret_namespace="$1"
  local secret_name="$2"
  local key="$3"
  local encoded

  if ! encoded="$(kubectl --context "$context" -n "$secret_namespace" get secret "$secret_name" -o "jsonpath={.data.${key}}" 2>/dev/null)" || [[ -z "$encoded" ]]; then
    printf '%s' '<not available>'
    return
  fi

  printf '%s' "$encoded" | base64 --decode
}

if ! kubectl --context "$context" cluster-info >/dev/null 2>&1; then
  printf "Kubernetes context '%s' is not reachable.\n" "$context" >&2
  exit 1
fi

printf '%-12s %-24s %s\n' 'SERVICE' 'USERNAME' 'PASSWORD'
printf '%-12s %-24s %s\n' 'Argo CD' 'admin' "$(secret_value argocd argocd-initial-admin-secret password)"
printf '%-12s %-24s %s\n' 'Airflow' 'admin' "$(secret_value "$namespace" airflow-admin password)"
printf '%-12s %-24s %s\n' 'Grafana' "$(secret_value "$namespace" platform-secrets GRAFANA_ADMIN_USER)" "$(secret_value "$namespace" platform-secrets GRAFANA_ADMIN_PASSWORD)"
printf '%-12s %-24s %s\n' 'MinIO' "$(secret_value "$namespace" platform-secrets MINIO_ROOT_USER)" "$(secret_value "$namespace" platform-secrets MINIO_ROOT_PASSWORD)"
printf '%-12s %-24s %s\n' 'Redis' 'default' "$(secret_value "$namespace" platform-secrets REDIS_PASSWORD)"
printf '%-12s %-24s %s\n' 'PostgreSQL' "$(secret_value "$namespace" platform-secrets POSTGRES_USER)" "$(secret_value "$namespace" platform-secrets POSTGRES_PASSWORD)"

printf '\nMLflow and Prometheus do not require login. KServe does not provide a user-facing login.\n'
printf 'WARNING: These values are sensitive. Do not paste the output into chat, logs, documentation, or source control.\n' >&2
