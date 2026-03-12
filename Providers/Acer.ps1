function Get-AcerWarranty {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Serial
  )

  # Acer warranty check (https://www.acer.com/ac/en/US/content/support)
  # may require reCAPTCHA.  A WebView2-based implementation is planned.
  throw "Acer provider is not yet implemented (WebView2 provider planned)."
}