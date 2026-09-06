[CmdletBinding()]
param(
  [string]$Context = 'kind-mlops',
  [string]$Namespace = 'mlops'
)

$ErrorActionPreference = 'Stop'

function Get-SecretValue {
  param(
    [Parameter(Mandatory)][string]$SecretNamespace,
    [Parameter(Mandatory)][string]$SecretName,
    [Parameter(Mandatory)][string]$Key
  )

  $encoded = kubectl --context $Context -n $SecretNamespace get secret $SecretName "-o=jsonpath={.data.$Key}" 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($encoded)) {
    return '<not available>'
  }

  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
}

kubectl --context $Context cluster-info *> $null
if ($LASTEXITCODE -ne 0) { throw "Kubernetes context '$Context' is not reachable." }

$credentials = @(
  [pscustomobject]@{ Service = 'Argo CD'; Username = 'admin'; Password = Get-SecretValue argocd 'argocd-initial-admin-secret' 'password' },
  [pscustomobject]@{ Service = 'Airflow'; Username = 'admin'; Password = Get-SecretValue $Namespace 'airflow-admin' 'password' },
  [pscustomobject]@{ Service = 'Grafana'; Username = Get-SecretValue $Namespace 'platform-secrets' 'GRAFANA_ADMIN_USER'; Password = Get-SecretValue $Namespace 'platform-secrets' 'GRAFANA_ADMIN_PASSWORD' },
  [pscustomobject]@{ Service = 'MinIO'; Username = Get-SecretValue $Namespace 'platform-secrets' 'MINIO_ROOT_USER'; Password = Get-SecretValue $Namespace 'platform-secrets' 'MINIO_ROOT_PASSWORD' },
  [pscustomobject]@{ Service = 'Redis'; Username = 'default'; Password = Get-SecretValue $Namespace 'platform-secrets' 'REDIS_PASSWORD' },
  [pscustomobject]@{ Service = 'PostgreSQL'; Username = Get-SecretValue $Namespace 'platform-secrets' 'POSTGRES_USER'; Password = Get-SecretValue $Namespace 'platform-secrets' 'POSTGRES_PASSWORD' }
)

$credentials | Format-Table -AutoSize
Write-Host 'MLflow and Prometheus do not require login. KServe does not provide a user-facing login.'
Write-Warning 'These values are sensitive. Do not paste the output into chat, logs, documentation, or source control.'
