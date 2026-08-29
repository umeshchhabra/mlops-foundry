[CmdletBinding()]
param([string]$Context = 'kind-mlops', [string]$Namespace = 'mlops')

$ErrorActionPreference = 'Stop'
function New-RandomSecret([int]$Bytes = 32) {
  $buffer = New-Object byte[] $Bytes
  # Use the instance API for Windows PowerShell/.NET Framework compatibility.
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($buffer) }
  finally { $rng.Dispose() }
  [Convert]::ToBase64String($buffer).Replace('+', '-').Replace('/', '_')
}
$dbUriEncoded = kubectl --context $Context get secret platform-secrets -n $Namespace -o jsonpath='{.data.AIRFLOW_DB_URI}'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($dbUriEncoded)) { throw 'platform-secrets/AIRFLOW_DB_URI is required.' }
$dbUri = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($dbUriEncoded))
$adminPassword = Read-Host 'Choose the Airflow admin password' -AsSecureString
$adminPasswordText = [System.Net.NetworkCredential]::new('', $adminPassword).Password
$secrets = @(
  @{ Name = 'airflow-metadata'; Key = 'connection'; Value = $dbUri },
  @{ Name = 'airflow-fernet-key'; Key = 'fernet-key'; Value = New-RandomSecret },
  @{ Name = 'airflow-api-secret'; Key = 'api-secret-key'; Value = New-RandomSecret },
  @{ Name = 'airflow-jwt-secret'; Key = 'jwt-secret'; Value = New-RandomSecret },
  @{ Name = 'airflow-admin'; Key = 'password'; Value = $adminPasswordText }
)
foreach ($secret in $secrets) {
  kubectl --context $Context -n $Namespace create secret generic $secret.Name "--from-literal=$($secret.Key)=$($secret.Value)" --dry-run=client -o yaml | kubectl --context $Context apply -f -
  if ($LASTEXITCODE -ne 0) { throw "Failed to apply secret '$($secret.Name)'." }
}
Write-Host 'Airflow secrets configured. They were applied to Kubernetes and not written to disk.'
