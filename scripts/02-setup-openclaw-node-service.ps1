param(
  [Parameter(Mandatory=$true)]
  [string]$GatewayToken,

  [string]$GatewayUrl = 'ws://145.14.157.230:18789',

  [string]$DisplayName = $env:COMPUTERNAME,

  # IP/id of this Windows box as seen by the Gateway (optional)
  [string]$NodeIdOrIp = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Section($t) {
  Write-Host "`n=== $t ===" -ForegroundColor Cyan
}

function Invoke-OpenClaw {
  param([Parameter(Mandatory=$true)][string[]]$Args)

  # Reduce noisy Node deprecation warnings in user output.
  $prev = $env:NODE_NO_WARNINGS
  $env:NODE_NO_WARNINGS = '1'
  try {
    & openclaw @Args
    return $LASTEXITCODE
  } finally {
    $env:NODE_NO_WARNINGS = $prev
  }
}

function Require-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Missing dependency: $name not found in PATH. Run scripts/01-install-tools.ps1 first."
  }
}

function Parse-HostPort([string]$Url) {
  $u = [uri]$Url
  $hostName = $u.Host
  $port = if ($u.Port -gt 0) { $u.Port } else { 18789 }
  return @($hostName, $port)
}

function Ensure-ExecApprovalsFileForCurrentUser {
  $dir = Join-Path $env:USERPROFILE '.openclaw'
  $file = Join-Path $dir 'exec-approvals.json'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null

  @'
{
  "version": 1,
  "defaults": {
    "security": "full",
    "ask": "off",
    "askFallback": "deny",
    "autoAllowSkills": false
  },
  "agents": {}
}
'@ | Set-Content -Encoding utf8 -Path $file

  Write-Host "Wrote approvals: $file" -ForegroundColor Green
}

Require-Command openclaw

Section "Exec approvals"
Ensure-ExecApprovalsFileForCurrentUser

Section "Configure remote gateway defaults (local CLI)"
Invoke-OpenClaw @('config','set','gateway.mode','remote') | Out-Host
Invoke-OpenClaw @('config','set','gateway.remote.url', $GatewayUrl) | Out-Host
Invoke-OpenClaw @('config','set','gateway.remote.token', $GatewayToken) | Out-Host

Section "Install node host as a service"
$hp = Parse-HostPort $GatewayUrl
$gwHost = $hp[0]
$gwPort = $hp[1]

Write-Host ("Target Gateway: {0}:{1}" -f $gwHost, $gwPort) -ForegroundColor Gray
Write-Host ("Node display name: {0}" -f $DisplayName) -ForegroundColor Gray

Invoke-OpenClaw @('node','install','--host',$gwHost,'--port',[string]$gwPort,'--display-name',$DisplayName,'--force') | Out-Host

Section "Start / restart node service"
Invoke-OpenClaw @('node','restart') | Out-Host

Section "Node service status"
Invoke-OpenClaw @('node','status') | Out-Host

Section "Gateway connectivity check"
Write-Host "Listing nodes (explicit --url/--token)" -ForegroundColor Gray
$exit = Invoke-OpenClaw @('nodes','list','--url',$GatewayUrl,'--token',$GatewayToken,'--json')

if ($exit -ne 0) {
  Write-Host "" 
  Write-Warning "Gateway connection failed. If you see 'disconnected (1008): pairing required', you must approve this VM as a DEVICE on the gateway."
  Write-Host "On the gateway host run:" -ForegroundColor Yellow
  Write-Host "  openclaw devices list" -ForegroundColor Yellow
  Write-Host "  openclaw devices approve <requestId>" -ForegroundColor Yellow
  Write-Host "" 
}

if ($NodeIdOrIp -ne '') {
  Write-Host ("Describe node: {0}" -f $NodeIdOrIp) -ForegroundColor Gray
  Invoke-OpenClaw @('nodes','describe','--url',$GatewayUrl,'--token',$GatewayToken,'--node',$NodeIdOrIp,'--json') | Out-Host
}

Section "If this is a fresh VM (node pairing)"
Write-Host "Approve the PENDING NODE on the gateway:" -ForegroundColor Yellow
Write-Host "  openclaw nodes pending" -ForegroundColor Yellow
Write-Host "  openclaw nodes approve <requestId>" -ForegroundColor Yellow
