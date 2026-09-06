[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Project,
  [string]$Namespace,
  [string]$Context = 'kind-mlops'
)

$ErrorActionPreference = 'Stop'
if ($Project -cnotmatch '^[a-z][a-z0-9_]*$') {
  throw 'Project must start with a lowercase letter and contain only lowercase letters, numbers, and underscores.'
}

$slug = $Project.Replace('_', '-')
$bucket = "feast-$slug"
if ($bucket.Length -gt 63) { throw "Derived bucket name '$bucket' exceeds 63 characters." }
if (-not $Namespace) { $Namespace = "feast-$slug" }
if ($Namespace -notmatch '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$' -or $Namespace.Length -gt 63) {
  throw "Namespace '$Namespace' is not a valid Kubernetes namespace."
}

function Get-PlatformSecret([string]$Key) {
  $encoded = kubectl --context $Context -n mlops get secret platform-secrets "-o=jsonpath={.data.$Key}"
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($encoded)) { throw "platform-secrets/$Key is required." }
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
}

$redisPassword = Get-PlatformSecret REDIS_PASSWORD
$accessKey = Get-PlatformSecret AWS_ACCESS_KEY_ID
$secretKey = Get-PlatformSecret AWS_SECRET_ACCESS_KEY

kubectl --context $Context create namespace $Namespace --dry-run=client -o yaml | kubectl --context $Context apply -f -
kubectl --context $Context label namespace $Namespace mlops-foundry.io/feature-client=true --overwrite
kubectl --context $Context -n $Namespace create configmap feast-platform `
  "--from-literal=FEAST_PROJECT=$Project" "--from-literal=FEAST_BUCKET=$bucket" `
  "--from-literal=FEAST_REGISTRY=s3://$bucket/registry.pb" "--from-literal=FEAST_OFFLINE_PREFIX=s3://$bucket/offline" `
  '--from-literal=REDIS_HOST=redis.mlops.svc.cluster.local' '--from-literal=REDIS_PORT=6379' `
  '--from-literal=S3_ENDPOINT_URL=http://minio.mlops.svc.cluster.local:9000' `
  '--from-literal=FEAST_S3_ENDPOINT_URL=http://minio.mlops.svc.cluster.local:9000' `
  --dry-run=client -o yaml | kubectl --context $Context apply -f -
kubectl --context $Context -n $Namespace create secret generic feast-platform-access `
  "--from-literal=REDIS_PASSWORD=$redisPassword" "--from-literal=AWS_ACCESS_KEY_ID=$accessKey" `
  "--from-literal=AWS_SECRET_ACCESS_KEY=$secretKey" --dry-run=client -o yaml | kubectl --context $Context apply -f -

$jobName = "create-$bucket"
kubectl --context $Context -n mlops delete job $jobName --ignore-not-found | Out-Null
$job = @{
  apiVersion = 'batch/v1'; kind = 'Job'; metadata = @{ name = $jobName; namespace = 'mlops' }
  spec = @{ backoffLimit = 4; template = @{ spec = @{
    restartPolicy = 'OnFailure'; containers = @(@{
      name = 'create-bucket'; image = 'minio/mc:RELEASE.2025-08-13T08-35-41Z'
      env = @(
        @{ name = 'MINIO_ROOT_USER'; valueFrom = @{ secretKeyRef = @{ name = 'platform-secrets'; key = 'MINIO_ROOT_USER' } } },
        @{ name = 'MINIO_ROOT_PASSWORD'; valueFrom = @{ secretKeyRef = @{ name = 'platform-secrets'; key = 'MINIO_ROOT_PASSWORD' } } }
      )
      command = @('/bin/sh','-ec')
      args = @(('mc alias set minio http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"; mc mb --ignore-existing minio/{0}' -f $bucket))
    })
  } } }
} | ConvertTo-Json -Depth 12
$job | kubectl --context $Context apply -f -
kubectl --context $Context -n mlops wait "job/$jobName" --for=condition=Complete --timeout=2m
if ($LASTEXITCODE -ne 0) { throw "Failed to create MinIO bucket '$bucket'. Inspect job/$jobName in namespace mlops." }
kubectl --context $Context -n mlops delete job $jobName --wait=false | Out-Null

$redisPassword = $null; $accessKey = $null; $secretKey = $null
Write-Host "Feast project '$Project' is ready in namespace '$Namespace' with bucket '$bucket'."
