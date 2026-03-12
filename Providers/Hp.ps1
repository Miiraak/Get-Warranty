# ── Module-scoped token cache (reused across calls within the same session) ──
$script:HpCaptchaToken     = $null
$script:HpCaptchaTokenTime = [datetime]::MinValue

function Get-HpReCaptchaToken {
  <#
    .SYNOPSIS
      Obtains a Google reCAPTCHA v3 token for support.hp.com using a headless
      Chromium-based browser (Microsoft Edge or Google Chrome).

    .DESCRIPTION
      Launches Edge/Chrome in headless mode with --dump-dom to load the HP
      warranty page, then extracts the token that Google reCAPTCHA v3 writes
      into the hidden textarea "g-recaptcha-response".

      The token is cached at module scope for ~90 seconds to avoid re-launching
      the browser on every call (reCAPTCHA v3 tokens are valid for ~120 s).
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param()

  # Return cached token if still valid
  if ($script:HpCaptchaToken -and
      ((Get-Date) - $script:HpCaptchaTokenTime).TotalSeconds -lt 90) {
    Write-Verbose "Reusing cached HP reCAPTCHA token."
    return $script:HpCaptchaToken
  }

  $browser = Get-ChromiumPath
  Write-Verbose "Launching headless browser to obtain reCAPTCHA token: $browser"

  # Regex pattern for the hidden reCAPTCHA v3 response textarea
  $tokenRegex = 'name="g-recaptcha-response"[^>]*>\s*([^<\s][^<]*?)\s*<'

  $browserOutput = & $browser --headless --disable-gpu --dump-dom `
    "https://support.hp.com/us-en/check-warranty" 2>&1
  $dom   = ($browserOutput | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
  $token = [regex]::Match($dom, $tokenRegex).Groups[1].Value

  if ([string]::IsNullOrWhiteSpace($token)) {
    # reCAPTCHA async call may not have completed; wait and retry once
    Write-Verbose "Token not found on first attempt; waiting 3 s and retrying..."
    Start-Sleep -Seconds 3
    $browserOutput = & $browser --headless --disable-gpu --dump-dom `
      "https://support.hp.com/us-en/check-warranty" 2>&1
    $dom   = ($browserOutput | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
    $token = [regex]::Match($dom, $tokenRegex).Groups[1].Value
  }

  if ([string]::IsNullOrWhiteSpace($token)) {
    throw "Failed to extract reCAPTCHA token from HP warranty page. " +
          "Ensure Microsoft Edge or Google Chrome is installed and can reach support.hp.com."
  }

  $script:HpCaptchaToken     = $token
  $script:HpCaptchaTokenTime = Get-Date
  Write-Verbose "reCAPTCHA token obtained and cached (~90 s TTL)."
  return $token
}

function Get-HPProductInfo {
  <#
    .SYNOPSIS
      Queries the HP device search API to retrieve product details for a serial number.
  #>
  [CmdletBinding()]
  [OutputType([object])]
  param(
    [Parameter(Mandatory)]
    [string] $SerialNumber
  )

  $uri  = "https://support.hp.com/wcc-services/profile/devices/searchresult"
  $body = @{
    serialNumber = $SerialNumber
    countryCode  = "us"
    languageCode = "en"
  } | ConvertTo-Json

  $iwrParams = @{
    Uri         = $uri
    Method      = "POST"
    ContentType = "application/json"
    Body        = $body
    ErrorAction = "Stop"
  }
  if ($PSVersionTable.PSVersion.Major -lt 6) { $iwrParams.UseBasicParsing = $true }

  try {
    $result = Invoke-RestMethod @iwrParams
    if ($result.devices -and $result.devices.Count -gt 0) {
      return $result.devices[0]
    }
  } catch {
    Write-Verbose "HP product info lookup failed: $_"
  }

  return $null
}

function Get-HpWarranty {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Serial,

    # Kept for backward compatibility; not used in the headless flow
    [Parameter()]
    [int] $TimeoutSeconds = 60
  )

  Write-Verbose "Fetching HP product info for serial: $Serial"
  $device = Get-HPProductInfo -SerialNumber $Serial

  Write-Verbose "Obtaining reCAPTCHA token via headless browser..."
  $token = Get-HpReCaptchaToken

  $uri = "https://support.hp.com/wcc-services/profile/devices/warranty/specs" +
         "?authState=anonymous&template=WarrantyLanding"

  $deviceEntry = @{
    serialNumber         = $Serial
    countryOfPurchase    = if ($device -and $device.countryOfPurchase) { $device.countryOfPurchase } else { "us" }
    productNumber        = if ($device -and $device.productNumber)     { $device.productNumber }     else { "" }
    displayProductNumber = if ($device -and $device.displayProductNumber) { $device.displayProductNumber } else { "" }
  }

  # HP API expects the UTC offset as "PHHMM" (e.g. "P0100" = UTC+01:00)
  $tzOff    = [System.TimeZoneInfo]::Local.GetUtcOffset([datetime]::Now)
  $utcOffset = "P{0:D2}{1:D2}" -f [math]::Abs($tzOff.Hours), [math]::Abs($tzOff.Minutes)

  $body = @{
    cc           = "us"
    lc           = "en"
    utcOffset    = $utcOffset
    devices      = @($deviceEntry)
    captchaToken = $token
  } | ConvertTo-Json -Depth 5

  $iwrParams = @{
    Uri         = $uri
    Method      = "POST"
    ContentType = "application/json"
    Body        = $body
    ErrorAction = "Stop"
  }
  if ($PSVersionTable.PSVersion.Major -lt 6) { $iwrParams.UseBasicParsing = $true }

  Write-Verbose "Calling HP warranty API..."
  $result = Invoke-RestMethod @iwrParams

  # ── Normalise into the standard output object ──
  $deviceResult = if ($result.devices -and $result.devices.Count -gt 0) { $result.devices[0] } else { $null }

  $modelName = if ($deviceResult -and $deviceResult.productName)  { $deviceResult.productName }
               elseif ($device -and $device.productName)          { $device.productName }
               else                                               { $null }

  $productNum = if ($deviceResult -and $deviceResult.productNumber) { $deviceResult.productNumber }
                elseif ($device -and $device.productNumber)         { $device.productNumber }
                else                                                { $null }

  $warrantyList = @()
  if ($deviceResult -and $deviceResult.warranties) {
    foreach ($w in $deviceResult.warranties) {
      $start  = $w.startDate
      $end    = $w.endDate
      $status = "unknown"
      if ($end) {
        try {
          $parsed = [datetime]::Parse($end, [Globalization.CultureInfo]::InvariantCulture)
          $status = if ($parsed.Date -ge (Get-Date).Date) { "active" } else { "expired" }
        } catch { }
      }
      $warrantyList += [pscustomobject]@{
        name   = if ($w.type) { $w.type } else { "Standard" }
        start  = $start
        end    = $end
        status = $status
        notes  = ""
      }
    }
  }

  if ($warrantyList.Count -eq 0) {
    $warrantyList += [pscustomobject]@{
      name   = "Standard"
      start  = $null
      end    = $null
      status = "unknown"
      notes  = ""
    }
  }

  [pscustomobject]@{
    manufacturer = "HP"
    model        = $modelName
    serial       = $Serial
    product      = $productNum
    checked_at   = (Get-Date).ToUniversalTime().ToString("o")
    source       = "https://support.hp.com"
    warranties   = $warrantyList
    meta         = [pscustomobject]@{
      region  = "us-en"
      country = if ($deviceResult -and $deviceResult.countryOfPurchase) { $deviceResult.countryOfPurchase }
                elseif ($device -and $device.countryOfPurchase)         { $device.countryOfPurchase }
                else                                                     { "us" }
      url     = "https://support.hp.com/wcc-services/profile/devices/warranty/specs"
      method  = "ChromiumHeadless"
    }
  }
}