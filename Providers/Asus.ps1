function Get-AsusWarranty {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Serial,

    [Parameter()]
    [int] $MaximumRedirection = 5
  )

  $base = "https://eu-rma.asus.com"
  $formPath = "/uk/info/warranty"
  $postPath = "/uk/info/warrantyCheck"

  $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

  # PowerShell 5.1: avoid script execution prompt
  $iwrCommon = @{}
  if ($PSVersionTable.PSVersion.Major -lt 6) {
    $iwrCommon.UseBasicParsing = $true
  }

  # GET form page to retrieve CSRF token + establish session cookies
  $r1 = Invoke-WebRequest @iwrCommon -Uri ($base + $formPath) -WebSession $session -Method GET -ErrorAction Stop

  $tokenMatch = [regex]::Match($r1.Content, 'name="_token"\s+value="([^"]+)"')
  if (-not $tokenMatch.Success) {
    throw "ASUS EU RMA: could not find CSRF _token on $($base + $formPath)."
  }
  $token = $tokenMatch.Groups[1].Value

  # POST serial number (Laravel form)
  $body = @{
    _token    = $token
    serial_no = $Serial
  }

  $r2 = Invoke-WebRequest @iwrCommon -Uri ($base + $postPath) -WebSession $session -Method POST `
    -Body $body -ContentType "application/x-www-form-urlencoded" -MaximumRedirection $MaximumRedirection -ErrorAction Stop

  $html = $r2.Content

  # Parse results from <li>Label: value</li>
  function Get-LiValue([string]$label) {
    $m = [regex]::Match($html, "<li>\s*$([regex]::Escape($label))\s*:\s*([^<]+)\s*</li>", "IgnoreCase")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
  }

  $model   = Get-LiValue "Model"
  $country = Get-LiValue "Country"
  $start   = Get-LiValue "Warranty start date"
  $end     = Get-LiValue "Warranty end date"

  if (-not $model -and -not $start -and -not $end) {
    # Attempt to capture the visible error/explanation text if any
    $hint = ([regex]::Match($html, "<span[^>]*class=""font-weight-bold""[^>]*>([^<]+)</span>", "IgnoreCase")).Groups[1].Value
    if (-not $hint) { $hint = "No warranty details found in response HTML." }
    throw "ASUS EU RMA: lookup failed for serial '$Serial'. $hint"
  }

  # Determine status based on end date
  $status = "unknown"
  if ($end) {
    try {
      $endDate = [datetime]::ParseExact($end, "yyyy-MM-dd", $null)
      $status = if ($endDate.Date -ge (Get-Date).Date) { "active" } else { "expired" }
    } catch {
      $status = "unknown"
    }
  }

  [pscustomobject]@{
    manufacturer = "ASUS"
    model        = $model
    serial       = $Serial
    product      = $null
    checked_at   = (Get-Date).ToUniversalTime().ToString("o")
    source       = $base
    warranties   = @(
      [pscustomobject]@{
        name   = "Standard"
        start  = $start
        end    = $end
        status = $status
        notes  = if ($country) { "Country: $country" } else { "" }
      }
    )
    meta = [pscustomobject]@{
      region  = "uk"
      country = $country
      url     = ($base + $formPath)
    }
  }
}