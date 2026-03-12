function Get-HpWarranty {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Serial,

    [Parameter()]
    [int] $TimeoutSeconds = 180
  )

  # ── JavaScript: auto-fill the serial number field ──
  $autoFillJs = @"
(function() {
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
        nativeSetter.call(el, '$Serial');
        el.dispatchEvent(new Event('input',  { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        filled = true;
        break;
      }
    }
    if (!filled) {
      // Fallback: fill the first visible text input
      var first = document.querySelector('input[type="text"]:not([hidden])');
      if (first) {
        var ns = Object.getOwnPropertyDescriptor(
          window.HTMLInputElement.prototype, 'value').set;
        ns.call(first, '$Serial');
        first.dispatchEvent(new Event('input',  { bubbles: true }));
        first.dispatchEvent(new Event('change', { bubbles: true }));
      }
    }
  }, 1500);
})();
"@

  # ── JavaScript: detect and extract warranty results, then postMessage ──
  $detectJs = @"
(function() {
  var poll = setInterval(function() {
    var body = document.body ? document.body.innerText : '';

    // Heuristic: the results page contains one of these phrases
    var hasResults = /warranty\s+status|coverage\s+type|start\s+date|end\s+date|active|expired/i.test(body);
    if (!hasResults || document.readyState !== 'complete') return;

    var data = { warranties: [] };

    // Attempt table-based extraction
    var rows = document.querySelectorAll('table tr, [role="row"]');
    rows.forEach(function(r) {
      var cells = r.querySelectorAll('td, th, [role="cell"], [role="columnheader"]');
      if (cells.length >= 2) {
        data.warranties.push({ label: cells[0].innerText.trim(),
                               value: cells[1].innerText.trim() });
      }
    });

    // Regex-based extraction from page text
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

  # ── Normalise into the standard output object ──
  $model        = if ($raw.productName)  { $raw.productName }  else { $null }
  $startDate    = if ($raw.startDate)    { $raw.startDate }    else { $null }
  $endDate      = if ($raw.endDate)      { $raw.endDate }      else { $null }
  $warrantyType = if ($raw.warrantyType) { $raw.warrantyType } else { "Standard" }

  $status = "unknown"
  if ($raw.status) {
    $s = $raw.status.ToLowerInvariant()
    if ($s -match "active|in warranty")      { $status = "active"  }
    elseif ($s -match "expired|out of warranty") { $status = "expired" }
  }
  if ($status -eq "unknown" -and $endDate) {
    try {
      $parsed = [datetime]::Parse($endDate)
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