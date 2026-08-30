[CmdletBinding()]
param(
  [string]$Context = 'kind-mlops',
  [string]$PlatformNamespace = 'mlops',
  [string]$ModelNamespace = 'models',
  [string]$SecretName = 'kserve-minio-storage'
)

$ErrorActionPreference = 'Stop'

function Get-SecretValue([string]$Key) {
  $encoded = kubectl --context $Context -n $PlatformNamespace get secret platform-secrets -o "jsonpath={.data.$Key}"
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($encoded)) { throw "platform-secrets/$Key is required." }
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
}

$accessKey = Get-SecretValue 'AWS_ACCESS_KEY_ID'
$secretKey = Get-SecretValue 'AWS_SECRET_ACCESS_KEY'

kubectl --context $Context -n $ModelNamespace create secret generic $SecretName `
  "--from-literal=AWS_ACCESS_KEY_ID=$accessKey" `
  "--from-literal=AWS_SECRET_ACCESS_KEY=$secretKey" `
  --dry-run=client -o yaml |
  kubectl --context $Context apply -f -
if ($LASTEXITCODE -ne 0) { throw "Failed to apply secret '$SecretName'." }

kubectl --context $Context -n $ModelNamespace annotate secret $SecretName `
  'serving.kserve.io/s3-endpoint=minio.mlops.svc.cluster.local:9000' `
  'serving.kserve.io/s3-usehttps=0' `
  'serving.kserve.io/s3-region=us-east-1' `
  'serving.kserve.io/s3-usevirtualbucket=0' `
  'serving.kserve.io/s3-verifyssl=0' --overwrite
if ($LASTEXITCODE -ne 0) { throw 'Failed to annotate the KServe storage secret.' }

Write-Host "KServe MinIO storage credentials configured in namespace '$ModelNamespace'. No credentials were written to disk."
