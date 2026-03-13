@{
  RootModule        = 'Get-Warranty.psm1'
  ModuleVersion     = '0.2.0'
  GUID              = 'b0e8b9f2-3dc4-4b02-9ec8-6bf6d9a5d1c6'
  Author            = 'Miiraak'
  CompanyName       = ''
  Copyright         = '(c) 2026 Miiraak. MIT License.'
  Description       = 'Get-Warranty: PowerShell CLI to check device warranty. ASUS (HTTP/CSRF), HP (Chromium Headless / CDP). Dell, Lenovo, Acer planned.'
  PowerShellVersion = '5.1'

  FunctionsToExport = @('Get-Warranty')
  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()

  PrivateData = @{
    PSData = @{
      Tags         = @('warranty','asus','hp','dell','lenovo','acer','cli')
      LicenseUri   = ''
      ProjectUri   = ''
      ReleaseNotes = @'
v0.2.0 – Chromium Headless HP provider & WebView2 infrastructure
  • Implemented HP warranty provider via Chromium Headless (CDP).
  • Added WebView2 infrastructure (Initialize-WebView2, Invoke-WebView2Session)
    for future providers that require interactive reCAPTCHA / heavy JavaScript.
  • Optimised ASUS provider (verbose logging, timeout parameter).
  • Improved Format-WarrantyTable null handling.
  • Updated documentation (README, module manifest).
'@
    }
  }
}
