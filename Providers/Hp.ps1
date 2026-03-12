function Get-HpWarranty {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Serial,

    [Parameter()]
    [int] $TimeoutSeconds = 180
  )

  # ── Try HP official API first (fast, no GUI) ──
  $apiKey    = $env:GETWARRANTY_HP_APIKEY
  $apiSecret = $env:GETWARRANTY_HP_APISECRET

  if ($apiKey -and $apiSecret) {
    Write-Verbose "HP API credentials found – using HTTP (no GUI)."
    return Invoke-HpWarrantyApi -Serial $Serial -ApiKey $apiKey -ApiSecret $apiSecret
  }

  # ── Fallback: WebView2 (requires reCAPTCHA) ──
  Write-Verbose ("No HP API credentials configured. " +
    "Set `$env:GETWARRANTY_HP_APIKEY and `$env:GETWARRANTY_HP_APISECRET to avoid WebView2.")
  return Invoke-HpWarrantyWebView2 -Serial $Serial -TimeoutSeconds $TimeoutSeconds
}

# ──────────────────────────────────────────────
#  HTTP path – HP CSS Warranty API (no GUI)
# ──────────────────────────────────────────────
function Invoke-HpWarrantyApi {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $Serial,
    [Parameter(Mandatory)] [string] $ApiKey,
    [Parameter(Mandatory)] [string] $ApiSecret
  )

  $iwrCommon = @{ ErrorAction = "Stop" }
  if ($PSVersionTable.PSVersion.Major -lt 6) { $iwrCommon.UseBasicParsing = $true }

  # 1 – Obtain an OAuth token
  Write-Verbose "Requesting OAuth token from HP CSS API..."
  $tokenUrl  = "https://css.api.hp.com/oauth/v1/token"
  $tokenBody = "apiKey=$ApiKey&apiSecret=$ApiSecret&grantType=client_credentials&scope=warranty"

  try {
    $tokenResp = Invoke-RestMethod @iwrCommon `
      -Method Post -Uri $tokenUrl `
      -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
  } catch {
    throw "HP API: failed to obtain OAuth token – check GETWARRANTY_HP_APIKEY / GETWARRANTY_HP_APISECRET. $_"
  }

  $accessToken = $tokenResp.access_token
  if (-not $accessToken) {
    throw "HP API: OAuth response did not contain an access_token."
  }
  Write-Verbose "OAuth token obtained."

  # 2 – Query warranty
  Write-Verbose "Querying HP warranty for serial $Serial..."
  $queryUrl = "https://css.api.hp.com/productWarranty/v1/queries"
  $headers  = @{
    "Authorization" = "Bearer $accessToken"
    "Accept"        = "application/json"
    "Content-Type"  = "application/json"
  }
  $body = ConvertTo-Json @( @{ sn = $Serial; pn = "" } )

  try {
    $resp = Invoke-RestMethod @iwrCommon `
      -Method Post -Uri $queryUrl -Headers $headers -Body $body
  } catch {
    throw "HP API: warranty query failed for serial '$Serial'. $_"
  }

  # 3 – Parse the response into the standard schema
  $product = $null
  $warranties = @()

  # The API may return a single object or a list
  $items = if ($resp -is [array]) { $resp } else { @($resp) }
  foreach ($item in $items) {
    if (-not $product -and $item.productDescription) { $product = $item.productDescription }

    $entitlements = @()
    if     ($item.warrantyList)  { $entitlements = $item.warrantyList }
    elseif ($item.entitlements)  { $entitlements = $item.entitlements }

    foreach ($w in $entitlements) {
      $startDate = if ($w.startDate) { $w.startDate } else { $null }
      $endDate   = if ($w.endDate)   { $w.endDate }   else { $null }
      $wType     = if ($w.serviceType)   { $w.serviceType }
                   elseif ($w.warrantyType) { $w.warrantyType }
                   else { "Standard" }
      $wStatus   = "unknown"
      $rawStatus = @($w.serviceStatus, $w.status) | Where-Object { $_ } | Select-Object -First 1
      if ($rawStatus) {
        $s = $rawStatus.ToString().ToLowerInvariant()
        if ($s -match "active|in warranty|ok") { $wStatus = "active" }
        elseif ($s -match "expired|out of warranty") { $wStatus = "expired" }
      }
      if ($wStatus -eq "unknown" -and $endDate) {
        try {
          $parsed = [datetime]::Parse($endDate, [Globalization.CultureInfo]::InvariantCulture)
          $wStatus = if ($parsed.Date -ge (Get-Date).Date) { "active" } else { "expired" }
        } catch { }
      }
      $warranties += [pscustomobject]@{
        name   = $wType
        start  = $startDate
        end    = $endDate
        status = $wStatus
        notes  = if ($w.serviceLevel) { "Level: $($w.serviceLevel)" } else { "" }
      }
    }
  }

  if ($warranties.Count -eq 0) {
    $warranties = @(
      [pscustomobject]@{ name = "Standard"; start = $null; end = $null; status = "unknown"; notes = "No entitlements returned by API." }
    )
  }

  Write-Verbose "HP API returned $($warranties.Count) warranty entitlement(s)."

  [pscustomobject]@{
    manufacturer = "HP"
    model        = $product
    serial       = $Serial
    product      = $null
    checked_at   = (Get-Date).ToUniversalTime().ToString("o")
    source       = "https://css.api.hp.com"
    warranties   = $warranties
    meta = [pscustomobject]@{
      region  = $null
      country = $null
      url     = "https://css.api.hp.com/productWarranty/v1/queries"
      method  = "HTTP"
    }
  }
}

# ──────────────────────────────────────────────
#  WebView2 fallback – HP support site (reCAPTCHA)
# ──────────────────────────────────────────────
function Invoke-HpWarrantyWebView2 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Serial,

    [Parameter()]
    [int] $TimeoutSeconds = 180
  )

  $safeSerial = ($Serial | ConvertTo-Json)

  $autoFillJs = @"
(function() {
  var serialValue = $safeSerial;
  setTimeout(function() {
    var filled = false;
    var inputs = document.querySelectorAll('input[type="text"], input[type="search"], input');
    for (var i = 0; i < inputs.length; i++) {
      var el  = inputs[i];
      var id  = (el.id || '').toLowerCase();
      var nm  = (el.name || '').toLowerCase();
      var ph  = (el.placeholder || '').toLowerCase();
      if (id.indexOf('serial') !== -1 || nm.indexOf('serial') !== -1 || ph.indexOf('serial') !== -1) {
        var nativeSetter = Object.getOwnPropertyDescriptor(
          window.HTMLInputElement.prototype, 'value').set;
        nativeSetter.call(el, serialValue);
        el.dispatchEvent(new Event('input',  { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        filled = true;
        break;
      }
    }
    if (!filled) {
      var first = document.querySelector('input[type="text"]:not([hidden])');
      if (first) {
        var ns = Object.getOwnPropertyDescriptor(
          window.HTMLInputElement.prototype, 'value').set;
        ns.call(first, serialValue);
        first.dispatchEvent(new Event('input',  { bubbles: true }));
        first.dispatchEvent(new Event('change', { bubbles: true }));
      }
    }
  }, 1500);
})();
"@

  $detectJs = @"
(function() {
  var poll = setInterval(function() {
    var body = document.body ? document.body.innerText : '';
    var hasResults = /warranty\s+status|coverage\s+type|start\s+date|end\s+date|active|expired/i.test(body);
    if (!hasResults || document.readyState !== 'complete') return;

    var data = { warranties: [] };
    var rows = document.querySelectorAll('table tr, [role="row"]');
    rows.forEach(function(r) {
      var cells = r.querySelectorAll('td, th, [role="cell"], [role="columnheader"]');
      if (cells.length >= 2) {
        data.warranties.push({ label: cells[0].innerText.trim(),
                               value: cells[1].innerText.trim() });
      }
    });

    var rx = {
      productName:  /Product\s*(?:Name|:)\s*([^\n]+)/i,
      serialNumber: /Serial\s*(?:Number|No\.?|:)\s*([^\n]+)/i,
      warrantyType: /(?:Warranty|Coverage)\s*(?:Type|:)\s*([^\n]+)/i,
      startDate:    /Start\s*(?:Date|:)\s*([^\n]+)/i,
      endDate:      /End\s*(?:Date|:)\s*([^\n]+)/i,
      status:       /(?:Warranty\s+)?Status\s*:?\s*(Active|Expired|In Warranty|Out of Warranty)[^\n]*/i
    };
    for (var k in rx) {
      var m = body.match(rx[k]);
      if (m) data[k] = m[1].trim();
    }

    if (data.warranties.length > 0 || data.productName || data.startDate || data.endDate || data.status) {
      clearInterval(poll);
      window.chrome.webview.postMessage(JSON.stringify(data));
    }
  }, 2000);
})();
"@

  Write-Verbose "Opening WebView2 session for HP warranty check (serial: $Serial)..."

  $raw = Invoke-WebView2Session `
    -Url                   "https://support.hp.com/us-en/check-warranty" `
    -AutoFillScript        $autoFillJs `
    -ResultDetectionScript $detectJs `
    -TimeoutSeconds        $TimeoutSeconds `
    -Title                 "Get-Warranty - HP Warranty Check"

  if (-not $raw) {
    throw "HP warranty check returned no data for serial '$Serial'."
  }

  $model        = if ($raw.productName)  { $raw.productName }  else { $null }
  $startDate    = if ($raw.startDate)    { $raw.startDate }    else { $null }
  $endDate      = if ($raw.endDate)      { $raw.endDate }      else { $null }
  $warrantyType = if ($raw.warrantyType) { $raw.warrantyType } else { "Standard" }

  $status = "unknown"
  if ($raw.status) {
    $s = $raw.status.ToLowerInvariant()
    if ($s -match "active|in warranty")          { $status = "active"  }
    elseif ($s -match "expired|out of warranty") { $status = "expired" }
  }
  if ($status -eq "unknown" -and $endDate) {
    try {
      $parsed = [datetime]::Parse($endDate, [Globalization.CultureInfo]::InvariantCulture)
      $status = if ($parsed.Date -ge (Get-Date).Date) { "active" } else { "expired" }
    } catch { }
  }

  [pscustomobject]@{
    manufacturer = "HP"
    model        = $model
    serial       = $Serial
    product      = $null
    checked_at   = (Get-Date).ToUniversalTime().ToString("o")
    source       = "https://support.hp.com"
    warranties   = @(
      [pscustomobject]@{
        name   = $warrantyType
        start  = $startDate
        end    = $endDate
        status = $status
        notes  = ""
      }
    )
    meta = [pscustomobject]@{
      region  = "us-en"
      country = $null
      url     = "https://support.hp.com/us-en/check-warranty"
      method  = "WebView2"
    }
  }
}