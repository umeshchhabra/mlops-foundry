[CmdletBinding()]
param(
    [securestring]$GitHubToken
)

$ErrorActionPreference = 'Stop'
if (-not $GitHubToken) {
    $GitHubToken = Read-Host -Prompt 'GitHub fine-grained token (read access to mlops-foundry)' -AsSecureString
}
$tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($GitHubToken)
try {
    $tokenValue = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
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
        password = $tokenValue
    }
} | ConvertTo-Json -Depth 6

$secret | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Failed to configure the Argo CD repository credential.' }
}
finally {
    if ($tokenPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer)
    }
}
