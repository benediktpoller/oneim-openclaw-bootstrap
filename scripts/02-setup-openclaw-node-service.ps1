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

function Ensure-ExecApprovalsFiles {
  $json = @'
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
'@

  $targets = @(
    "$env:USERPROFILE\.openclaw\exec-approvals.json",
    # Some installs run the scheduled task as the built-in Administrator account
    "C:\Users\Administrator\.openclaw\exec-approvals.json",
    # Worst-case: LocalSystem
    "C:\Windows\System32\config\systemprofile\.openclaw\exec-approvals.json"
  )

  foreach ($file in $targets) {
    try {
      $dir = Split-Path $file -Parent
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      $json | Set-Content -Encoding utf8 -Path $file
      Write-Host "Wrote approvals: $file" -ForegroundColor Green
    } catch {
      Write-Warning "Could not write approvals to $($file): $($_.Exception.Message)"
    }
  }
}

Require-Command openclaw

Section "Exec approvals"
Ensure-ExecApprovalsFiles

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

function Strip-Ansi($s) {
  if ($null -eq $s) { return $null }
  return ($s -replace "`e\[[0-9;?]*[A-Za-z]", "")
}

function Try-ParseJson($text) {
  if (-not $text) { return $null }
  $s = if ($text -is [array]) { ($text -join "`n") } else { [string]$text }
  $s = Strip-Ansi $s
  $t = $s.TrimStart()
  if ($t.StartsWith('{') -or $t.StartsWith('[')) {
    try { return ($t | ConvertFrom-Json) } catch { return $null }
  }
  return $null
}

function Get-PropValue($obj, [string]$name) {
  if ($null -eq $obj) { return $null }
  $p = $obj.PSObject.Properties[$name]
  if ($p) { return $p.Value }
  return $null
}

function Resolve-NodeId {
  param([string]$NodeIdOrIp, [string]$DisplayName)

  if ($NodeIdOrIp -and $NodeIdOrIp.Trim() -ne '' -and $NodeIdOrIp -match '^[a-f0-9]{64}$') {
    return $NodeIdOrIp
  }

  $devJson = (& openclaw devices list --json 2>$null)
  if ($LASTEXITCODE -ne 0) { return $null }
  $dev = Try-ParseJson $devJson
  if (-not $dev) { return $null }

  $paired = @($dev.paired | Where-Object { $_.clientId -eq 'node-host' -and $_.clientMode -eq 'node' })
  if ($paired.Count -eq 0) { return $null }

  if ($NodeIdOrIp -and $NodeIdOrIp.Trim() -ne '' -and ($NodeIdOrIp -match '^\d{1,3}(\.\d{1,3}){3}$')) {
    $paired = @($paired | Where-Object { $_.remoteIp -eq $NodeIdOrIp })
  } elseif ($DisplayName -and $DisplayName.Trim() -ne '') {
    $paired = @($paired | Where-Object { $_.displayName -eq $DisplayName })
  }

  if ($paired.Count -eq 0) { return $null }

  $best = $paired | Sort-Object -Property @{Expression={ $_.approvedAtMs };Descending=$true}, @{Expression={ $_.createdAtMs };Descending=$true} | Select-Object -First 1
  return $best.deviceId
}

Section "Gateway connectivity check"
Write-Host "Checking gateway connectivity (devices list)" -ForegroundColor Gray
$devCheck = (& openclaw devices list --json 2>$null)
if ($LASTEXITCODE -ne 0 -or -not (Try-ParseJson $devCheck)) {
  Write-Host "" 
  Write-Warning "Gateway connection failed. If you see 'disconnected (1008): pairing required', you must approve this VM as a DEVICE on the gateway."
  Write-Host "On the gateway host run:" -ForegroundColor Yellow
  Write-Host "  openclaw devices list" -ForegroundColor Yellow
  Write-Host "  openclaw devices approve <requestId>" -ForegroundColor Yellow
  Write-Host "" 
}

function Resolve-ConnectedNodeId {
  param([string]$NodeIdOrIp, [string]$DisplayName)

  $candidateIds = @()

  if ($NodeIdOrIp -and $NodeIdOrIp.Trim() -ne '' -and $NodeIdOrIp -match '^[a-f0-9]{64}$') {
    $candidateIds = @($NodeIdOrIp)
  } else {
    $devJson = (& openclaw devices list --json 2>$null)
    if ($LASTEXITCODE -eq 0) {
      $dev = Try-ParseJson $devJson
      if ($dev) {
        # In some repair flows, the connected node may show up under a CLI device id.
        # So consider all paired devices from this host and then probe nodes.describe.
        $paired = @($dev.paired | Where-Object { $_.platform -eq 'win32' })

        if ($NodeIdOrIp -and $NodeIdOrIp.Trim() -ne '' -and ($NodeIdOrIp -match '^\d{1,3}(\.\d{1,3}){3}$')) {
          $paired = @($paired | Where-Object { (Get-PropValue $_ 'remoteIp') -eq $NodeIdOrIp })
        }
        if ($DisplayName -and $DisplayName.Trim() -ne '') {
          $paired = @($paired | Where-Object { (Get-PropValue $_ 'displayName') -eq $DisplayName })
        }

        $candidateIds = @($paired |
          Sort-Object -Property @{Expression={ $_.approvedAtMs };Descending=$true}, @{Expression={ $_.createdAtMs };Descending=$true} |
          Select-Object -ExpandProperty deviceId -Unique)
      }
    }
  }

  if ($candidateIds.Count -eq 0) { return $null }

  # Prefer a CONNECTED node that supports system.run by probing nodes.describe.
  foreach ($id in $candidateIds) {
    $j = (& openclaw nodes describe --url $GatewayUrl --token $GatewayToken --node $id --json 2>$null)
    if ($LASTEXITCODE -eq 0) {
      $d = Try-ParseJson $j
      if ($d -and $d.connected -eq $true) {
        # If commands are present, ensure system.run exists.
        if (-not $d.commands -or ($d.commands -contains 'system.run')) {
          return $id
        }
      }
    }
  }

  # Fallback: newest candidate.
  return $candidateIds[0]
}

# Persist the resolved node id so later scripts don't need manual input.
Section "Resolve + persist node id"
$resolvedNodeId = Resolve-ConnectedNodeId -NodeIdOrIp $NodeIdOrIp -DisplayName $DisplayName
if ($resolvedNodeId) {
  $outFile = Join-Path (Join-Path $env:USERPROFILE '.openclaw') 'nodeid.txt'
  New-Item -ItemType Directory -Force -Path (Split-Path $outFile -Parent) | Out-Null
  $resolvedNodeId | Set-Content -Encoding ascii -NoNewline -Path $outFile
  Write-Host "Resolved nodeId: $resolvedNodeId" -ForegroundColor Green
  Write-Host "Wrote: $outFile" -ForegroundColor Green

  Write-Host ("Describe node: {0}" -f $resolvedNodeId) -ForegroundColor Gray
  Invoke-OpenClaw @('nodes','describe','--url',$GatewayUrl,'--token',$GatewayToken,'--node',$resolvedNodeId,'--json') | Out-Host
} else {
  Write-Warning "Could not resolve nodeId automatically. You can pass -NodeIdOrIp <nodeId|ip> or run: openclaw devices list --json"
}

Section "If this is a fresh VM (node pairing)"
Write-Host "Approve the PENDING NODE on the gateway:" -ForegroundColor Yellow
Write-Host "  openclaw nodes pending" -ForegroundColor Yellow
Write-Host "  openclaw nodes approve <requestId>" -ForegroundColor Yellow
