param(
  [string]$TaskName = 'OpenClaw Node'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

Section "Identity / profile"
whoami
Write-Host "USERPROFILE=$env:USERPROFILE" -ForegroundColor Gray

Section "Approvals files (common locations)"
$paths = @(
  "$env:USERPROFILE\.openclaw\exec-approvals.json",
  "C:\Users\Administrator\.openclaw\exec-approvals.json",
  "C:\Windows\System32\config\systemprofile\.openclaw\exec-approvals.json"
)
foreach ($p in $paths) {
  if (Test-Path $p) {
    Write-Host "FOUND: $p" -ForegroundColor Green
    Get-Content $p | Select-Object -First 30
  } else {
    Write-Host "MISSING: $p" -ForegroundColor Yellow
  }
  Write-Host "" 
}

Section "Scheduled Task state"
schtasks /Query /TN $TaskName /FO LIST /V | more

Section "TaskScheduler Operational events (last 50)"
try {
  Get-WinEvent -LogName Microsoft-Windows-TaskScheduler/Operational -MaxEvents 50 |
    Where-Object { $_.Message -like "*$TaskName*" } |
    Select-Object TimeCreated, Id, LevelDisplayName, Message |
    Format-List | Out-Host
} catch {
  Write-Warning "Could not read TaskScheduler operational log: $($_.Exception.Message)"
}

Section "Try running node.cmd in foreground (will block if successful)"
Write-Host "If this exits immediately, copy/paste the error output back into chat." -ForegroundColor Yellow
Write-Host "Path: $env:USERPROFILE\.openclaw\node.cmd" -ForegroundColor Gray

if (Test-Path "$env:USERPROFILE\.openclaw\node.cmd") {
  & "$env:USERPROFILE\.openclaw\node.cmd"
} else {
  Write-Warning "node.cmd not found in current USERPROFILE."
}
