param(
  [Parameter(Mandatory)] [string] $RunId,
  [string] $TrackingUri = 'http://localhost:5000',
  [string] $ModelUri,
  [string] $OutputPath = 'infra/platform/kserve/models/promoted-inferenceservice.yaml'
)

$run = Invoke-RestMethod -Uri "$TrackingUri/api/2.0/mlflow/runs/get?run_id=$RunId"
if ($run.run.info.status -ne 'FINISHED') {
  throw "Run '$RunId' is not FINISHED (status: $($run.run.info.status))."
}
if (-not $ModelUri) {
  $artifactUri = $run.run.info.artifact_uri
  if (-not $artifactUri) { throw "Run '$RunId' has no artifact URI." }
  $ModelUri = "$artifactUri/model"
}

$manifest = @"
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: promoted-model
  namespace: models
spec:
  predictor:
    serviceAccountName: kserve-model
    model:
      modelFormat:
        name: sklearn
        version: "1"
      storageUri: $ModelUri
      resources:
        requests: { cpu: 100m, memory: 256Mi }
        limits: { cpu: 500m, memory: 512Mi }
"@

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
Set-Content -Path $OutputPath -Value $manifest -Encoding utf8NoBOM
Write-Output "Validated MLflow run $RunId and wrote $OutputPath"
