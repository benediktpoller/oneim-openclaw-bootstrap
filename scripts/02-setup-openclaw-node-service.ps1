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

# 1) Exec approvals
Ensure-ExecApprovalsFileForCurrentUser

# 2) Persist remote gateway defaults (so CLI uses remote by default)
& openclaw config set gateway.mode remote | Out-Host
& openclaw config set gateway.remote.url $GatewayUrl | Out-Host
& openclaw config set gateway.remote.token $GatewayToken | Out-Host

# 3) Install the node host as a service
$hp = Parse-HostPort $GatewayUrl
$gwHost = $hp[0]
$gwPort = $hp[1]

Write-Host "\nInstalling node service -> $gwHost:$gwPort (displayName=$DisplayName)" -ForegroundColor Cyan
& openclaw node install --host $gwHost --port $gwPort --display-name $DisplayName --force | Out-Host

Write-Host "\nRestarting node service" -ForegroundColor Cyan
& openclaw node restart | Out-Host

Write-Host "\nNode service status" -ForegroundColor Cyan
& openclaw node status | Out-Host

# 4) Quick remote visibility check using explicit url/token (no reliance on config reload)
Write-Host "\nGateway nodes list (explicit url/token)" -ForegroundColor Cyan
& openclaw nodes list --url $GatewayUrl --token $GatewayToken | Out-Host

if ($NodeIdOrIp -ne '') {
  Write-Host "\nNode describe (explicit url/token): $NodeIdOrIp" -ForegroundColor Cyan
  & openclaw nodes describe --url $GatewayUrl --token $GatewayToken --node $NodeIdOrIp | Out-Host
}

Write-Host "\nIf this is a fresh VM, approve the pending node on the Gateway:" -ForegroundColor Yellow
Write-Host "  openclaw nodes pending" -ForegroundColor Yellow
Write-Host "  openclaw nodes approve <requestId>" -ForegroundColor Yellow
