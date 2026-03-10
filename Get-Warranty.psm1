<#
 .SYNOPSIS
  Retrieves warranty information for the local machine or a specified serial number.
  This function supports multiple manufacturers and can emit results as structured JSON
  or a formatted ASCII table.

 .DESCRIPTION
  Get-Warranty is a PowerShell function that retrieves warranty information for the local machine
  or a specified serial number. It supports multiple manufacturers including ASUS, HP, Dell, Lenovo,
  and Acer. The function can emit results as structured JSON or a formatted ASCII table.

 .PARAMETER Serial
  The serial number of the device to check. If not specified, the local machine's
  serial number will be used.

 .PARAMETER Manufacturer
  The manufacturer of the device. If not specified, the local machine's manufacturer
  will be used. Supported values are "asus", "hp", "dell", "lenovo", and "acer".

  .PARAMETER Json
  If specified, the output will be emitted as structured JSON instead of a formatted ASCII table.

  .PARAMETER Region
  The region to use for ASUS warranty checks. Defaults to "uk" which works well for EU RMA.

 .EXAMPLE
    # Get warranty info for the local machine and display as a table.
    Get-Warranty

 .EXAMPLE
   # Get warranty info for a specific serial number and display as JSON.
   Get-Warranty -Serial "ABCDEFGH1234567" -Json

 .EXAMPLE
    # Get warranty info for a specific serial number and manufacturer, and display as a table.
    Get-Warranty -Serial "ABCDEFGH1234567" -Manufacturer "hp"
#>
Set-StrictMode -Version Latest

$script:ModuleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load helpers + providers
Get-ChildItem -Path (Join-Path $script:ModuleRoot "Private") -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object { . $_.FullName }

Get-ChildItem -Path (Join-Path $script:ModuleRoot "Providers") -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object { . $_.FullName }

function Get-LocalDeviceIdentity {
  [CmdletBinding()]
  param()

  $cs  = Get-CimInstance -ClassName Win32_ComputerSystem
  $bio = Get-CimInstance -ClassName Win32_BIOS

  $manufacturer = ($cs.Manufacturer | ForEach-Object { $_.Trim() })
  $model        = ($cs.Model | ForEach-Object { $_.Trim() })
  $serial       = ($bio.SerialNumber | ForEach-Object { $_.Trim() })

  $m = $manufacturer.ToLowerInvariant()
  $normalized =
    if ($m -match "asus") { "asus" }
    elseif ($m -match "hp|hewlett") { "hp" }
    elseif ($m -match "dell") { "dell" }
    elseif ($m -match "lenovo") { "lenovo" }
    elseif ($m -match "acer") { "acer" }
    else { $manufacturer } # fallback raw

  [pscustomobject]@{
    Manufacturer = $manufacturer
    Model = $model
    Serial = $serial
    ManufacturerNormalized = $normalized
  }
}

function Get-Warranty {
  [CmdletBinding()]
  param(
    # Overrides local machine serial if specified
    [Parameter()]
    [string] $Serial,

    # Overrides manufacturer detection if specified
    [Parameter()]
    [ValidateSet("asus","hp","dell","lenovo","acer")]
    [string] $Manufacturer,

    # Emit structured JSON instead of the ASCII table
    [Parameter()]
    [switch] $Json
  )

  if (-not $Serial -or -not $Manufacturer) {
    $id = Get-LocalDeviceIdentity
    if (-not $Serial) { $Serial = $id.Serial }
    if (-not $Manufacturer) { $Manufacturer = $id.ManufacturerNormalized }
  }

  $result =
    switch ($Manufacturer.ToLowerInvariant()) {
      "asus" { Get-AsusWarranty -Serial $Serial }
      "hp"   { Get-HpWarranty -Serial $Serial }
      "dell" { Get-DellWarranty -Serial $Serial }
      "lenovo" { Get-LenovoWarranty -Serial $Serial }
      "acer" { Get-AcerWarranty -Serial $Serial }
      default { throw "Unsupported manufacturer: $Manufacturer" }
    }

  if ($Json) {
    $result | ConvertTo-Json -Depth 8
  } else {
    Format-WarrantyTable -WarrantyObject $result
  }
}

Export-ModuleMember -Function Get-Warranty