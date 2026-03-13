function Send-CdpCommand {
  <#
  .SYNOPSIS
    Sends a command to the Chrome DevTools Protocol (CDP) and waits for the response.

  .PARAMETER WebSocket
    The WebSocket connection to the Chrome DevTools Protocol.

  .PARAMETER Id
    The unique identifier for the CDP command.

  .PARAMETER Method
    The CDP method to invoke.

  .PARAMETER Params
    A hashtable of parameters to pass to the CDP method.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [System.Net.WebSockets.ClientWebSocket] $WebSocket,

    [Parameter(Mandatory)]
    [int] $Id,

    [Parameter(Mandatory)]
    [string] $Method,

    [hashtable] $Params = @{}
  )

  $cmd     = @{ id = $Id; method = $Method; params = $Params } | ConvertTo-Json -Depth 10 -Compress
  $sendBuf = [System.Text.Encoding]::UTF8.GetBytes($cmd)
  $segment = [System.ArraySegment[byte]]::new($sendBuf)
  $WebSocket.SendAsync(
    $segment,
    [System.Net.WebSockets.WebSocketMessageType]::Text,
    $true,
    [System.Threading.CancellationToken]::None
  ).GetAwaiter().GetResult()

  $recvBuf = [byte[]]::new(1MB)
  $sw      = [System.Diagnostics.Stopwatch]::StartNew()
  $found   = $null

  while ($sw.Elapsed.TotalSeconds -lt 60 -and $null -eq $found) {
    $accumulated = ""
    do {
      $seg    = [System.ArraySegment[byte]]::new($recvBuf)
      $result = $WebSocket.ReceiveAsync($seg, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
      $accumulated += [System.Text.Encoding]::UTF8.GetString($recvBuf, 0, $result.Count)
    } while (-not $result.EndOfMessage)

    if ($accumulated -notmatch "`"id`"\s*:\s*$Id\b") { continue }

    try {
      $json = $accumulated | ConvertFrom-Json -ErrorAction Stop
    } catch {
      continue
    }

    foreach ($item in @($json)) {
      if ($null -eq $item) { continue }
      $idProp = $item.PSObject.Properties["id"]
      if ($null -ne $idProp -and [int]$idProp.Value -eq $Id) {
        $found = $item
        break
      }
    }
  }

  if ($null -eq $found) {
    throw "CDP command '$Method' (id=$Id) timed out."
  }

  return $found
}

function Get-CdpEvalValue {
  <#
  .SYNOPSIS
    Extracts the 'value' from a CDP Runtime.evaluate response, handling nested structures.
  .PARAMETER CdpResponse
    The response object returned from a Runtime.evaluate CDP command.
  #>
  param($CdpResponse)

  if ($null -eq $CdpResponse) { return $null }

  if ($CdpResponse -is [System.Array]) {
    $CdpResponse = $CdpResponse | Where-Object {
      $null -ne $_ -and $null -ne $_.PSObject.Properties["result"]
    } | Select-Object -First 1
    if ($null -eq $CdpResponse) { return $null }
  }

  $resultProp = $CdpResponse.PSObject.Properties["result"]
  if ($null -eq $resultProp) { return $null }

  $inner = $resultProp.Value
  if ($null -eq $inner) { return $null }

  $innerResultProp = $inner.PSObject.Properties["result"]
  if ($null -eq $innerResultProp) { return $null }

  $resultObj = $innerResultProp.Value
  if ($null -eq $resultObj) { return $null }

  $valueProp = $resultObj.PSObject.Properties["value"]
  if ($null -eq $valueProp) { return $null }

  return $valueProp.Value
}

function Get-SafeProp {
  <#
  .SYNOPSIS
    Safely reads a property from a PSObject (StrictMode compatible).

  .PARAMETER Object
    The object from which to read the property.

  .PARAMETER Name
    The name of the property to read.
  #>
  param($Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $null }
  return $prop.Value
}

function Get-HpWarranty {
  <#
    .SYNOPSIS
      Retrieves HP warranty information for a given serial number.

    .DESCRIPTION
      Uses a headless Chromium browser via CDP to:
      1. Navigate to the HP warranty page
      2. Obtain a reCAPTCHA Enterprise token
      3. Call the HP product search API (from the browser session)
      4. Call the HP warranty API (from the same browser session)
      All API calls are made via fetch() inside the browser to maintain
      session/cookie coherence with the reCAPTCHA token.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Serial,

    [Parameter()]
    [int] $TimeoutSeconds = 60
  )

  $browser = Get-ChromiumPath
  $proc    = $null
  $ws      = $null
  $msgId   = 0

  Write-Verbose "Launching headless browser (CDP) for HP warranty: $browser"

  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
  $listener.Start()
  $port = $listener.LocalEndpoint.Port
  $listener.Stop()

  $browserArgs = @(
    "--headless",
    "--disable-gpu",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-extensions",
    "--remote-debugging-port=$port",
    "about:blank"
  )

  try {
    $proc = Start-Process -FilePath $browser -ArgumentList $browserArgs -PassThru -WindowStyle Hidden

    $cdpBase  = "http://localhost:$port"
    $cdpReady = $false
    $sw       = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $cdpReady -and $sw.Elapsed.TotalSeconds -lt 15) {
      Start-Sleep -Milliseconds 300
      try {
        [void](Invoke-RestMethod -Uri "$cdpBase/json/version" -ErrorAction Stop)
        $cdpReady = $true
      } catch { }
    }
    if (-not $cdpReady) { throw "CDP endpoint not available on port $port." }

    $targets    = Invoke-RestMethod -Uri "$cdpBase/json" -ErrorAction Stop
    $pageTarget = $targets | Where-Object { $_.type -eq "page" } | Select-Object -First 1
    if (-not $pageTarget) { throw "No page target found via CDP." }

    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    [void]($ws.ConnectAsync([Uri]$pageTarget.webSocketDebuggerUrl, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult())

    $msgId++
    [void](Send-CdpCommand -WebSocket $ws -Id $msgId -Method "Page.enable")

    Write-Verbose "Navigating to HP warranty page..."
    $msgId++
    [void](Send-CdpCommand -WebSocket $ws -Id $msgId -Method "Page.navigate" -Params @{
      url = "https://support.hp.com/us-en/check-warranty"
    })

    Write-Verbose "Waiting for page to load..."
    Start-Sleep -Seconds 6

    # Step 1: Get product info via fetch()
    Write-Verbose "Fetching product info for serial: $Serial"
    $jsProductInfo = @"
(function() {
  return fetch('https://support.hp.com/wcc-services/searchresult/us-en?q=$Serial&context=pdp&authState=anonymous&template=WarrantyLanding')
    .then(function(r) { return r.json(); })
    .then(function(data) { return JSON.stringify(data); });
})()
"@

    $msgId++
    $piResult = Send-CdpCommand -WebSocket $ws -Id $msgId -Method "Runtime.evaluate" -Params @{
      expression    = $jsProductInfo
      returnByValue = $true
      awaitPromise  = $true
    }

    $piJson   = Get-CdpEvalValue -CdpResponse $piResult
    $piData   = $null
    $prodName = $null
    $prodNum  = ""

    if ($piJson) {
      try {
        $piParsed = $piJson | ConvertFrom-Json -ErrorAction Stop
        $vrData   = Get-SafeProp (Get-SafeProp (Get-SafeProp $piParsed "data") "verifyResponse") "data"
        if ($null -ne $vrData) {
          $piData   = $vrData
          $prodName = Get-SafeProp $vrData "productName"
          $prodNum  = Get-SafeProp $vrData "productNumber"
          if ($null -eq $prodNum) { $prodNum = "" }
        }
      } catch {
        Write-Verbose "Failed to parse product info: $_"
      }
    }

    Write-Verbose "Product: $prodName ($prodNum)"

    # Step 2: Get reCAPTCHA token
    Write-Verbose "Obtaining reCAPTCHA Enterprise token..."
    $jsRecaptcha = @"
(function() {
  return new Promise(function(resolve, reject) {
    var maxMs = 30000;
    var start = Date.now();
    var check = setInterval(function() {
      if (typeof grecaptcha !== 'undefined' &&
          typeof grecaptcha.enterprise !== 'undefined' &&
          typeof grecaptcha.enterprise.execute === 'function') {
        clearInterval(check);
        grecaptcha.enterprise.execute(
          '6LfX93IaAAAAAKlH_84kr8WSMGbZ-qDaxJxNzrnB',
          { action: 'checkWarranty' }
        ).then(resolve).catch(function(e) { reject('execute failed: ' + e); });
      } else if (Date.now() - start > maxMs) {
        clearInterval(check);
        reject('grecaptcha.enterprise not available');
      }
    }, 500);
  });
})()
"@

    $msgId++
    $captchaResult = Send-CdpCommand -WebSocket $ws -Id $msgId -Method "Runtime.evaluate" -Params @{
      expression    = $jsRecaptcha
      returnByValue = $true
      awaitPromise  = $true
    }

    $captchaToken = Get-CdpEvalValue -CdpResponse $captchaResult
    if (-not $captchaToken -or $captchaToken -isnot [string] -or $captchaToken.Length -le 20) {
      throw "Failed to obtain reCAPTCHA token."
    }
    Write-Verbose "reCAPTCHA token obtained."

    # Step 3: Call warranty API via fetch()
    $tzOff     = [System.TimeZoneInfo]::Local.GetUtcOffset([datetime]::Now)
    $utcPrefix = if ($tzOff.TotalMinutes -lt 0) { "N" } else { "P" }
    $utcOffset = "{0}{1:D2}{2:D2}" -f $utcPrefix, [math]::Abs($tzOff.Hours), [math]::Abs($tzOff.Minutes)

    $jsWarranty = @"
(function() {
  var payload = {
    cc: 'us',
    lc: 'en',
    utcOffset: '$utcOffset',
    devices: [{
      serialNumber: '$Serial',
      productNumber: '$prodNum',
      displayProductNumber: '$prodNum',
      countryOfPurchase: 'us'
    }],
    captchaToken: '$captchaToken'
  };

  return fetch('https://support.hp.com/wcc-services/profile/devices/warranty/specs?authState=anonymous&template=WarrantyLanding', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  })
  .then(function(r) { return r.json(); })
  .then(function(data) { return JSON.stringify(data); });
})()
"@

    Write-Verbose "Calling HP warranty API..."
    $msgId++
    $warResult = Send-CdpCommand -WebSocket $ws -Id $msgId -Method "Runtime.evaluate" -Params @{
      expression    = $jsWarranty
      returnByValue = $true
      awaitPromise  = $true
    }

    $warJson = Get-CdpEvalValue -CdpResponse $warResult

    try {
      [void]($ws.CloseAsync(
        [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
        "done",
        [System.Threading.CancellationToken]::None
      ).GetAwaiter().GetResult())
    } catch { }

  } finally {
    if ($ws)   { try { $ws.Dispose()   } catch { } }
    if ($proc -and -not $proc.HasExited) {
      try { $proc.Kill() } catch { }
      try { $proc.WaitForExit(5000) } catch { }
    }
    if ($proc) { try { $proc.Dispose() } catch { } }
  }

  # ==================================================================
  # Parse warranty response
  # Structure: data.devices[0].warranty.data  (warranty details)
  #            data.devices[0].productSpecs.data  (product details)
  # ==================================================================
  $warData = $null
  if ($warJson) {
    try { $warData = $warJson | ConvertFrom-Json -ErrorAction Stop } catch { }
  }

  $apiDevice    = $null
  $warrantyData = $null
  $specsData    = $null

  if ($null -ne $warData) {
    $devicesArr = Get-SafeProp (Get-SafeProp $warData "data") "devices"
    if ($null -ne $devicesArr) {
      $devicesArr = @($devicesArr)
      if ($devicesArr.Count -gt 0) {
        $apiDevice = $devicesArr[0]
      }
    }
  }

  if ($null -ne $apiDevice) {
    $warrantyData = Get-SafeProp (Get-SafeProp $apiDevice "warranty") "data"
    $specsData    = Get-SafeProp (Get-SafeProp $apiDevice "productSpecs") "data"
  }

  # Model name (prefer productSpecs.productSeriesName, fallback to search result)
  $modelName = Get-SafeProp $specsData "productSeriesName"
  if (-not $modelName) { $modelName = Get-SafeProp $specsData "productName" }
  if (-not $modelName) { $modelName = $prodName }

  # Product number
  $productNum = Get-SafeProp $specsData "productNumber"
  if (-not $productNum) { $productNum = Get-SafeProp $warrantyData "productNumber" }
  if (-not $productNum) { $productNum = $prodNum }

  # Country
  $metaCountry = "us"
  $countries = Get-SafeProp $warrantyData "countries"
  if ($countries) {
    # HP returns comma-separated, take first
    $metaCountry = ($countries -split ",")[0].Trim().ToLower()
  }

  # Warranties (from entitlements array)
  $warrantyList  = @()
  $entitlements  = Get-SafeProp $warrantyData "entitlements"

  if ($null -ne $entitlements) {
    $entitlements = @($entitlements)
  }
  if ($null -ne $entitlements -and $entitlements.Count -gt 0) {
    foreach ($e in $entitlements) {
      $wStart  = $null
      $wEnd    = $null
      $wStatus = "unknown"

      $startRaw = Get-SafeProp $e "warrantyStartDate"
      $endRaw   = Get-SafeProp $e "warrantyEndDate"

      if ($startRaw) {
        try {
          $wStart = ([datetime]::Parse($startRaw, [Globalization.CultureInfo]::InvariantCulture)).ToString("yyyy-MM-dd")
        } catch { $wStart = $startRaw }
      }

      if ($endRaw) {
        try {
          $parsedEnd = [datetime]::Parse($endRaw, [Globalization.CultureInfo]::InvariantCulture)
          $wEnd    = $parsedEnd.ToString("yyyy-MM-dd")
          $wStatus = if ($parsedEnd.Date -ge (Get-Date).Date) { "active" } else { "expired" }
        } catch { $wEnd = $endRaw }
      }

      $wType = Get-SafeProp $e "warrantyTypeDescription"
      if (-not $wType) { $wType = Get-SafeProp $e "serviceType" }
      if (-not $wType) { $wType = "Standard" }

      $wService = Get-SafeProp $e "serviceType"
      if (-not $wService) { $wService = "" }

      $warrantyList += [pscustomobject]@{
        name   = $wType
        start  = $wStart
        end    = $wEnd
        status = $wStatus
        notes  = $wService
      }
    }
  }

  # Fallback: use top-level warranty dates if no entitlements
  if ($warrantyList.Count -eq 0 -and $null -ne $warrantyData) {
    $wStart  = $null
    $wEnd    = $null
    $wStatus = "unknown"

    $startRaw = Get-SafeProp $warrantyData "warrantyStartDate"
    $endRaw   = Get-SafeProp $warrantyData "warrantyEndDate"

    if ($startRaw) {
      try {
        $wStart = ([datetime]::Parse($startRaw, [Globalization.CultureInfo]::InvariantCulture)).ToString("yyyy-MM-dd")
      } catch { $wStart = $startRaw }
    }

    if ($endRaw) {
      try {
        $parsedEnd = [datetime]::Parse($endRaw, [Globalization.CultureInfo]::InvariantCulture)
        $wEnd    = $parsedEnd.ToString("yyyy-MM-dd")
        $wStatus = if ($parsedEnd.Date -ge (Get-Date).Date) { "active" } else { "expired" }
      } catch { $wEnd = $endRaw }
    }

    $warrantyList += [pscustomobject]@{
      name   = Get-SafeProp $warrantyData "warrantyTypeDescription"
      start  = $wStart
      end    = $wEnd
      status = $wStatus
      notes  = Get-SafeProp $warrantyData "serviceType"
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
      country = $metaCountry
      url     = "https://support.hp.com/wcc-services/profile/devices/warranty/specs"
      method  = "ChromiumHeadless"
    }
  }
}