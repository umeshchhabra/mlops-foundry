[CmdletBinding()]
param(
  [string]$Context = 'kind-mlops',
  [string]$Namespace = 'argocd'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
kubectl --context $Context apply -f (Join-Path $root 'infra/bootstrap/argocd-server-nodeport.yaml')
if ($LASTEXITCODE -ne 0) { throw 'Failed to expose the Argo CD server.' }

# TLS is intentionally out of scope for this trusted local stack. Running the
# server in HTTP mode avoids a self-signed certificate warning on localhost.
kubectl --context $Context -n $Namespace patch configmap argocd-cmd-params-cm `
  --type merge --patch '{"data":{"server.insecure":"true"}}' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to configure local Argo CD HTTP mode.' }
kubectl --context $Context -n $Namespace rollout restart deployment/argocd-server | Out-Null
kubectl --context $Context -n $Namespace rollout status deployment/argocd-server --timeout=3m | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Argo CD server did not become ready.' }

Write-Host 'Argo CD is available at http://localhost:8080.'
