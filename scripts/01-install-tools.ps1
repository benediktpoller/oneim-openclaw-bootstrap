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

function Install-Chocolatey {
  if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Host "Chocolatey already installed." -ForegroundColor Green
    return
  }

  Write-Host "\n--- Installing Chocolatey (fallback package manager) ---" -ForegroundColor Cyan
  Set-ExecutionPolicy Bypass -Scope Process -Force
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
  Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

  if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    throw "Chocolatey install failed (choco not found after install)."
  }
}

function Require-Winget {
  if (Get-Command winget -ErrorAction SilentlyContinue) { return }

  Write-Warning "winget not found. We'll try a bootstrap install of winget (App Installer) via Add-AppxPackage."

  # Some Windows Server images (and Server Core) do not support AppX at all.
  $appxSupported = $true
  try {
    Import-Module Appx -ErrorAction Stop
  } catch {
    $appxSupported = $false
  }

  if (-not $appxSupported) {
    Write-Warning "AppX not supported on this platform. Falling back to Chocolatey-based installs."
    Install-Chocolatey
    return
  }

  $tmp = Join-Path $env:TEMP ("winget-bootstrap-" + [guid]::NewGuid().ToString('n'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null

  $pkgs = @(
    @{ name = 'VCLibs'; url = 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx' },
    @{ name = 'UIXaml'; url = 'https://aka.ms/Microsoft.UI.Xaml.2.8.x64.appx' },
    @{ name = 'DesktopAppInstaller'; url = 'https://aka.ms/getwinget' }
  )

  foreach ($p in $pkgs) {
    $out = Join-Path $tmp ($p.name + '-' + (Split-Path $p.url -Leaf))
    Write-Host ("Downloading {0} -> {1}" -f $p.name, $out) -ForegroundColor Cyan
    Invoke-WebRequest -UseBasicParsing -Uri $p.url -OutFile $out
    Write-Host ("Installing {0}" -f $p.name) -ForegroundColor Cyan
    try {
      Add-AppxPackage -Path $out
    } catch {
      Write-Warning "Add-AppxPackage failed ($($p.name)): $($_.Exception.Message)"
      Write-Warning "Falling back to Chocolatey-based installs."
      Install-Chocolatey
      return
    }
  }

  Start-Sleep -Seconds 2

  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warning "winget still not found after AppX bootstrap. Falling back to Chocolatey-based installs."
    Install-Chocolatey
    return
  }

  Write-Host "winget is now available." -ForegroundColor Green
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

$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
$hasChoco  = [bool](Get-Command choco -ErrorAction SilentlyContinue)

if (-not $hasWinget -and -not $hasChoco) {
  throw "Neither winget nor chocolatey is available. Cannot continue."
}

function Install-Tool {
  param(
    [Parameter(Mandatory=$true)][string]$Tool,
    [string]$WingetId = '',
    [string]$ChocoId = ''
  )

  if (Get-Command $Tool -ErrorAction SilentlyContinue) {
    Write-Host "$Tool already installed." -ForegroundColor Green
    return
  }

  if ($hasWinget -and $WingetId) {
    Install-WingetPackage -Id $WingetId -Name $Tool
    return
  }

  if ($hasChoco -and $ChocoId) {
    Write-Host "\n--- Installing: $Tool (choco: $ChocoId) ---" -ForegroundColor Cyan
    choco install $ChocoId -y --no-progress
    return
  }

  throw "No installer mapping provided for $Tool (wingetId='$WingetId', chocoId='$ChocoId')."
}

# Git
Install-Tool -Tool 'git' -WingetId 'Git.Git' -ChocoId 'git'

# Node.js (LTS)
Install-Tool -Tool 'node' -WingetId 'OpenJS.NodeJS.LTS' -ChocoId 'nodejs-lts'

# Ensure we are on Node LTS (OpenClaw is tested primarily on LTS)
try {
  $nodeV = (& node -v).Trim()
  Write-Host "Node version: $nodeV" -ForegroundColor Gray
  if ($nodeV -match '^v(\d+)\.' ) {
    $major = [int]$Matches[1]
    if ($major -ge 24) {
      Write-Warning "Node $nodeV detected (non-LTS/current). Attempting to switch to Node 22 LTS."

      if (Get-Command choco -ErrorAction SilentlyContinue) {
        # Some environments have nodejs-lts mapped to v24+. If so, use nvm-windows to pin v22.
        Write-Host "Installing/using nvm-windows to pin Node 22 LTS..." -ForegroundColor Cyan
        choco install nvm -y --no-progress | Out-Host

        $target = '22.13.1'
        try {
          nvm install $target | Out-Host
        } catch {
          Write-Warning "nvm install $target failed: $($_.Exception.Message)"
          throw
        }
        nvm use $target | Out-Host

        Write-Warning "Open a NEW PowerShell so PATH updates apply (nvm shim). Then re-run this script."
        return
      }
    }
  }
} catch {
  Write-Warning "Could not read node version: $($_.Exception.Message)"
}

# PowerShell 7 (optional)
if (-not $SkipPowerShell7) {
  Install-Tool -Tool 'pwsh' -WingetId 'Microsoft.PowerShell' -ChocoId 'powershell-core'
}

# sqlcmd (optional)
if (-not $SkipSqlCmd) {
  if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    if ($hasWinget) {
      try {
        Install-WingetPackage -Id 'Microsoft.SQLCMD' -Name 'SQLCMD'
      } catch {
        Write-Warning "winget id 'Microsoft.SQLCMD' failed. We'll try Chocolatey 'sqlcmd'."
      }
    }
    if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue) -and $hasChoco) {
      Write-Host "\n--- Installing: sqlcmd (choco: sqlcmd) ---" -ForegroundColor Cyan
      # Package availability varies; if it fails, install SQL cmdline utilities manually.
      choco install sqlcmd -y --no-progress
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
  $needsInstall = $false

  if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) {
    $needsInstall = $true
  } else {
    # Don't trust PATH-only checks; verify the CLI actually runs.
    try {
      $null = (& openclaw --version)
    } catch {
      Write-Warning "openclaw command exists but is broken. Will reinstall. Error: $($_.Exception.Message)"
      $needsInstall = $true
    }
  }

  if ($needsInstall) {
    Write-Host "\n--- Installing OpenClaw CLI (npm -g openclaw --omit=optional) ---" -ForegroundColor Cyan
    npm i -g openclaw --omit=optional
  } else {
    Write-Host "openclaw already installed (and runnable)." -ForegroundColor Green
  }
}

Write-Host "\nDone." -ForegroundColor Green
