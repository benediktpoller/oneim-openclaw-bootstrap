param(
  [Parameter(Mandatory=$true)]
  [string]$GatewayToken,

  [string]$GatewayUrl = 'ws://145.14.157.230:18789',

  [string]$NodeIdOrIp = ''
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

function Try-ParseJson($text) {
  if (-not $text) { return $null }
  $t = $text.TrimStart()
  if ($t.StartsWith('{') -or $t.StartsWith('[')) {
    return ($text | ConvertFrom-Json)
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

if ($NodeIdOrIp -ne '') {
  Section "Node describe"
  $descJson = (& openclaw nodes describe --url $GatewayUrl --token $GatewayToken --node $NodeIdOrIp --json 2>$null)
  $obj = $null
  if ($LASTEXITCODE -eq 0) { $obj = Try-ParseJson $descJson }
  if ($obj) {
    $obj | Format-List | Out-Host
  } else {
    Invoke-OpenClaw @('nodes','describe','--url',$GatewayUrl,'--token',$GatewayToken,'--node',$NodeIdOrIp) | Out-Host
  }
}

# restore env
$env:NODE_NO_WARNINGS = $__prevNodeNoWarnings
