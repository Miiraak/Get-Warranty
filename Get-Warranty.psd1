@{
  RootModule        = 'Get-Warranty.psm1'
  ModuleVersion     = '0.3.0'
  GUID              = 'b0e8b9f2-3dc4-4b02-9ec8-6bf6d9a5d1c6'
  Author            = 'Miiraak'
  CompanyName       = ''
  Copyright         = '(c) 2026 Miiraak. MIT License.'
  Description       = 'Get-Warranty: PowerShell CLI to check device warranty. ASUS (HTTP/CSRF), HP (HTTP API or WebView2 fallback). Dell, Lenovo, Acer planned.'
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
v0.3.0 – HP HTTP API support & bug fixes
  • HP provider now supports the official HP CSS Warranty API (pure HTTP,
    no GUI) when $env:GETWARRANTY_HP_APIKEY and $env:GETWARRANTY_HP_APISECRET
    are configured.  WebView2 remains as automatic fallback.
  • Fixed WebView2 SDK SHA-256 hash (package was updated on NuGet).
  • Fixed WebView2 E_UNEXPECTED initialisation error by using a dedicated
    UserDataFolder.
  • Code simplification and documentation updates.
'@
    }
  }
}