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

# A ready Prometheus UI can still have broken Kubernetes discovery. Require
# both a successful exporter scrape and node metrics for every current node.
foreach ($check in @(
    @{ Query = 'up{service="prometheus-kube-state-metrics"} == 1'; Minimum = 1; Name = 'kube-state-metrics scrape' },
    @{ Query = 'count(count by (node) (kube_node_info))'; Minimum = @($nodes.items).Count; Name = 'Kubernetes node metrics' },
    @{ Query = 'count(up{job="kubernetes-apiservers"} == 1)'; Minimum = 1; Name = 'API server scrape' },
    @{ Query = 'up{job="kserve-controller"} == 1'; Minimum = 1; Name = 'KServe controller scrape' },
    @{ Query = 'count(up{job="kubernetes-nodes"} == 1)'; Minimum = @($nodes.items).Count; Name = 'Kubelet scrapes' },
    @{ Query = 'count(up{job="kubernetes-nodes-cadvisor"} == 1)'; Minimum = @($nodes.items).Count; Name = 'cAdvisor scrapes' }
)) {
    try {
        $query = [Uri]::EscapeDataString($check.Query)
        $raw = & kubectl --request-timeout=15s get --raw "/api/v1/namespaces/$Namespace/services/http:prometheus-server:80/proxy/api/v1/query?query=$query"
        if ($LASTEXITCODE -ne 0) { throw 'Prometheus query failed.' }
        $result = $raw | ConvertFrom-Json
        if ($result.status -ne 'success' -or -not @($result.data.result).Count) { throw 'No metric samples returned.' }
        if ([double]$result.data.result[0].value[1] -lt $check.Minimum) {
            throw "Expected a value of at least $($check.Minimum)."
        }
    }
    catch { $failures.Add("Monitoring check failed: $($check.Name): $($_.Exception.Message)") }
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'Stack health check passed.'
