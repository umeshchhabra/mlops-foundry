[CmdletBinding()]
param(
    [string]$HostName = '10.0.0.113',
    [string]$UserName = 'agent',
    [string]$KeyPath = "$env:USERPROFILE\.ssh\mlops_raspberry_pi_ed25519"
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue)) {
    throw 'OpenSSH client tools are required.'
}
if (-not (Test-Path -LiteralPath $KeyPath)) {
    ssh-keygen.exe -t ed25519 -a 64 -f $KeyPath -C 'mlops-foundry@raspberry-pi' -N ''
}

$publicKey = Get-Content -LiteralPath "$KeyPath.pub" -Raw
# SSH prompts locally for the Pi password once. It is neither printed nor
# written to disk; subsequent logins use the private key on this laptop.
$publicKey | ssh.exe -o StrictHostKeyChecking=ask -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no "$UserName@$HostName" 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys'
if ($LASTEXITCODE -ne 0) { throw 'SSH key installation failed.' }

ssh.exe -i $KeyPath -o BatchMode=yes "$UserName@$HostName" 'echo SSH key authentication works'
if ($LASTEXITCODE -ne 0) { throw 'Key installation completed but key authentication could not be verified.' }
Write-Host "SSH key authentication configured for $UserName@$HostName."
