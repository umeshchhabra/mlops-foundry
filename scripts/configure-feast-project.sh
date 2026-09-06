#!/usr/bin/env bash
set -euo pipefail

project="${1:-}"
context="${KUBE_CONTEXT:-kind-mlops}"
namespace="${FEAST_NAMESPACE:-}"
if [[ ! "$project" =~ ^[a-z][a-z0-9_]*$ ]]; then
  printf 'Usage: %s <lowercase_feast_project>\n' "$0" >&2
  exit 1
fi

slug="${project//_/-}"
bucket="feast-${slug}"
namespace="${namespace:-feast-${slug}}"
if (( ${#bucket} > 63 )); then
  printf "Derived bucket name '%s' exceeds 63 characters.\n" "$bucket" >&2
  exit 1
fi
if [[ ! "$namespace" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || (( ${#namespace} > 63 )); then
  printf "Namespace '%s' is not a valid Kubernetes namespace.\n" "$namespace" >&2
  exit 1
fi

secret_value() {
  kubectl --context "$context" -n mlops get secret platform-secrets -o "jsonpath={.data.$1}" | base64 --decode
}

redis_password="$(secret_value REDIS_PASSWORD)"
access_key="$(secret_value AWS_ACCESS_KEY_ID)"
secret_key="$(secret_value AWS_SECRET_ACCESS_KEY)"

kubectl --context "$context" create namespace "$namespace" --dry-run=client -o yaml | kubectl --context "$context" apply -f -
kubectl --context "$context" label namespace "$namespace" mlops-foundry.io/feature-client=true --overwrite
kubectl --context "$context" -n "$namespace" create configmap feast-platform \
  --from-literal="FEAST_PROJECT=$project" --from-literal="FEAST_BUCKET=$bucket" \
  --from-literal="FEAST_REGISTRY=s3://$bucket/registry.pb" --from-literal="FEAST_OFFLINE_PREFIX=s3://$bucket/offline" \
  --from-literal=REDIS_HOST=redis.mlops.svc.cluster.local --from-literal=REDIS_PORT=6379 \
  --from-literal=S3_ENDPOINT_URL=http://minio.mlops.svc.cluster.local:9000 \
  --from-literal=FEAST_S3_ENDPOINT_URL=http://minio.mlops.svc.cluster.local:9000 \
  --dry-run=client -o yaml | kubectl --context "$context" apply -f -
kubectl --context "$context" -n "$namespace" create secret generic feast-platform-access \
  --from-literal="REDIS_PASSWORD=$redis_password" --from-literal="AWS_ACCESS_KEY_ID=$access_key" \
  --from-literal="AWS_SECRET_ACCESS_KEY=$secret_key" --dry-run=client -o yaml | kubectl --context "$context" apply -f -

job_name="create-${bucket}"
kubectl --context "$context" -n mlops delete job "$job_name" --ignore-not-found >/dev/null
kubectl --context "$context" apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata: { name: $job_name, namespace: mlops }
spec:
  backoffLimit: 4
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: create-bucket
          image: minio/mc:RELEASE.2025-08-13T08-35-41Z
          env:
            - name: MINIO_ROOT_USER
              valueFrom: { secretKeyRef: { name: platform-secrets, key: MINIO_ROOT_USER } }
            - name: MINIO_ROOT_PASSWORD
              valueFrom: { secretKeyRef: { name: platform-secrets, key: MINIO_ROOT_PASSWORD } }
          command: [/bin/sh, -ec]
          args: ['mc alias set minio http://minio:9000 "\$MINIO_ROOT_USER" "\$MINIO_ROOT_PASSWORD"; mc mb --ignore-existing minio/$bucket']
EOF
kubectl --context "$context" -n mlops wait "job/$job_name" --for=condition=Complete --timeout=2m
kubectl --context "$context" -n mlops delete job "$job_name" --wait=false >/dev/null

unset redis_password access_key secret_key
printf "Feast project '%s' is ready in namespace '%s' with bucket '%s'.\n" "$project" "$namespace" "$bucket"
