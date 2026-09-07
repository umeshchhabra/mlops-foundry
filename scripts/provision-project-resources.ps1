[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Project,
  [Parameter(Mandatory)][ValidateSet('artifacts','mlflow','airflow','kserve','feast')][string[]]$Services,
  [string]$DisplayName,
  [int]$AirflowSlots = 1,
  [string]$Context = 'kind-mlops',
  [string]$MlflowUri = 'http://localhost:5000'
)

$ErrorActionPreference = 'Stop'
if ($Project -cnotmatch '^[a-z][a-z0-9_]*$') { throw 'Project must start with a lowercase letter and use only lowercase letters, numbers, and underscores.' }
$slug = $Project.Replace('_', '-')
if ($slug.Length -gt 48) { throw 'Project is too long; use 48 characters or fewer.' }
if (-not $DisplayName) { $DisplayName = $Project }
$Services = @($Services | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
$needsStorage = @($Services | Where-Object { $_ -in @('artifacts','mlflow','feast') }).Count -gt 0
$bucket = "mlops-$slug"; $secretName = "project-$slug-access"; $configName = "project-$slug"

function Get-SecretValue([string]$Secret, [string]$Key) {
  $encoded = kubectl --context $Context -n mlops get secret $Secret "-o=jsonpath={.data.$Key}" 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($encoded)) { return $null }
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
}
function New-RandomValue([int]$Bytes = 24) {
  $buffer = New-Object byte[] $Bytes; $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
  ([Convert]::ToBase64String($buffer) -replace '[^A-Za-z0-9]', '').Substring(0, 32)
}
function New-ProjectAccessKey([string]$Value) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))
    'prj' + ([BitConverter]::ToString($hash).Replace('-', '').Substring(0, 12).ToLowerInvariant())
  } finally { $sha.Dispose() }
}

$accessKey = Get-SecretValue $secretName 'MINIO_ACCESS_KEY'
$secretKey = Get-SecretValue $secretName 'MINIO_SECRET_KEY'
if ($needsStorage -and -not $accessKey) { $accessKey = New-ProjectAccessKey $Project; $secretKey = New-RandomValue }

if ($needsStorage) {
  $secretArgs = @("--from-literal=MINIO_ACCESS_KEY=$accessKey", "--from-literal=MINIO_SECRET_KEY=$secretKey", '--from-literal=S3_ENDPOINT_URL=http://minio.mlops.svc.cluster.local:9000', "--from-literal=PROJECT_BUCKET=$bucket")
  if ($Services -contains 'feast') {
    $redisPassword = Get-SecretValue 'platform-secrets' 'REDIS_PASSWORD'
    if (-not $redisPassword) { throw 'platform-secrets/REDIS_PASSWORD is required for Feast.' }
    $secretArgs += "--from-literal=REDIS_PASSWORD=$redisPassword"
  }
  kubectl --context $Context -n mlops create secret generic $secretName @secretArgs --dry-run=client -o yaml | kubectl --context $Context apply -f -
  $jobName = "provision-$slug-storage"
  kubectl --context $Context -n mlops delete job $jobName --ignore-not-found | Out-Null
  $policy = "project-$slug"
  $command = @"
set -e
mc alias set minio http://minio:9000 "`$MINIO_ROOT_USER" "`$MINIO_ROOT_PASSWORD"
mc mb --ignore-existing minio/$bucket
cat > /tmp/policy.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:ListBucket","s3:GetBucketLocation"],"Resource":["arn:aws:s3:::$bucket"]},{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:DeleteObject"],"Resource":["arn:aws:s3:::$bucket/*"]}]}
EOF
mc admin policy remove minio $policy >/dev/null 2>&1 || true
mc admin policy create minio $policy /tmp/policy.json
mc admin user add minio "`$MINIO_ACCESS_KEY" "`$MINIO_SECRET_KEY"
mc admin policy attach minio $policy --user "`$MINIO_ACCESS_KEY"
"@
  $job = @{ apiVersion='batch/v1'; kind='Job'; metadata=@{name=$jobName;namespace='mlops'}; spec=@{backoffLimit=4;template=@{spec=@{restartPolicy='OnFailure';containers=@(@{name='provision';image='minio/mc:RELEASE.2025-08-13T08-35-41Z';command=@('/bin/sh','-ec');args=@($command);env=@(
    @{name='MINIO_ROOT_USER';valueFrom=@{secretKeyRef=@{name='platform-secrets';key='MINIO_ROOT_USER'}}}, @{name='MINIO_ROOT_PASSWORD';valueFrom=@{secretKeyRef=@{name='platform-secrets';key='MINIO_ROOT_PASSWORD'}}}, @{name='MINIO_ACCESS_KEY';valueFrom=@{secretKeyRef=@{name=$secretName;key='MINIO_ACCESS_KEY'}}}, @{name='MINIO_SECRET_KEY';valueFrom=@{secretKeyRef=@{name=$secretName;key='MINIO_SECRET_KEY'}}}
  )})}}}} | ConvertTo-Json -Depth 15
  $job | kubectl --context $Context apply -f -
  kubectl --context $Context -n mlops wait "job/$jobName" --for=condition=Complete --timeout=2m
  if ($LASTEXITCODE -ne 0) { throw "Storage provisioning failed; inspect job/$jobName in mlops." }
  kubectl --context $Context -n mlops delete job $jobName --wait=false | Out-Null
}

$configArgs = @("--from-literal=PROJECT=$Project", "--from-literal=DISPLAY_NAME=$DisplayName", "--from-literal=SERVICES=$($Services -join ',')", "--from-literal=MLFLOW_TRACKING_URI=$MlflowUri", "--from-literal=KSERVE_AVAILABLE=$($Services -contains 'kserve')")
if ($needsStorage) { $configArgs += "--from-literal=PROJECT_BUCKET=$bucket" }
if ($Services -contains 'feast') { $configArgs += "--from-literal=FEAST_REGISTRY=s3://$bucket/features/registry.pb"; $configArgs += "--from-literal=FEAST_OFFLINE_PREFIX=s3://$bucket/features/offline"; $configArgs += '--from-literal=REDIS_HOST=redis.mlops.svc.cluster.local'; $configArgs += '--from-literal=REDIS_PORT=6379' }
kubectl --context $Context -n mlops create configmap $configName @configArgs --dry-run=client -o yaml | kubectl --context $Context apply -f -

if ($Services -contains 'mlflow') {
  $lookup = Invoke-WebRequest -UseBasicParsing -Uri "$MlflowUri/api/2.0/mlflow/experiments/get-by-name?experiment_name=$([uri]::EscapeDataString($DisplayName))" -SkipHttpErrorCheck
  if ($lookup.StatusCode -eq 404) {
    $body = @{name=$DisplayName;artifact_location="s3://$bucket/artifacts"} | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri "$MlflowUri/api/2.0/mlflow/experiments/create" -ContentType 'application/json' -Body $body | Out-Null
  } elseif ($lookup.StatusCode -ne 200) { throw "MLflow experiment lookup failed with HTTP $($lookup.StatusCode)." }
}
if ($Services -contains 'airflow') {
  $scheduler = kubectl --context $Context -n mlops get pod -l component=scheduler -o jsonpath='{.items[0].metadata.name}'
  if (-not $scheduler) { throw 'Airflow scheduler pod is unavailable.' }
  kubectl --context $Context -n mlops exec $scheduler -c scheduler -- airflow pools set "project-$slug" $AirflowSlots "Project $Project workload limit"
}

$accessKey = $null; $secretKey = $null; $redisPassword = $null
Write-Host "Project '$Project' provisioned in the shared platform. No project Kubernetes workload was created."
