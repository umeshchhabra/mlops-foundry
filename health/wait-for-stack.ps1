[CmdletBinding()]
param(
  [int]$TimeoutMinutes = 15,
  [int]$IntervalSeconds = 15
)

$ErrorActionPreference = 'Continue'
$check = Join-Path $PSScriptRoot 'check-stack.ps1'
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
do {
  & $check *> $null
  if ($LASTEXITCODE -eq 0) {
    Write-Host 'Stack is healthy.'
    exit 0
  }
  Write-Host 'Stack is still reconciling...'
  Start-Sleep -Seconds $IntervalSeconds
} while ((Get-Date) -lt $deadline)

Write-Error "Stack did not become healthy within $TimeoutMinutes minutes."
& $check
exit 1
