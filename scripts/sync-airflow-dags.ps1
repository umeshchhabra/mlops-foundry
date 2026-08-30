[CmdletBinding()]
param(
  [string]$Context = 'kind-mlops',
  [string]$Namespace = 'mlops',
  [string]$ClaimName = 'airflow-pvc'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dagSource = Join-Path $root 'pipelines/airflow/dags'
$podName = 'airflow-dag-sync'
if (-not (Test-Path $dagSource)) { throw "DAG directory not found: $dagSource" }

$pod = @"
apiVersion: v1
kind: Pod
metadata:
  name: $podName
  namespace: $Namespace
spec:
  restartPolicy: Never
  containers:
    - name: sync
      image: busybox:1.36
      command: [sh, -c, 'mkdir -p /opt/airflow/dags && sleep 3600']
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: { drop: [ALL] }
        seccompProfile: { type: RuntimeDefault }
      resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { cpu: 50m, memory: 64Mi } }
      volumeMounts: [{ name: dags, mountPath: /opt/airflow/dags }]
  volumes: [{ name: dags, persistentVolumeClaim: { claimName: $ClaimName } }]
"@

try {
  kubectl --context $Context delete pod $podName -n $Namespace --ignore-not-found --wait=true | Out-Null
  $pod | kubectl --context $Context apply -f - | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Failed to create the DAG synchronization pod.' }
  kubectl --context $Context wait -n $Namespace --for=condition=Ready "pod/$podName" --timeout=2m | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'DAG synchronization pod did not become ready.' }
  Push-Location $root
  try {
    # A repository-relative source avoids kubectl treating the colon in a
    # Windows drive letter as Kubernetes's pod:path separator.
    kubectl --context $Context cp 'pipelines/airflow/dags/.' "$Namespace/${podName}:/opt/airflow/dags"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to copy Airflow DAGs.' }
  }
  finally {
    Pop-Location
  }
}
finally {
  kubectl --context $Context delete pod $podName -n $Namespace --ignore-not-found --wait=false | Out-Null
}

Write-Host 'Airflow DAGs copied to airflow-pvc.'
