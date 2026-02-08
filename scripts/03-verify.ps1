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
Invoke-OpenClaw @('node','status') | Out-Host

Section "Nodes list"
Invoke-OpenClaw @('nodes','list','--url',$GatewayUrl,'--token',$GatewayToken) | Out-Host

if ($NodeIdOrIp -ne '') {
  Section "Node describe"
  Invoke-OpenClaw @('nodes','describe','--url',$GatewayUrl,'--token',$GatewayToken,'--node',$NodeIdOrIp) | Out-Host
}
