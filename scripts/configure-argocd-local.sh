#!/usr/bin/env bash
set -euo pipefail

context="${KUBE_CONTEXT:-kind-mlops}"
namespace="${ARGOCD_NAMESPACE:-argocd}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: ./scripts/configure-argocd-local.sh [--context NAME] [--namespace NAME]

Exposes Argo CD on localhost and enables its trusted-local HTTP mode.
EOF
}

while (($#)); do
  case "$1" in
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

kubectl --context "$context" apply -f "$root/infra/bootstrap/argocd-server-nodeport.yaml"
kubectl --context "$context" -n "$namespace" patch configmap argocd-cmd-params-cm \
  --type merge --patch '{"data":{"server.insecure":"true"}}' >/dev/null
kubectl --context "$context" -n "$namespace" rollout restart deployment/argocd-server >/dev/null
kubectl --context "$context" -n "$namespace" rollout status deployment/argocd-server --timeout=3m >/dev/null

printf '%s\n' 'Argo CD is available at http://localhost:8080.'
