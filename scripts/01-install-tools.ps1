param(
  [switch]$SkipPowerShell7,
  [switch]$SkipSqlCmd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Section($t) {
  Write-Host "`n=== $t ===" -ForegroundColor Cyan
}

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

  Write-Host "`n--- Installing Chocolatey (fallback package manager) ---" -ForegroundColor Cyan
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

  Write-Host "`n--- Installing: $Name ($Id) ---" -ForegroundColor Cyan
  # Use silent/accept agreements. Some packages may still prompt.
  winget install --id $Id --silent --accept-package-agreements --accept-source-agreements
}

Section "Bootstrap / Package manager"
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
    Write-Host "`n--- Installing: $Tool (choco: $ChocoId) ---" -ForegroundColor Cyan
    choco install $ChocoId -y --no-progress
    return
  }

  throw "No installer mapping provided for $Tool (wingetId='$WingetId', chocoId='$ChocoId')."
}

Section "Core tools"

# Git
Install-Tool -Tool 'git' -WingetId 'Git.Git' -ChocoId 'git'

# Node.js (LTS)
Install-Tool -Tool 'node' -WingetId 'OpenJS.NodeJS.LTS' -ChocoId 'nodejs-lts'

# Ensure we are on Node LTS (OpenClaw is tested primarily on LTS)
try {
  $nodeV = (& node -v).Trim()
  Write-Host ("Node: {0}" -f $nodeV) -ForegroundColor Gray
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
# NOTE: IdentityManager.PoSh for One Identity Manager 10.0x requires PowerShell 7.6+.
# Stable PowerShell may lag behind; PowerShell Preview is often required.
if (-not $SkipPowerShell7) {
  Install-Tool -Tool 'pwsh' -WingetId 'Microsoft.PowerShell' -ChocoId 'powershell-core'

  # Try to install PowerShell Preview as well (best-effort).
  # winget id: Microsoft.PowerShell.Preview
  # choco id: powershell-preview
  try {
    Install-Tool -Tool 'pwsh-preview' -WingetId 'Microsoft.PowerShell.Preview' -ChocoId 'powershell-preview'
  } catch {
    Write-Warning "Could not install PowerShell Preview (optional): $($_.Exception.Message)"
  }
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
      Write-Host "`n--- Installing: sqlcmd (choco: sqlcmd) ---" -ForegroundColor Cyan
      # Package availability varies; if it fails, install SQL cmdline utilities manually.
      choco install sqlcmd -y --no-progress
    }
  } else {
    Write-Host "sqlcmd already installed." -ForegroundColor Green
  }
}

Section "OpenClaw CLI"

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
    # External command failures often do NOT throw; check $LASTEXITCODE.
    $prev = $env:NODE_NO_WARNINGS
    $env:NODE_NO_WARNINGS = '1'
    $null = (& openclaw --version)
    $env:NODE_NO_WARNINGS = $prev

    if ($LASTEXITCODE -ne 0) {
      Write-Warning "openclaw command exists but is broken (exit=$LASTEXITCODE). Will reinstall."
      $needsInstall = $true
    }
  }

  if ($needsInstall) {
    Write-Host "(Re)installing OpenClaw via npm" -ForegroundColor Cyan
    npm rm -g openclaw 2>$null | Out-Null
    try { Remove-Item -Recurse -Force "$env:APPDATA\npm\node_modules\openclaw" -ErrorAction SilentlyContinue } catch {}
    $installed = $false

    Write-Host "- Try 1: npm i -g openclaw --omit=optional" -ForegroundColor Gray
    npm i -g openclaw --omit=optional
    if ($LASTEXITCODE -eq 0) { $installed = $true }

    if (-not $installed) {
      Write-Warning "Install failed (exit=$LASTEXITCODE). Retrying with --ignore-scripts (skips postinstall)."
      Write-Host "- Try 2: npm i -g openclaw --ignore-scripts" -ForegroundColor Gray
      npm i -g openclaw --ignore-scripts
      if ($LASTEXITCODE -eq 0) { $installed = $true }
    }

    if (-not $installed) {
      throw "openclaw npm install failed (exit=$LASTEXITCODE)."
    }

    # verify
    $prev = $env:NODE_NO_WARNINGS
    $env:NODE_NO_WARNINGS = '1'
    $null = (& openclaw --version)
    $env:NODE_NO_WARNINGS = $prev

    if ($LASTEXITCODE -ne 0) {
      Write-Warning "openclaw still not runnable. Diagnostics:"
      try { where.exe openclaw | Out-Host } catch {}
      try { npm prefix -g | Out-Host } catch {}
      try { npm root -g | Out-Host } catch {}
      throw "openclaw install completed but CLI is still not runnable (exit=$LASTEXITCODE)."
    }

    Write-Host "openclaw OK" -ForegroundColor Green
  } else {
    Write-Host "openclaw OK" -ForegroundColor Green
  }
}

Section "Summary"

$summary = @(
  [pscustomobject]@{ Name = 'git';     Version = ((git --version 2>$null) -join ' ');  Ok = [bool](Get-Command git -ErrorAction SilentlyContinue) },
  [pscustomobject]@{ Name = 'node';    Version = ((node -v 2>$null) -join ' ');        Ok = [bool](Get-Command node -ErrorAction SilentlyContinue) },
  [pscustomobject]@{ Name = 'npm';     Version = ((npm -v 2>$null) -join ' ');         Ok = [bool](Get-Command npm -ErrorAction SilentlyContinue) },
  [pscustomobject]@{ Name = 'pwsh';          Version = ((pwsh -v 2>$null) -join ' ');        Ok = [bool](Get-Command pwsh -ErrorAction SilentlyContinue) },
  [pscustomobject]@{ Name = 'pwsh-preview';  Version = ((& 'C:\Program Files\PowerShell\7-preview\pwsh.exe' -v 2>$null) -join ' '); Ok = Test-Path 'C:\Program Files\PowerShell\7-preview\pwsh.exe' },
  [pscustomobject]@{ Name = 'sqlcmd';  Version = ((sqlcmd -? 2>$null | Select-Object -First 1) -join ''); Ok = [bool](Get-Command sqlcmd -ErrorAction SilentlyContinue) },
  [pscustomobject]@{ Name = 'openclaw';Version = ((openclaw --version 2>$null) -join ' '); Ok = [bool](Get-Command openclaw -ErrorAction SilentlyContinue) }
)

$summary | Format-Table -AutoSize | Out-Host

Write-Host "Done." -ForegroundColor Green
