@{
  RootModule        = 'Get-Warranty.psm1'
  ModuleVersion     = '0.1.1'
  GUID              = 'b0e8b9f2-3dc4-4b02-9ec8-6bf6d9a5d1c6'
  Author            = 'Miiraak'
  CompanyName       = ''
  Copyright         = ''
  Description       = 'Get-Warranty: CLI PowerShell to check device warranty (ASUS via EU RMA; HP TBD; Dell TBD; Lenovo TBD; Acer TBD).'
  PowerShellVersion = '5.1'

  FunctionsToExport = @('Get-Warranty')
  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()

  PrivateData = @{
    PSData = @{
      Tags       = @('warranty','asus','hp','dell','lenovo','acer','cli')
      LicenseUri = ''
      ProjectUri = ''
      ReleaseNotes = 'Initial version: ASUS EU RMA provider. And some basic formatting and JSON output.'
    }
  }
}