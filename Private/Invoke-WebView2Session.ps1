<#
  .SYNOPSIS
    Opens a WebView2 browser window to interact with a warranty-check page.

  .DESCRIPTION
    Creates a WinForms dialog hosting a WebView2 control.  The caller provides:

      * Url                   – page to load.
      * AutoFillScript        – JavaScript executed after page load to fill form
                                fields automatically.
      * ResultDetectionScript – JavaScript injected via
                                AddScriptToExecuteOnDocumentCreatedAsync.
                                It must call
                                  window.chrome.webview.postMessage(JSON.stringify(data))
                                once results are detected.

    The dialog closes automatically when results are received or the timeout
    expires.  This lets the user solve a reCAPTCHA while the module handles
    the rest.
#>

function Invoke-WebView2Session {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Url,

    # JS executed once after first successful navigation
    [Parameter()]
    [string] $AutoFillScript,

    # JS injected into every document; must postMessage when data is ready
    [Parameter()]
    [string] $ResultDetectionScript,

    # Seconds before the window is closed automatically (1–600)
    [Parameter()]
    [ValidateRange(1, 600)]
    [int] $TimeoutSeconds = 180,

    # Title shown in the window title-bar
    [Parameter()]
    [string] $Title = "Get-Warranty"
  )

  # WebView2 / WinForms require a Single Threaded Apartment (STA) thread
  if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw "Invoke-WebView2Session must run in a Single Threaded Apartment (STA). Start PowerShell with '-STA' (where supported) or create an STA runspace/thread to host this dialog."
  }

  # Ensure WebView2 Runtime + SDK are ready
  Initialize-WebView2

  # ── shared state between the UI event-handlers ──
  $state = @{
    Result    = $null
    Error     = $null
    Completed = $false
    Filled    = $false
  }

  # ── build the form ──
  $form = New-Object Windows.Forms.Form
  $form.Text            = $Title
  $form.Width           = 1100
  $form.Height          = 850
  $form.StartPosition   = "CenterScreen"

  $label = New-Object Windows.Forms.Label
  $label.Text      = "Loading page..."
  $label.Dock      = "Top"
  $label.Height    = 32
  $label.TextAlign = "MiddleCenter"
  $label.BackColor = [Drawing.Color]::FromArgb(255, 255, 243, 205)
  $label.Font      = New-Object Drawing.Font("Segoe UI", 9.5)

  $webView = New-Object Microsoft.Web.WebView2.WinForms.WebView2
  $webView.Dock = "Fill"

  $form.Controls.Add($webView)
  $form.Controls.Add($label)

  # ── timeout timer ──
  $timeout = New-Object Windows.Forms.Timer
  $timeout.Interval = $TimeoutSeconds * 1000
  $timeout.add_Tick({
    if (-not $state.Completed) {
      $state.Error     = "Session timed out after $TimeoutSeconds seconds."
      $state.Completed = $true
      $label.Text      = "Timeout reached. Closing..."
      $label.BackColor = [Drawing.Color]::FromArgb(255, 248, 215, 218)
      $closeTimer = New-Object Windows.Forms.Timer
      $closeTimer.Interval = 1200
      $closeTimer.add_Tick({ $form.Close(); $closeTimer.Dispose() })
      $closeTimer.Start()
    }
    $timeout.Stop()
  })

  # ── WebView2 init completed ──
  $webView.add_CoreWebView2InitializationCompleted({
    param($sender, $e)
    if (-not $e.IsSuccess) {
      $state.Error     = "WebView2 initialisation failed: $($e.InitializationException.Message)"
      $state.Completed = $true
      $form.Close()
      return
    }

    # Listen for messages sent from the injected JS
    $webView.CoreWebView2.add_WebMessageReceived({
      param($s, $evt)
      $msg = $evt.WebMessageAsJson
      if ($msg -and -not $state.Completed) {
        $state.Result    = $msg
        $state.Completed = $true
        $label.Text      = "Results extracted successfully!"
        $label.BackColor = [Drawing.Color]::FromArgb(255, 209, 231, 221)
        $closeTimer = New-Object Windows.Forms.Timer
        $closeTimer.Interval = 600
        $closeTimer.add_Tick({ $form.Close(); $closeTimer.Dispose() })
        $closeTimer.Start()
      }
    })

    # Inject the monitoring / extraction script into every document
    if ($ResultDetectionScript) {
      $webView.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync($ResultDetectionScript) | Out-Null
    }

    $webView.CoreWebView2.Navigate($Url)
    $timeout.Start()
  })

  # ── navigation completed → auto-fill ──
  $webView.add_NavigationCompleted({
    param($sender, $e)
    if ($e.IsSuccess -and $AutoFillScript -and -not $state.Filled) {
      $state.Filled = $true
      $webView.CoreWebView2.ExecuteScriptAsync($AutoFillScript) | Out-Null
      $label.Text      = "Form auto-filled. Solve reCAPTCHA if prompted, then click Submit."
      $label.BackColor = [Drawing.Color]::FromArgb(255, 207, 226, 255)
    }
  })

  # ── show (blocks until the form closes) ──
  $webView.EnsureCoreWebView2Async($null) | Out-Null
  [void] $form.ShowDialog()

  # ── cleanup ──
  $timeout.Stop();  $timeout.Dispose()
  $webView.Dispose()
  $form.Dispose()

  # ── return ──
  if ($state.Error) {
    throw "WebView2 session failed: $($state.Error)"
  }

  if ($state.Result) {
    try {
      $json = $state.Result
      # ExecuteScriptAsync / postMessage may double-encode the JSON string
      if ($json -and $json -is [string] -and $json.StartsWith('"') -and $json.EndsWith('"')) {
        $json = $json | ConvertFrom-Json
      }
      return ($json | ConvertFrom-Json)
    } catch {
      throw "Could not parse WebView2 result as JSON. Raw value (truncated): $($state.Result.Substring(0, [Math]::Min($state.Result.Length, 200)))"
    }
  }

  return $null
}
