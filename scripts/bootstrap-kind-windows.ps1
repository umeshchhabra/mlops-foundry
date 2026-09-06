[CmdletBinding()]
param(
  [string] $ClusterName = 'mlops',
  [string] $DataDir = 'C:\mlops-data'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($command in 'docker', 'kind', 'kubectl', 'helm') {
  if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Missing: $command" }
}

$resolvedDataDir = (New-Item -ItemType Directory -Path $DataDir -Force).FullName.Replace('\', '/')
$config = New-TemporaryFile
try {
  @"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraMounts: [{ hostPath: $resolvedDataDir, containerPath: /data }]
    extraPortMappings:
      - { containerPort: 30080, hostPort: 8080, protocol: TCP }
      - { containerPort: 30500, hostPort: 5000, protocol: TCP }
      - { containerPort: 30900, hostPort: 9002, protocol: TCP }
      - { containerPort: 30901, hostPort: 9003, protocol: TCP }
      - { containerPort: 31080, hostPort: 8090, protocol: TCP }
      - { containerPort: 32000, hostPort: 9000, protocol: TCP }
      - { containerPort: 32001, hostPort: 9001, protocol: TCP }
  - role: worker
    extraMounts: [{ hostPath: $resolvedDataDir, containerPath: /data }]
  - role: worker
    extraMounts: [{ hostPath: $resolvedDataDir, containerPath: /data }]
  - role: worker
    extraMounts: [{ hostPath: $resolvedDataDir, containerPath: /data }]
"@ | Set-Content -Path $config -Encoding utf8NoBOM

  kind create cluster --name $ClusterName --config $config
  kubectl apply -f (Join-Path $root 'infra/platform/overlays/kind-linux/storage.yaml')
  & (Join-Path $PSScriptRoot 'configure-monitoring-network.ps1') -Context "kind-$ClusterName"
  docker build --tag mlflow:3.4.0-psycopg2 --file (Join-Path $root 'images/mlflow/Dockerfile') (Join-Path $root 'images/mlflow')
  kind load docker-image mlflow:3.4.0-psycopg2 --name $ClusterName

  function New-RandomSecret {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '').Substring(0, 32)
  }
  $postgresPassword = New-RandomSecret
  $airflowPassword = New-RandomSecret
  $minioPassword = New-RandomSecret
  $grafanaPassword = New-RandomSecret
  kubectl create secret generic platform-secrets -n mlops `
    "--from-literal=POSTGRES_USER=mlflow" "--from-literal=POSTGRES_PASSWORD=$postgresPassword" `
    "--from-literal=AIRFLOW_DB_PASSWORD=$airflowPassword" "--from-literal=AIRFLOW_DB_URI=postgresql+psycopg2://airflow:$airflowPassword@postgres:5432/airflow" `
    "--from-literal=MLFLOW_DB_URI=postgresql+psycopg2://mlflow:$postgresPassword@postgres:5432/mlflow" `
    "--from-literal=MINIO_ROOT_USER=mlops-admin" "--from-literal=MINIO_ROOT_PASSWORD=$minioPassword" `
    "--from-literal=AWS_ACCESS_KEY_ID=mlops-admin" "--from-literal=AWS_SECRET_ACCESS_KEY=$minioPassword" `
    "--from-literal=GRAFANA_ADMIN_USER=admin" "--from-literal=GRAFANA_ADMIN_PASSWORD=$grafanaPassword"
  if ($LASTEXITCODE -ne 0) { throw 'Failed to create platform-secrets.' }
  Write-Host 'Cluster, storage, local images, and runtime-only secrets are ready. Configure Argo CD next.'
}
finally {
  Remove-Item -LiteralPath $config -Force -ErrorAction SilentlyContinue
}
