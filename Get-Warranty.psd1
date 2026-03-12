@{
  RootModule        = 'Get-Warranty.psm1'
  ModuleVersion     = '0.2.0'
  GUID              = 'b0e8b9f2-3dc4-4b02-9ec8-6bf6d9a5d1c6'
  Author            = 'Miiraak'
  CompanyName       = ''
  Copyright         = '(c) 2026 Miiraak. MIT License.'
  Description       = 'Get-Warranty: PowerShell CLI to check device warranty. ASUS (HTTP/CSRF), HP (WebView2). Dell, Lenovo, Acer planned.'
  PowerShellVersion = '5.1'

  FunctionsToExport = @('Get-Warranty')
  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()

  PrivateData = @{
    PSData = @{
      Tags         = @('warranty','asus','hp','dell','lenovo','acer','cli','webview2')
      LicenseUri   = ''
      ProjectUri   = ''
      ReleaseNotes = @'
v0.2.0 – WebView2 integration & HP provider
  • Added WebView2 infrastructure (Initialize-WebView2, Invoke-WebView2Session)
    for warranty sites that use reCAPTCHA / heavy JavaScript.
  • Implemented HP warranty provider via WebView2.
  • Optimised ASUS provider (verbose logging, timeout parameter).
  • Improved Format-WarrantyTable null handling.
  • Updated documentation (README, module manifest).
'@
    }
  }
}