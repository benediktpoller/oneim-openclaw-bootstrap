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
    Write-Warning "winget not found. We'll try a bootstrap install of winget (App Installer), then re-check."

    # Best-effort winget bootstrap for Windows Server / minimal images.
    # Strategy:
    # - Install Microsoft.VCLibs.140.00.UWPDesktop
    # - Install Microsoft.UI.Xaml
    # - Install Microsoft.DesktopAppInstaller (winget)
    # Uses aka.ms links that redirect to the latest msixbundle/appx.

    $tmp = Join-Path $env:TEMP ("winget-bootstrap-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    $pkgs = @(
      @{ name = 'VCLibs'; url = 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx' },
      @{ name = 'UIXaml'; url = 'https://aka.ms/Microsoft.UI.Xaml.2.8.x64.appx' },
      @{ name = 'DesktopAppInstaller'; url = 'https://aka.ms/getwinget' }
    )

    foreach ($p in $pkgs) {
      $out = Join-Path $tmp ($p.name + (Split-Path $p.url -Leaf))
      Write-Host ("Downloading {0} -> {1}" -f $p.name, $out) -ForegroundColor Cyan
      Invoke-WebRequest -UseBasicParsing -Uri $p.url -OutFile $out
      Write-Host ("Installing {0}" -f $p.name) -ForegroundColor Cyan
      Add-AppxPackage -Path $out
    }

    Start-Sleep -Seconds 2

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
      throw "winget still not found after bootstrap. On Windows Server, ensure Microsoft Store/App Installer is available, or install prerequisites manually."
    }

    Write-Host "winget is now available." -ForegroundColor Green
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
