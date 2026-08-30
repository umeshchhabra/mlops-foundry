[CmdletBinding()]
param(
  [string]$Context = 'kind-mlops',
  [string]$Namespace = 'mlops'
)

$ErrorActionPreference = 'Stop'
$serviceJson = kubectl --context $Context -n default get service kubernetes -o json
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the Kubernetes API service.' }
$service = $serviceJson | ConvertFrom-Json
$sliceJson = kubectl --context $Context -n default get endpointslices -l kubernetes.io/service-name=kubernetes -o json
if ($LASTEXITCODE -ne 0) { throw 'Cannot read Kubernetes API endpoints.' }
$slices = $sliceJson | ConvertFrom-Json
$addresses = @($service.spec.clusterIPs) + @($slices.items.endpoints.addresses)
$addresses = @($addresses | Where-Object { $_ -and $_ -ne 'None' } | Sort-Object -Unique)
$ports = @(@($service.spec.ports.port) + @($slices.items.ports.port) | Where-Object { $_ } | Sort-Object -Unique)
if (-not $addresses.Count -or -not $ports.Count) { throw 'Kubernetes API addresses or ports are missing.' }

# Include both service and endpoint addresses because CNI implementations can
# enforce egress either before or after service destination NAT.
$peers = @($addresses | ForEach-Object {
  $ip = [Net.IPAddress]::Parse($_)
  $prefix = if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) { 128 } else { 32 }
  @{ ipBlock = @{ cidr = "$_/$prefix" } }
})
$policy = @{
  apiVersion = 'networking.k8s.io/v1'
  kind = 'NetworkPolicy'
  metadata = @{ name = 'monitoring-allow-kubernetes-api'; namespace = $Namespace }
  spec = @{
    podSelector = @{ matchExpressions = @(@{
      key = 'app.kubernetes.io/name'; operator = 'In'; values = @('prometheus', 'kube-state-metrics')
    }) }
    policyTypes = @('Egress')
    egress = @(@{
      to = $peers
      ports = @($ports | ForEach-Object { @{ protocol = 'TCP'; port = [int]$_ } })
    })
  }
}
$policy | ConvertTo-Json -Depth 12 | kubectl --context $Context apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Failed to configure monitoring API egress.' }
Write-Host 'Monitoring API-only egress configured from current cluster addresses.'
