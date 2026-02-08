param(
  [Parameter(Mandatory=$true)]
  [string]$GatewayToken,

  [string]$GatewayUrl = 'ws://145.14.157.230:18789',

  [string]$NodeIdOrIp = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Section($t) {
  Write-Host "`n=== $t ===" -ForegroundColor Cyan
}

function Invoke-OpenClaw {
  param([Parameter(Mandatory=$true)][string[]]$Args)

  $prev = $env:NODE_NO_WARNINGS
  $env:NODE_NO_WARNINGS = '1'
  try {
    & openclaw @Args
    return $LASTEXITCODE
  } finally {
    $env:NODE_NO_WARNINGS = $prev
  }
}

Section "Node service"
# Use --json to avoid box-drawing glyph issues on Windows consoles.
$nodeStatusJson = (& openclaw node status --json)
if ($LASTEXITCODE -eq 0 -and $nodeStatusJson) {
  $nodeStatus = $nodeStatusJson | ConvertFrom-Json
  $nodeStatus | Format-List | Out-Host
} else {
  Invoke-OpenClaw @('node','status') | Out-Host
}

Section "Nodes list"
$nodesJson = (& openclaw nodes list --url $GatewayUrl --token $GatewayToken --json)
if ($LASTEXITCODE -eq 0 -and $nodesJson) {
  $nodes = $nodesJson | ConvertFrom-Json
  $nodes | Format-Table -AutoSize | Out-Host
} else {
  Invoke-OpenClaw @('nodes','list','--url',$GatewayUrl,'--token',$GatewayToken) | Out-Host
}

if ($NodeIdOrIp -ne '') {
  Section "Node describe"
  $descJson = (& openclaw nodes describe --url $GatewayUrl --token $GatewayToken --node $NodeIdOrIp --json)
  if ($LASTEXITCODE -eq 0 -and $descJson) {
    $desc = $descJson | ConvertFrom-Json
    $desc | Format-List | Out-Host
  } else {
    Invoke-OpenClaw @('nodes','describe','--url',$GatewayUrl,'--token',$GatewayToken,'--node',$NodeIdOrIp) | Out-Host
  }
}
