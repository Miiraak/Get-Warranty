<#
 .SYNOPSIS
  Retrieves warranty information for the local machine or a specified serial number.

 .DESCRIPTION
  Get-Warranty is a PowerShell function that retrieves warranty information for
  the local machine or a specified serial number.  It supports multiple
  manufacturers (ASUS, HP, Dell, Lenovo, Acer) and can emit results as
  structured JSON or a formatted ASCII table.

  Providers use pure HTTP when the manufacturer's site allows it (e.g. ASUS EU
  RMA).  When the site requires reCAPTCHA or heavy JavaScript, the provider
  opens a WebView2 browser window so the user can solve the captcha while the
  module handles form-filling and data extraction automatically.

 .PARAMETER Serial
  The serial number of the device to check.  If omitted the local machine's
  serial number is detected via WMI.

 .PARAMETER Manufacturer
  The manufacturer of the device.  If omitted the local machine's manufacturer
  is detected via WMI.  Accepted values: asus, hp, dell, lenovo, acer.

 .PARAMETER Json
  Emit structured JSON instead of the default ASCII table.

 .EXAMPLE
  # Detect the local machine and display a table
  Get-Warranty

 .EXAMPLE
  # Check a specific ASUS serial, output as JSON
  Get-Warranty -Manufacturer asus -Serial "ABCDEFGH1234567" -Json

 .EXAMPLE
  # Check an HP serial (uses HTTP API if credentials are set, otherwise WebView2)
  Get-Warranty -Manufacturer hp -Serial "CND1234567"
#>
Set-StrictMode -Version Latest

$script:ModuleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load helpers + providers
Get-ChildItem -Path (Join-Path $script:ModuleRoot "Private")   -Filter *.ps1 -File -ErrorAction SilentlyContinue |
  ForEach-Object { . $_.FullName }

Get-ChildItem -Path (Join-Path $script:ModuleRoot "Providers") -Filter *.ps1 -File -ErrorAction SilentlyContinue |
  ForEach-Object { . $_.FullName }

function Get-LocalDeviceIdentity {
  [CmdletBinding()]
  param()

  $cs  = Get-CimInstance -ClassName Win32_ComputerSystem
  $bio = Get-CimInstance -ClassName Win32_BIOS

  $manufacturer = ($cs.Manufacturer  | ForEach-Object { $_.Trim() })
  $model        = ($cs.Model         | ForEach-Object { $_.Trim() })
  $serial       = ($bio.SerialNumber | ForEach-Object { $_.Trim() })

  $m = $manufacturer.ToLowerInvariant()
  $normalized =
    if     ($m -match "asus")        { "asus" }
    elseif ($m -match "hp|hewlett")  { "hp" }
    elseif ($m -match "dell")        { "dell" }
    elseif ($m -match "lenovo")      { "lenovo" }
    elseif ($m -match "acer")        { "acer" }
    else   { $manufacturer }

  Write-Verbose "Local device: manufacturer=$manufacturer ($normalized), model=$model, serial=$serial"

  [pscustomobject]@{
    Manufacturer           = $manufacturer
    Model                  = $model
    Serial                 = $serial
    ManufacturerNormalized = $normalized
  }
}

function Get-Warranty {
  [CmdletBinding()]
  param(
    [Parameter()]
    [string] $Serial,

    [Parameter()]
    [ValidateSet("asus","hp","dell","lenovo","acer")]
    [string] $Manufacturer,

    [Parameter()]
    [switch] $Json
  )

  # Auto-detect when parameters are missing
  if (-not $Serial -or -not $Manufacturer) {
    $id = Get-LocalDeviceIdentity
    if (-not $Serial)        { $Serial       = $id.Serial }
    if (-not $Manufacturer)  { $Manufacturer = $id.ManufacturerNormalized }
  }

  Write-Verbose "Querying warranty for manufacturer=$Manufacturer, serial=$Serial"

  $result =
    switch ($Manufacturer.ToLowerInvariant()) {
      "asus"   { Get-AsusWarranty   -Serial $Serial }
      "hp"     { Get-HpWarranty     -Serial $Serial }
      "dell"   { Get-DellWarranty   -Serial $Serial }
      "lenovo" { Get-LenovoWarranty -Serial $Serial }
      "acer"   { Get-AcerWarranty   -Serial $Serial }
      default  { throw "Unsupported manufacturer: $Manufacturer" }
    }

  if ($Json) {
    $result | ConvertTo-Json -Depth 8
  } else {
    Format-WarrantyTable -WarrantyObject $result
  }
}

Export-ModuleMember -Function Get-Warranty