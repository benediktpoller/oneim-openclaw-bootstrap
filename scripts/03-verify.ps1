param(
  [Parameter(Mandatory=$true)]
  [string]$GatewayToken,

  [string]$GatewayUrl = 'ws://145.14.157.230:18789',

  # Optional: node id or IP. If omitted, the script auto-selects a paired node-host device.
  [string]$NodeIdOrIp = '',

  # Used only for auto-selection when NodeIdOrIp is empty.
  [string]$NodeDisplayName = 'IAMSERVER'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Keep output readable: suppress Node deprecation warnings from the openclaw wrapper.
$__prevNodeNoWarnings = $env:NODE_NO_WARNINGS
$env:NODE_NO_WARNINGS = '1'

function Section($t) {
  Write-Host "`n=== $t ===" -ForegroundColor Cyan
}

function Invoke-OpenClaw {
  param([Parameter(Mandatory=$true)][string[]]$Args)
  & openclaw @Args
  return $LASTEXITCODE
}

function Strip-Ansi($s) {
  if ($null -eq $s) { return $null }
  # Remove common ANSI escape sequences (ESC[...)
  return ($s -replace "`e\[[0-9;?]*[A-Za-z]", "")
}

function Try-ParseJson($text) {
  if (-not $text) { return $null }

  # When capturing output, PowerShell may return string[]; normalize.
  $s = if ($text -is [array]) { ($text -join "`n") } else { [string]$text }

  $s = Strip-Ansi $s
  $t = $s.TrimStart()

  if ($t.StartsWith('{') -or $t.StartsWith('[')) {
    try {
      return ($t | ConvertFrom-Json)
    } catch {
      return $null
    }
  }

  return $null
}

# Ensure env var is restored even if the script errors
trap {
  $env:NODE_NO_WARNINGS = $__prevNodeNoWarnings
  break
}

Section "Node service"
# Use --json to avoid box-drawing glyph issues on Windows consoles.
$nodeStatusJson = (& openclaw node status --json 2>$null)
if ($LASTEXITCODE -eq 0) {
  $obj = Try-ParseJson $nodeStatusJson
  if ($obj) {
    $obj | Format-List | Out-Host
  } else {
    Invoke-OpenClaw @('node','status') | Out-Host
  }
} else {
  Invoke-OpenClaw @('node','status') | Out-Host
}

Section "Nodes list"
$nodesJson = (& openclaw nodes list --url $GatewayUrl --token $GatewayToken --json 2>$null)
$obj = $null
if ($LASTEXITCODE -eq 0) { $obj = Try-ParseJson $nodesJson }
if ($obj) {
  $obj | Format-Table -AutoSize | Out-Host
} else {
  # Fallback to plain output (some builds print non-JSON even with --json)
  Invoke-OpenClaw @('nodes','list','--url',$GatewayUrl,'--token',$GatewayToken) | Out-Host
}

function Resolve-NodeId {
  param([string]$NodeIdOrIp, [string]$NodeDisplayName)

  if ($NodeIdOrIp -and $NodeIdOrIp.Trim() -ne '') {
    # If they gave a 64-hex node id, use it.
    if ($NodeIdOrIp -match '^[a-f0-9]{64}$') { return $NodeIdOrIp }
  }

  # Reliable JSON source: devices list.
  $devJson = (& openclaw devices list --json 2>$null)
  if ($LASTEXITCODE -ne 0) { return $null }
  $dev = Try-ParseJson $devJson
  if (-not $dev) { return $null }

  $paired = @($dev.paired | Where-Object { $_.clientId -eq 'node-host' -and $_.clientMode -eq 'node' })
  if ($paired.Count -eq 0) { return $null }

  if ($NodeIdOrIp -and $NodeIdOrIp.Trim() -ne '' -and ($NodeIdOrIp -match '^\d{1,3}(\.\d{1,3}){3}$')) {
    $paired = @($paired | Where-Object { $_.remoteIp -eq $NodeIdOrIp })
  } elseif ($NodeDisplayName -and $NodeDisplayName.Trim() -ne '') {
    $paired = @($paired | Where-Object { $_.displayName -eq $NodeDisplayName })
  }

  if ($paired.Count -eq 0) { return $null }

  # Pick newest approval/creation.
  $best = $paired | Sort-Object -Property @{Expression={ $_.approvedAtMs };Descending=$true}, @{Expression={ $_.createdAtMs };Descending=$true} | Select-Object -First 1
  return $best.deviceId
}

$resolvedNodeId = Resolve-NodeId -NodeIdOrIp $NodeIdOrIp -NodeDisplayName $NodeDisplayName
if ($resolvedNodeId) {
  Section "Node describe"
  Write-Host "Using nodeId: $resolvedNodeId" -ForegroundColor Gray
  $descJson = (& openclaw nodes describe --url $GatewayUrl --token $GatewayToken --node $resolvedNodeId --json 2>$null)
  $obj = $null
  if ($LASTEXITCODE -eq 0) { $obj = Try-ParseJson $descJson }
  if ($obj) {
    $obj | Format-List | Out-Host
  } else {
    Invoke-OpenClaw @('nodes','describe','--url',$GatewayUrl,'--token',$GatewayToken,'--node',$resolvedNodeId) | Out-Host
  }
} elseif ($NodeIdOrIp -and $NodeIdOrIp.Trim() -ne '') {
  # As a last resort, try whatever they provided.
  Section "Node describe"
  Invoke-OpenClaw @('nodes','describe','--url',$GatewayUrl,'--token',$GatewayToken,'--node',$NodeIdOrIp) | Out-Host
} else {
  Section "Node describe"
  Write-Warning "No node id provided and auto-detection failed. Try: openclaw devices list --json (look for clientId=node-host)"
}

# restore env
$env:NODE_NO_WARNINGS = $__prevNodeNoWarnings
