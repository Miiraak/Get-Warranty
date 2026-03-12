function Get-DellWarranty {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Serial
  )

  # Dell warranty check (https://www.dell.com/support/home/) requires
  # reCAPTCHA.  A WebView2-based implementation is planned.
  throw "Dell provider is not yet implemented (WebView2 provider planned)."
}