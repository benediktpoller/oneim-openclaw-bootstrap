param(
  [switch]$SkipPowerShell7,
  [switch]$SkipSqlCmd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Not running as Administrator. winget installs may fail."
  }
}

function Require-Winget {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget not found. Install 'App Installer' from Microsoft Store or enable winget."
  }
}

function Install-WingetPackage {
  param(
    [Parameter(Mandatory=$true)][string]$Id,
    [string]$Name = $Id
  )

  Write-Host "\n--- Installing: $Name ($Id) ---" -ForegroundColor Cyan
  # Use silent/accept agreements. Some packages may still prompt.
  winget install --id $Id --silent --accept-package-agreements --accept-source-agreements
}

Require-Admin
Require-Winget

# Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Install-WingetPackage -Id 'Git.Git' -Name 'Git'
} else {
  Write-Host "Git already installed." -ForegroundColor Green
}

# Node.js (LTS)
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Install-WingetPackage -Id 'OpenJS.NodeJS.LTS' -Name 'Node.js LTS'
} else {
  Write-Host "Node already installed." -ForegroundColor Green
}

# PowerShell 7 (optional)
if (-not $SkipPowerShell7) {
  if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Install-WingetPackage -Id 'Microsoft.PowerShell' -Name 'PowerShell 7'
  } else {
    Write-Host "pwsh already installed." -ForegroundColor Green
  }
}

# sqlcmd (optional)
if (-not $SkipSqlCmd) {
  if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    # New sqlcmd (mssql-tools18) is usually available via winget.
    # If this id fails in your environment, install SQL Server Command Line Utilities manually.
    try {
      Install-WingetPackage -Id 'Microsoft.SQLCMD' -Name 'SQLCMD'
    } catch {
      Write-Warning "winget id 'Microsoft.SQLCMD' failed. You may need to install SQL Server Command Line Utilities / mssql-tools manually. Error: $($_.Exception.Message)"
    }
  } else {
    Write-Host "sqlcmd already installed." -ForegroundColor Green
  }
}

# OpenClaw CLI via npm
# Ensure npm is on PATH. In the same shell, you might need to restart after Node install.
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  Write-Warning "npm not found yet. If you just installed Node, open a new PowerShell and re-run this script."
} else {
  if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) {
    Write-Host "\n--- Installing OpenClaw CLI (npm -g openclaw) ---" -ForegroundColor Cyan
    npm i -g openclaw
  } else {
    Write-Host "openclaw already installed." -ForegroundColor Green
  }
}

Write-Host "\nDone." -ForegroundColor Green
