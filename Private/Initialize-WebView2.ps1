<#
  .SYNOPSIS
    Detects the WebView2 Runtime, downloads the SDK if needed, and loads assemblies.

  .DESCRIPTION
    Provides three helper functions used by providers that need a real browser
    (e.g. when the target site requires reCAPTCHA):

      Test-WebView2Runtime   – Checks the Windows registry / filesystem for the
                               Evergreen WebView2 Runtime.
      Install-WebView2Sdk    – Downloads the Microsoft.Web.WebView2 NuGet package
                               and extracts the managed + native DLLs into a
                               user-writable cache directory.
      Initialize-WebView2    – Orchestrates the above and loads the assemblies into
                               the current PowerShell session.

    The SDK cache is stored under $env:LOCALAPPDATA\Get-Warranty\WebView2 by
    default.  Set $env:GETWARRANTY_WV2_SDK to override with a custom path
    (e.g. for pre-provisioned / offline installs).
#>

function Test-WebView2Runtime {
  [CmdletBinding()]
  [OutputType([bool])]
  param()

  # Evergreen WebView2 Runtime client GUID
  $guid = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
  $regPaths = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$guid",
    "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$guid",
    "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$guid"
  )

  foreach ($p in $regPaths) {
    try {
      if (Test-Path $p) {
        $ver = (Get-ItemProperty -Path $p -ErrorAction SilentlyContinue).pv
        if ($ver) {
          Write-Verbose "WebView2 Runtime detected (version $ver) at $p"
          return $true
        }
      }
    } catch { continue }
  }

  # Fallback: look for the EdgeWebView folder
  $folders = @(
    "$env:ProgramFiles\Microsoft\EdgeWebView",
    "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView",
    "$env:LOCALAPPDATA\Microsoft\EdgeWebView"
  )
  foreach ($f in $folders) {
    if (Test-Path $f) {
      Write-Verbose "WebView2 Runtime folder found: $f"
      return $true
    }
  }

  Write-Verbose "WebView2 Runtime not detected."
  return $false
}

function Install-WebView2Sdk {
  [CmdletBinding()]
  param(
    [Parameter()]
    # Pin a known-good version.  Bump this when a newer SDK is verified.
    # See https://www.nuget.org/packages/Microsoft.Web.WebView2 for releases.
    [string] $PackageVersion = "1.0.2903.40"
  )

  # Expected SHA-256 hash of the pinned NuGet package (lowercase hex).
  # Update this whenever $PackageVersion is bumped.
  $expectedHash = "65B2580B92900A07B06AE68E5A7E03E8CE498E09E155F5F38B5F09E9F8AF8E37"

  # ── Resolve cache directory ──
  # Priority: $env:GETWARRANTY_WV2_SDK > $env:LOCALAPPDATA\Get-Warranty\WebView2
  if ($env:GETWARRANTY_WV2_SDK -and (Test-Path $env:GETWARRANTY_WV2_SDK)) {
    $wv2Dir = $env:GETWARRANTY_WV2_SDK
    Write-Verbose "Using administrator-provisioned SDK path: $wv2Dir"
  } else {
    $cacheRoot = Join-Path $env:LOCALAPPDATA "Get-Warranty"
    $wv2Dir    = Join-Path $cacheRoot "WebView2"
  }

  # Already present?
  if (Test-Path (Join-Path $wv2Dir "Microsoft.Web.WebView2.Core.dll")) {
    Write-Verbose "WebView2 SDK already cached in $wv2Dir"
    return $wv2Dir
  }

  Write-Verbose "Downloading Microsoft.Web.WebView2 $PackageVersion from NuGet..."
  try {
    if (-not (Test-Path $wv2Dir)) {
      New-Item -Path $wv2Dir -ItemType Directory -Force | Out-Null
    }
  } catch {
    throw "Cannot create SDK cache directory '$wv2Dir'. Check folder permissions or set `$env:GETWARRANTY_WV2_SDK to a writable path."
  }

  $nugetUrl  = "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$PackageVersion"
  $tempFile  = Join-Path ([IO.Path]::GetTempPath()) "WebView2_$PackageVersion.zip"
  $tempDir   = Join-Path ([IO.Path]::GetTempPath()) "WebView2_extract_$PackageVersion"

  try {
    # Download
    $iwrParams = @{ Uri = $nugetUrl; OutFile = $tempFile; ErrorAction = "Stop" }
    if ($PSVersionTable.PSVersion.Major -lt 6) { $iwrParams.UseBasicParsing = $true }
    Invoke-WebRequest @iwrParams

    # Verify integrity (SHA-256)
    $actualHash = (Get-FileHash -Path $tempFile -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
      throw ("Package integrity check failed.`n" +
             "  Expected SHA-256: $expectedHash`n" +
             "  Actual SHA-256:   $actualHash`n" +
             "The downloaded file may be corrupted or tampered with.")
    }
    Write-Verbose "Package SHA-256 verified: $actualHash"

    # Extract
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    Expand-Archive -Path $tempFile -DestinationPath $tempDir -Force

    # Choose framework folder
    $fxName    = if ($PSVersionTable.PSVersion.Major -ge 6) { "netcoreapp3.0" } else { "net45" }
    $libSource = Join-Path $tempDir "lib\$fxName"
    if (-not (Test-Path $libSource)) {
      $libSource = Get-ChildItem (Join-Path $tempDir "lib") -Directory |
                   Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $libSource -or -not (Test-Path $libSource)) {
      throw "Managed DLLs not found inside the NuGet package."
    }

    # Copy managed assemblies
    Copy-Item (Join-Path $libSource "*.dll") -Destination $wv2Dir -Force

    # Copy native WebView2Loader.dll for current architecture
    $arch = if ([Environment]::Is64BitProcess) { "win-x64" } else { "win-x86" }
    $nativeSrc = Join-Path $tempDir "runtimes\$arch\native"
    if (Test-Path $nativeSrc) {
      Copy-Item (Join-Path $nativeSrc "*.dll") -Destination $wv2Dir -Force
    }

    Write-Verbose "WebView2 SDK installed to $wv2Dir"
    return $wv2Dir
  } catch {
    throw "Failed to install WebView2 SDK: $_`nEnsure you have internet access or pre-provision the DLLs via `$env:GETWARRANTY_WV2_SDK."
  } finally {
    Remove-Item $tempFile  -Force -ErrorAction SilentlyContinue
    Remove-Item $tempDir   -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Initialize-WebView2 {
  [CmdletBinding()]
  param()

  # 1 – Runtime check
  if (-not (Test-WebView2Runtime)) {
    throw @"
WebView2 Runtime is required but was not detected.
Install the Evergreen Runtime from:
  https://developer.microsoft.com/en-us/microsoft-edge/webview2/
(Windows 11 includes it by default; Windows 10 may require a separate install.)
"@
  }

  # 2 – SDK / assemblies
  $wv2Dir = Install-WebView2Sdk

  # 3 – Load into the session
  Add-Type -AssemblyName System.Windows.Forms  -ErrorAction SilentlyContinue
  Add-Type -AssemblyName System.Drawing        -ErrorAction SilentlyContinue

  $coreDll     = Join-Path $wv2Dir "Microsoft.Web.WebView2.Core.dll"
  $winformsDll = Join-Path $wv2Dir "Microsoft.Web.WebView2.WinForms.dll"

  try {
    [void][Reflection.Assembly]::LoadFrom($coreDll)
    [void][Reflection.Assembly]::LoadFrom($winformsDll)
    Write-Verbose "WebView2 assemblies loaded from $wv2Dir"
  } catch {
    throw "Failed to load WebView2 assemblies: $_"
  }
}
