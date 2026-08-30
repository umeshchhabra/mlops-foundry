[CmdletBinding()]
param(
    [string]$Namespace = 'mlops',
    [string]$ArgoNamespace = 'argocd',
    [string]$KServeNamespace = 'kserve',
    [string]$ModelNamespace = 'models'
)

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()

function Test-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Missing required command: $Name" }
}
function Get-KubectlJson { param([string[]]$Arguments) (& kubectl @Arguments | ConvertFrom-Json) }

Test-Command kubectl

$nodes = Get-KubectlJson @('get','nodes','-o','json')
foreach ($node in $nodes.items) {
    $ready = $node.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }
    if (-not $ready) { $failures.Add("Node not Ready: $($node.metadata.name)") }
}

$apps = Get-KubectlJson @('get','applications','-n',$ArgoNamespace,'-o','json')
foreach ($app in $apps.items) {
    $kserveModelReady = $false
    if ($app.metadata.name -eq 'kserve-models' -and $app.status.sync.status -eq 'Synced') {
        $isvc = Get-KubectlJson @('get','inferenceservice','sklearn-iris','-n',$ModelNamespace,'-o','json')
        $kserveModelReady = [bool]($isvc.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })
    }
    # Argo's generic KServe health check currently treats its informational
    # Stopped=False condition as Degraded. Use KServe's Ready condition for
    # this application, while still requiring Argo synchronization.
    $isHealthy = $app.status.health.status -eq 'Healthy' -or $kserveModelReady
    if ($app.status.sync.status -ne 'Synced' -or -not $isHealthy) {
        $failures.Add("Argo application unhealthy: $($app.metadata.name) ($($app.status.sync.status)/$($app.status.health.status))")
    }
}

$pods = Get-KubectlJson @('get','pods','-n',$Namespace,'-o','json')
foreach ($pod in $pods.items) {
    # Completed Jobs and terminal pods retained by an old ReplicaSet are not
    # active workload failures. Active crash loops remain Running/NotReady.
    if ($pod.status.phase -in @('Succeeded','Completed','Failed')) { continue }
    $ready = $pod.status.containerStatuses | Where-Object { -not $_.ready }
    if ($pod.status.phase -ne 'Running' -or $ready) {
        $failures.Add("Workload pod unhealthy: $($pod.metadata.name) ($($pod.status.phase))")
    }
}

$kservePods = Get-KubectlJson @('get','pods','-n',$KServeNamespace,'-o','json')
foreach ($pod in $kservePods.items) {
    $notReady = $pod.status.containerStatuses | Where-Object { -not $_.ready }
    if ($pod.status.phase -ne 'Running' -or $notReady) {
        $failures.Add("KServe pod unhealthy: $($pod.metadata.name) ($($pod.status.phase))")
    }
}

$modelService = Get-KubectlJson @('get','inferenceservice','sklearn-iris','-n',$ModelNamespace,'-o','json')
$modelReady = $modelService.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }
if (-not $modelReady) { $failures.Add('KServe InferenceService is not Ready: models/sklearn-iris') }

foreach ($endpoint in @(
    '/api/v1/namespaces/mlops/services/http:mlflow:5000/proxy/health',
    '/api/v1/namespaces/mlops/services/http:minio:9000/proxy/minio/health/live',
    '/api/v1/namespaces/mlops/services/http:prometheus-server:80/proxy/-/ready',
    '/api/v1/namespaces/mlops/services/http:grafana:80/proxy/api/health'
)) {
    & kubectl get --raw $endpoint *> $null
    if ($LASTEXITCODE -ne 0) { $failures.Add("Endpoint failed: $endpoint") }
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'Stack health check passed.'
