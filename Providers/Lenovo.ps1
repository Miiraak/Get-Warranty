function Get-LenovoWarranty {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Serial
  )

  # Lenovo warranty check (https://pcsupport.lenovo.com/warrantyLookup)
  # may require reCAPTCHA.  A WebView2-based implementation is planned.
  throw "Lenovo provider is not yet implemented (WebView2 provider planned)."
}