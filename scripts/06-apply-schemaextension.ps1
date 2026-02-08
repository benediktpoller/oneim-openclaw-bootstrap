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

function Get-TableExists([string]$connStr, [string]$tableName) {
  $q = "select case when object_id(@t,'U') is null then 0 else 1 end;"
  $cn = New-Object System.Data.SqlClient.SqlConnection($connStr)
  try {
    $cn.Open()
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = $q
    $null = $cmd.Parameters.Add('@t',[System.Data.SqlDbType]::NVarChar,128)
    $cmd.Parameters['@t'].Value = $tableName
    return ([int]$cmd.ExecuteScalar() -eq 1)
  } finally {
    if ($cn.State -ne 'Closed') { $cn.Close() }
  }
}

function Load-ExtensionMeta([string]$path) {
  [xml]$x = Get-Content $path -Raw
  $ext = $x.Extensions.Extension
  if (-not $ext) { throw "No <Extension> found in $path" }
  return [pscustomobject]@{
    Xml = $x
    Ext = $ext
    Name = [string]$ext.Name
    Mode = [string]$ext.Mode
  }
}

if (-not (Test-Path $SchemaExtensionCmd)) { throw "SchemaExtensionCmd not found: $SchemaExtensionCmd" }
if (-not (Test-Path $Definition)) { throw "Definition not found: $Definition" }

$meta = Load-ExtensionMeta $Definition
$extName = $meta.Name
$mode = $meta.Mode

# Idempotency helpers
if ($mode -eq 'RemoveExtension') {
  $exists = Get-TableExists -connStr $Conn -tableName $extName
  if (-not $exists) {
    Write-Host "Skip: $extName already absent (RemoveExtension no-op)." -ForegroundColor Yellow
    exit 0
  }
}

$definitionToUse = $Definition
if ($mode -eq 'CreateTable') {
  $exists = Get-TableExists -connStr $Conn -tableName $extName
  if ($exists) {
    # Avoid failing on create table when re-applying.
    Write-Host "Info: $extName already exists. Applying without <CreateTable/> step." -ForegroundColor Yellow
    $tmp = Join-Path $env:TEMP ("SchemaExt_{0}_{1}.xml" -f $extName, [System.Guid]::NewGuid().ToString('N'))

    # Remove <CreateTable/> steps only (robustly; PowerShell XML can expose elements oddly).
    $nodes = $meta.Xml.SelectNodes("/Extensions/Extension[@Name='$extName']/Steps/CreateTable")
    if ($nodes) {
      foreach ($n in @($nodes)) {
        $null = $n.ParentNode.RemoveChild($n)
      }
    }

    # Also remove already-existing columns from the definition to avoid duplicate ALTER TABLE ... ADD.
    $existingCols = @{}
    $cn = New-Object System.Data.SqlClient.SqlConnection($Conn)
    try {
      $cn.Open()
      $cmd = $cn.CreateCommand()
      $cmd.CommandText = "select c.name from sys.columns c join sys.tables t on t.object_id=c.object_id where t.name=@tn"
      $null = $cmd.Parameters.Add('@tn',[System.Data.SqlDbType]::NVarChar,128)
      $cmd.Parameters['@tn'].Value = $extName
      $r = $cmd.ExecuteReader()
      while ($r.Read()) { $existingCols[$r.GetString(0)] = $true }
      $r.Close()
    } finally {
      if ($cn.State -ne 'Closed') { $cn.Close() }
    }

    $colNodes = $meta.Xml.SelectNodes("/Extensions/Extension[@Name='$extName']/Columns/*[@Name]")
    foreach ($c in @($colNodes)) {
      $n = $c.Attributes['Name'].Value
      if ($existingCols.ContainsKey($n)) {
        $null = $c.ParentNode.RemoveChild($c)
      }
    }

    $meta.Xml.Save($tmp)
    $definitionToUse = $tmp
  }
}

$argList = @(
  "/Conn=$Conn",
  "/Auth=$Auth",
  "/Definition=$definitionToUse",
  "/LogLevel=$LogLevel"
)
if ($VerboseMode) { $argList += '-v' }

Write-Host "Running SchemaExtensionCmd:" -ForegroundColor Cyan
Write-Host "  $SchemaExtensionCmd $($argList -join ' ')" -ForegroundColor Gray

& $SchemaExtensionCmd @argList
exit $LASTEXITCODE
