param(
  [Parameter(Mandatory)] [string] $PostgresBackup,
  [switch] $Apply
)

if (-not (Test-Path $PostgresBackup)) { throw "Backup file not found: $PostgresBackup" }
if (-not $Apply) {
  Write-Output "Dry run: validated $PostgresBackup. Re-run with -Apply to restore into the mlops PostgreSQL service."
  exit 0
}

if ($PostgresBackup -match '\.gz$') {
  if (-not (Get-Command gzip -ErrorAction SilentlyContinue)) {
    throw 'The -Apply path for .gz backups requires gzip on the client.'
  }
  & gzip -dc -- $PostgresBackup |
    kubectl -n mlops exec -i deploy/postgres -- psql -U mlflow
} else {
  Get-Content -Raw -Path $PostgresBackup |
    kubectl -n mlops exec -i deploy/postgres -- psql -U mlflow
}
Write-Output 'Restore stream completed. Verify application tables before using the restored data.'
