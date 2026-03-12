<#
  .SYNOPSIS
    Locates a Chromium-based browser (Microsoft Edge or Google Chrome) on Windows.

  .DESCRIPTION
    Searches the standard installation paths for Microsoft Edge and Google Chrome.
    Returns the full path to the first executable found.  Throws if neither is
    installed so callers receive a clear error instead of a cryptic "file not found".
#>

function Get-ChromiumPath {
  [CmdletBinding()]
  [OutputType([string])]
  param()

  $candidates = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
  )

  foreach ($p in $candidates) {
    if (Test-Path $p) {
      Write-Verbose "Found Chromium-based browser: $p"
      return $p
    }
  }

  throw "No Chromium-based browser found. Install Microsoft Edge or Google Chrome to use this provider."
}
