#!/usr/bin/env bash
set -euo pipefail

project=''
services=''
display_name=''
airflow_slots=1
context="${KUBE_CONTEXT:-kind-mlops}"
mlflow_uri="${MLFLOW_URI:-http://localhost:5000}"

while (($#)); do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --services) services="$2"; shift 2 ;;
    --display-name) display_name="$2"; shift 2 ;;
    --airflow-slots) airflow_slots="$2"; shift 2 ;;
    --context) context="$2"; shift 2 ;;
    --mlflow-uri) mlflow_uri="$2"; shift 2 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[[ "$project" =~ ^[a-z][a-z0-9_]*$ ]] || { echo 'Project must start with a lowercase letter and use only lowercase letters, numbers, and underscores.' >&2; exit 2; }
[[ -n "$services" ]] || { echo 'At least one service is required.' >&2; exit 2; }
slug="${project//_/-}"; [[ ${#slug} -le 48 ]] || { echo 'Project is too long; use 48 characters or fewer.' >&2; exit 2; }
display_name="${display_name:-$project}"
bucket="mlops-$slug"; secret_name="project-$slug-access"; config_name="project-$slug"
IFS=',' read -r -a selected <<< "$services"
for service in "${selected[@]}"; do [[ "$service" =~ ^(artifacts|mlflow|airflow|kserve|feast)$ ]] || { echo "Unsupported service: $service" >&2; exit 2; }; done
has_service() { local wanted="$1"; [[ ",$services," == *",$wanted,"* ]]; }
needs_storage=false
if has_service artifacts || has_service mlflow || has_service feast; then needs_storage=true; fi

secret_value() { kubectl --context "$context" -n mlops get secret "$1" -o "jsonpath={.data.$2}" 2>/dev/null | base64 --decode; }
existing_secret_value() { secret_value "$1" "$2" 2>/dev/null || true; }
access_key="$(existing_secret_value "$secret_name" MINIO_ACCESS_KEY)"
secret_key="$(existing_secret_value "$secret_name" MINIO_SECRET_KEY)"
if [[ "$needs_storage" == true && -z "$access_key" ]]; then
  access_key="prj$(printf '%s' "$project" | sha256sum | cut -c1-12)"
  secret_key="$(openssl rand -hex 24)"
fi

if [[ "$needs_storage" == true ]]; then
  secret_args=("--from-literal=MINIO_ACCESS_KEY=$access_key" "--from-literal=MINIO_SECRET_KEY=$secret_key" '--from-literal=S3_ENDPOINT_URL=http://minio.mlops.svc.cluster.local:9000' "--from-literal=PROJECT_BUCKET=$bucket")
  if has_service feast; then
    redis_password="$(secret_value platform-secrets REDIS_PASSWORD)"
    [[ -n "$redis_password" ]] || { echo 'platform-secrets/REDIS_PASSWORD is required for Feast.' >&2; exit 1; }
    secret_args+=("--from-literal=REDIS_PASSWORD=$redis_password")
  fi
  kubectl --context "$context" -n mlops create secret generic "$secret_name" "${secret_args[@]}" --dry-run=client -o yaml | kubectl --context "$context" apply -f -
  job_name="provision-$slug-storage"; policy="project-$slug"
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
        - name: provision
          image: minio/mc:RELEASE.2025-08-13T08-35-41Z
          env:
            - { name: MINIO_ROOT_USER, valueFrom: { secretKeyRef: { name: platform-secrets, key: MINIO_ROOT_USER } } }
            - { name: MINIO_ROOT_PASSWORD, valueFrom: { secretKeyRef: { name: platform-secrets, key: MINIO_ROOT_PASSWORD } } }
            - { name: MINIO_ACCESS_KEY, valueFrom: { secretKeyRef: { name: $secret_name, key: MINIO_ACCESS_KEY } } }
            - { name: MINIO_SECRET_KEY, valueFrom: { secretKeyRef: { name: $secret_name, key: MINIO_SECRET_KEY } } }
          command: [/bin/sh, -ec]
          args:
            - |
              set -e
              mc alias set minio http://minio:9000 "\$MINIO_ROOT_USER" "\$MINIO_ROOT_PASSWORD"
              mc mb --ignore-existing minio/$bucket
              cat > /tmp/policy.json <<'POLICY'
              {"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:ListBucket","s3:GetBucketLocation"],"Resource":["arn:aws:s3:::$bucket"]},{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:DeleteObject"],"Resource":["arn:aws:s3:::$bucket/*"]}]}
              POLICY
              mc admin policy remove minio $policy >/dev/null 2>&1 || true
              mc admin policy create minio $policy /tmp/policy.json
              mc admin user add minio "\$MINIO_ACCESS_KEY" "\$MINIO_SECRET_KEY"
              mc admin policy attach minio $policy --user "\$MINIO_ACCESS_KEY"
EOF
  kubectl --context "$context" -n mlops wait "job/$job_name" --for=condition=Complete --timeout=2m
  kubectl --context "$context" -n mlops delete job "$job_name" --wait=false >/dev/null
fi

config_args=("--from-literal=PROJECT=$project" "--from-literal=DISPLAY_NAME=$display_name" "--from-literal=SERVICES=$services" "--from-literal=MLFLOW_TRACKING_URI=$mlflow_uri" "--from-literal=KSERVE_AVAILABLE=$(has_service kserve && echo true || echo false)")
[[ "$needs_storage" == true ]] && config_args+=("--from-literal=PROJECT_BUCKET=$bucket")
if has_service feast; then config_args+=("--from-literal=FEAST_REGISTRY=s3://$bucket/features/registry.pb" "--from-literal=FEAST_OFFLINE_PREFIX=s3://$bucket/features/offline" '--from-literal=REDIS_HOST=redis.mlops.svc.cluster.local' '--from-literal=REDIS_PORT=6379'); fi
kubectl --context "$context" -n mlops create configmap "$config_name" "${config_args[@]}" --dry-run=client -o yaml | kubectl --context "$context" apply -f -

if has_service mlflow; then
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$mlflow_uri/api/2.0/mlflow/experiments/get-by-name?experiment_name=$(printf '%s' "$display_name" | sed 's/ /%20/g')")"
  if [[ "$code" == 404 ]]; then curl -fsS -X POST "$mlflow_uri/api/2.0/mlflow/experiments/create" -H 'Content-Type: application/json' -d "{\"name\":\"$display_name\",\"artifact_location\":\"s3://$bucket/artifacts\"}" >/dev/null; elif [[ "$code" != 200 ]]; then echo "MLflow experiment lookup failed with HTTP $code." >&2; exit 1; fi
fi
if has_service airflow; then
  scheduler="$(kubectl --context "$context" -n mlops get pod -l component=scheduler -o jsonpath='{.items[0].metadata.name}')"
  [[ -n "$scheduler" ]] || { echo 'Airflow scheduler pod is unavailable.' >&2; exit 1; }
  kubectl --context "$context" -n mlops exec "$scheduler" -c scheduler -- airflow pools set "project-$slug" "$airflow_slots" "Project $project workload limit"
fi

unset access_key secret_key redis_password
printf "Project '%s' provisioned in the shared platform. No project Kubernetes workload was created.\n" "$project"
