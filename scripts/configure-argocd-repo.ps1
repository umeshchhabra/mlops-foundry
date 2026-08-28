[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GitHubToken
)

$ErrorActionPreference = 'Stop'
$secret = @{
    apiVersion = 'v1'
    kind = 'Secret'
    metadata = @{
        name = 'repo-mlops-foundry'
        namespace = 'argocd'
        labels = @{ 'argocd.argoproj.io/secret-type' = 'repository' }
    }
    stringData = @{
        type = 'git'
        url = 'https://github.com/umeshchhabra/mlops-foundry.git'
        username = 'x-access-token'
        password = $GitHubToken
    }
} | ConvertTo-Json -Depth 6

$secret | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Failed to configure the Argo CD repository credential.' }
