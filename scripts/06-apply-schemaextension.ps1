param(
  [Parameter(Mandatory=$true)][string]$Conn,
  [Parameter(Mandatory=$true)][string]$Auth,
  [Parameter(Mandatory=$true)][string]$Definition,
  [string]$SchemaExtensionCmd = 'C:\OneIM\Tools\One Identity Manager\SchemaExtensionCmd.exe',
  [ValidateSet('Off','Fatal','Error','Info','Warn','Debug','Trace')]
  [string]$LogLevel = 'Info',
  [switch]$VerboseMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SchemaExtensionCmd)) { throw "SchemaExtensionCmd not found: $SchemaExtensionCmd" }
if (-not (Test-Path $Definition)) { throw "Definition not found: $Definition" }

$argList = @(
  "/Conn=$Conn",
  "/Auth=$Auth",
  "/Definition=$Definition",
  "/LogLevel=$LogLevel"
)
if ($VerboseMode) { $argList += '-v' }

Write-Host "Running SchemaExtensionCmd:" -ForegroundColor Cyan
Write-Host "  $SchemaExtensionCmd $($argList -join ' ')" -ForegroundColor Gray

& $SchemaExtensionCmd @argList
exit $LASTEXITCODE
