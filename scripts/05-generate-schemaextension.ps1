param(
  [Parameter(Mandatory=$true)]
  [string]$SpecPath,

  [Parameter(Mandatory=$true)]
  [string]$OutXml
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Die($m) { throw $m }

if (-not (Test-Path $SpecPath)) { Die "SpecPath not found: $SpecPath" }

$spec = Get-Content $SpecPath -Raw | ConvertFrom-Json

foreach ($k in @('name','customerPrefix','mode','display','description','steps','columns')) {
  if (-not $spec.PSObject.Properties[$k]) { Die "Missing required field in spec: $k" }
}

$extName = [string]$spec.name
$customerPrefix = [string]$spec.customerPrefix
$mode = [string]$spec.mode
$display = [string]$spec.display
$description = [string]$spec.description

$columns = @($spec.columns)
$steps = @($spec.steps)

# Build XML with deterministic formatting.
$settings = New-Object System.Xml.XmlWriterSettings
$settings.Indent = $true
$settings.IndentChars = '  '
$settings.NewLineChars = "`r`n"
$settings.OmitXmlDeclaration = $false
$settings.Encoding = [System.Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Force -Path (Split-Path $OutXml -Parent) | Out-Null

$writer = [System.Xml.XmlWriter]::Create($OutXml, $settings)
try {
  $writer.WriteStartDocument()
  $writer.WriteStartElement('Extensions')

  $writer.WriteStartElement('Extension')
  $writer.WriteAttributeString('Name', $extName)
  $writer.WriteAttributeString('Mode', $mode)
  $writer.WriteAttributeString('CustomerPrefix', $customerPrefix)

  if ($spec.PSObject.Properties['uid'] -and $spec.uid) {
    $writer.WriteAttributeString('UID', [string]$spec.uid)
  }

  $writer.WriteStartElement('Display')
  $writer.WriteString($display)
  $writer.WriteEndElement()

  $writer.WriteStartElement('Description')
  $writer.WriteString($description)
  $writer.WriteEndElement()

  if ($columns.Count -gt 0) {
    $writer.WriteStartElement('Columns')
    foreach ($c in $columns) {
      $kind = if ($c.PSObject.Properties['kind']) { [string]$c.kind } else { 'Column' }
      if ($kind -eq 'FkColumn') {
        $writer.WriteStartElement('FkColumn')
        foreach ($attr in @('Name','Length','Type','IsUid','SortOrder','SchemaDataLen','RestrictionChild','RestrictionParent')) {
          $key = $attr.Substring(0,1).ToLower() + $attr.Substring(1)
          if ($c.PSObject.Properties[$key] -and $null -ne $c.$key) {
            $writer.WriteAttributeString($attr, [string]$c.$key)
          }
        }

        if (-not $c.otherPk -or -not $c.otherPk.table -or -not $c.otherPk.column) {
          Die "FkColumn requires otherPk.table and otherPk.column (column: $($c.name))"
        }
        $writer.WriteStartElement('OtherPK')
        $writer.WriteAttributeString('Table', [string]$c.otherPk.table)
        $writer.WriteAttributeString('Column', [string]$c.otherPk.column)
        $writer.WriteEndElement() # OtherPK

        $writer.WriteEndElement() # FkColumn
      } else {
        $writer.WriteStartElement('Column')
        foreach ($attr in @('Name','Length','Type','SortOrder','SchemaDataLen')) {
          $key = $attr.Substring(0,1).ToLower() + $attr.Substring(1)
          if ($c.PSObject.Properties[$key] -and $null -ne $c.$key) {
            $writer.WriteAttributeString($attr, [string]$c.$key)
          }
        }
        $writer.WriteEndElement() # Column
      }
    }
    $writer.WriteEndElement() # Columns
  }

  $writer.WriteStartElement('Steps')
  foreach ($s in $steps) {
    $stepName = [string]$s
    if ($stepName -eq 'SetRights') {
      $writer.WriteStartElement('SetRights')
      $readUids = @($spec.rights.readGroupUids)
      $writeUids = @($spec.rights.writeGroupUids)
      if ($readUids.Count -gt 0) {
        $writer.WriteStartElement('ReadGroupUids')
        foreach ($u in $readUids) { $writer.WriteElementString('Uid', [string]$u) }
        $writer.WriteEndElement()
      }
      if ($writeUids.Count -gt 0) {
        $writer.WriteStartElement('WriteGroupUids')
        foreach ($u in $writeUids) { $writer.WriteElementString('Uid', [string]$u) }
        $writer.WriteEndElement()
      }
      $writer.WriteEndElement() # SetRights
      continue
    }

    if ($stepName -like 'DialogTag:*') {
      $modeVal = $stepName.Split(':',2)[1]
      $writer.WriteStartElement('DialogTag')
      $writer.WriteAttributeString('TagMode', $modeVal)
      $writer.WriteEndElement()
      continue
    }

    # Simple empty steps (e.g. CreateTable, CreateColumns, RemoveExtension)
    $writer.WriteStartElement($stepName)
    $writer.WriteEndElement()
  }
  $writer.WriteEndElement() # Steps

  $writer.WriteEndElement() # Extension
  $writer.WriteEndElement() # Extensions
  $writer.WriteEndDocument()
} finally {
  $writer.Flush()
  $writer.Close()
}

Write-Host "Wrote schema extension XML: $OutXml" -ForegroundColor Green
