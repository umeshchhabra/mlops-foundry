# Project-service provisioning guide

Use this guide when a training team asks the platform team to support a model
project. It documents individual service operations; it does not create project
pods, services, namespaces, training jobs, Feast servers, or KServe models.

## Collect the request

Ask for a lowercase project ID, a display name, requested services, expected
storage size, and Airflow concurrency. Supported shared services are artifacts
(MinIO), MLflow, Airflow, KServe, and Feast. Use one dedicated bucket named
`mlops-<project-id-with-hyphens>` with `data/`, `artifacts/`, `models/`,
`features/registry.pb`, and `features/offline/` prefixes.

## MinIO: bucket and scoped credentials

Run these commands as the platform operator after retrieving the MinIO root
credentials with `pwsh ./scripts/show-platform-credentials.ps1`. Install the
MinIO client (`mc`) on the operator machine. Store generated project credentials
only in the approved secret store, never in Git or chat.

PowerShell:

```powershell
$Project = '<project_id>'; $Slug = $Project.Replace('_', '-')
$Bucket = "mlops-$Slug"; $AccessKey = '<project-access-key>'; $SecretKey = '<project-secret-key>'
$PolicyName = "project-$Slug"
mc alias set mlops http://localhost:9000 '<minio-root-user>' '<minio-root-password>'
mc mb --ignore-existing "mlops/$Bucket"
$PolicyFile = Join-Path $env:TEMP "$PolicyName.json"
@"
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:ListBucket","s3:GetBucketLocation"],"Resource":["arn:aws:s3:::$Bucket"]},{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:DeleteObject"],"Resource":["arn:aws:s3:::$Bucket/*"]}]}
"@ | Set-Content -NoNewline $PolicyFile
mc admin policy create mlops $PolicyName $PolicyFile
mc admin user add mlops $AccessKey $SecretKey
mc admin policy attach mlops $PolicyName --user $AccessKey
Remove-Item -LiteralPath $PolicyFile
```

Bash:

```bash
project='<project_id>'; slug="${project//_/-}"; bucket="mlops-$slug"
access_key='<project-access-key>'; secret_key='<project-secret-key>'; policy_name="project-$slug"
mc alias set mlops http://localhost:9000 '<minio-root-user>' '<minio-root-password>'
mc mb --ignore-existing "mlops/$bucket"
policy_file="$(mktemp)"; trap 'rm -f "$policy_file"' EXIT
printf '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:ListBucket","s3:GetBucketLocation"],"Resource":["arn:aws:s3:::%s"]},{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:DeleteObject"],"Resource":["arn:aws:s3:::%s/*"]}]}' "$bucket" "$bucket" > "$policy_file"
mc admin policy create mlops "$policy_name" "$policy_file"
mc admin user add mlops "$access_key" "$secret_key"
mc admin policy attach mlops "$policy_name" --user "$access_key"
```

## MLflow: experiment and artifact location

Create one experiment after the bucket exists. Do not alter an existing
experiment's artifact location.

PowerShell:

```powershell
$DisplayName = '<project display name>'
$Body = @{ name = $DisplayName; artifact_location = "s3://$Bucket/artifacts" } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri 'http://localhost:5000/api/2.0/mlflow/experiments/create' -ContentType 'application/json' -Body $Body
```

Bash:

```bash
display_name='<project display name>'
curl --fail-with-body -X POST http://localhost:5000/api/2.0/mlflow/experiments/create -H 'Content-Type: application/json' -d "{\"name\":\"$display_name\",\"artifact_location\":\"s3://$bucket/artifacts\"}"
```

## Airflow: project pool

This creates scheduler metadata only, not a project workload.

PowerShell:

```powershell
$Scheduler = kubectl -n mlops get pod -l component=scheduler -o jsonpath='{.items[0].metadata.name}'
kubectl -n mlops exec $Scheduler -c scheduler -- airflow pools set "project-$Slug" 1 '<project display name> workload limit'
```

Bash:

```bash
scheduler="$(kubectl -n mlops get pod -l component=scheduler -o jsonpath='{.items[0].metadata.name}')"
kubectl -n mlops exec "$scheduler" -c scheduler -- airflow pools set "project-$slug" 1 '<project display name> workload limit'
```

## KServe and Feast

KServe is already shared; verify it with `kubectl -n kserve get deployment
kserve-controller-manager`. The development repository later deploys its own
`InferenceService` if serving is required.

For Feast, give the development team the project ID, its bucket credentials,
`s3://mlops-<project-id-with-hyphens>/features/registry.pb`, the
`features/offline/` prefix, and the shared Redis endpoint
`redis.mlops.svc.cluster.local:6379`. The local platform currently uses shared
Redis credentials, so Feast project names are a logical—not security—isolation
boundary.
