function Get-AsusWarranty {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Serial,

    [Parameter()]
    [int] $MaximumRedirection = 5,

    [Parameter()]
    [int] $TimeoutSec = 30
  )

  $base     = "https://eu-rma.asus.com"
  $formPath = "/uk/info/warranty"
  $postPath = "/uk/info/warrantyCheck"

  $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

  # Common Invoke-WebRequest parameters (PS 5.1 compat)
  $iwrCommon = @{ TimeoutSec = $TimeoutSec }
  if ($PSVersionTable.PSVersion.Major -lt 6) {
    $iwrCommon.UseBasicParsing = $true
  }

  # ── 1. GET the form page – retrieve CSRF token + cookies ──
  Write-Verbose "GET $($base + $formPath)"
  $r1 = Invoke-WebRequest @iwrCommon `
    -Uri ($base + $formPath) `
    -WebSession $session `
    -Method GET `
    -ErrorAction Stop

  $tokenMatch = [regex]::Match($r1.Content, 'name="_token"\s+value="([^"]+)"')
  if (-not $tokenMatch.Success) {
    throw "ASUS EU RMA: could not extract CSRF _token from $($base + $formPath)."
  }
  $token = $tokenMatch.Groups[1].Value
  Write-Verbose "CSRF token obtained (length $($token.Length))."

  # ── 2. POST the serial number ──
  $body = @{
    _token    = $token
    serial_no = $Serial
  }

  Write-Verbose "POST $($base + $postPath) (serial: $Serial)"
  $r2 = Invoke-WebRequest @iwrCommon `
    -Uri ($base + $postPath) `
    -WebSession $session `
    -Method POST `
    -Body $body `
    -ContentType "application/x-www-form-urlencoded" `
    -MaximumRedirection $MaximumRedirection `
    -ErrorAction Stop

  $html = $r2.Content

  # ── 3. Parse <li> elements ──
  function Get-LiValue([string]$label) {
    $m = [regex]::Match(
      $html,
      "<li>\s*$([regex]::Escape($label))\s*:\s*([^<]+)\s*</li>",
      "IgnoreCase"
    )
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
  }

  $model   = Get-LiValue "Model"
  $country = Get-LiValue "Country"
  $start   = Get-LiValue "Warranty start date"
  $end     = Get-LiValue "Warranty end date"

  if (-not $model -and -not $start -and -not $end) {
    $hint = ([regex]::Match(
      $html,
      '<span[^>]*class="font-weight-bold"[^>]*>([^<]+)</span>',
      "IgnoreCase"
    )).Groups[1].Value
    if (-not $hint) { $hint = "No warranty details found in the response HTML." }
    throw "ASUS EU RMA: lookup failed for serial '$Serial'. $hint"
  }

  # ── 4. Determine warranty status ──
  $status = "unknown"
  if ($end) {
    try {
      $endDate = [datetime]::ParseExact($end, "yyyy-MM-dd", $null)
      $status  = if ($endDate.Date -ge (Get-Date).Date) { "active" } else { "expired" }
    } catch {
      Write-Verbose "Could not parse end date '$end' – status remains unknown."
    }
  }

  Write-Verbose "ASUS result: model=$model, start=$start, end=$end, status=$status"

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
      method  = "HTTP"
    }
  }
}