param(
  [string]$BaseUrl = "http://127.0.0.1:8384",
  [string]$ConfigPath = "$env:LOCALAPPDATA\Syncthing\config.xml"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) {
  throw "Syncthing config not found: $ConfigPath"
}

[xml]$config = Get-Content -Path $ConfigPath
$apiKey = $config.configuration.gui.apikey
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw "Syncthing API key not found in $ConfigPath"
}

$headers = @{ "X-API-Key" = $apiKey }

function Get-SyncthingJson([string]$Path) {
  $response = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 -Headers $headers "$BaseUrl$Path"
  return $response.Content | ConvertFrom-Json
}

$health = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 "$BaseUrl/rest/noauth/health"
$version = Get-SyncthingJson "/rest/system/version"
$status = Get-SyncthingJson "/rest/system/status"
$connections = Get-SyncthingJson "/rest/system/connections"

$connectionCount = 0
if ($connections.connections -ne $null) {
  $connectionCount = ($connections.connections.PSObject.Properties | Measure-Object).Count
}

[pscustomobject]@{
  HealthStatus = $health.StatusCode
  Version = $version.version
  LongVersion = $version.longVersion
  DeviceId = $status.myID
  UptimeSeconds = $status.uptime
  AllocBytes = $status.alloc
  DiscoveryMethods = $status.discoveryMethods
  ConnectionCount = $connectionCount
  InBytesTotal = $connections.total.inBytesTotal
  OutBytesTotal = $connections.total.outBytesTotal
}
