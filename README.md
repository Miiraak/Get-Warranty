# Get-Warranty (PowerShell)

Minimalist PowerShell module to verify the warranty of a machine from a CLI.

- Main control: **`Get-Warranty`**
- Use case:
  1) Without arguments   : detects the constructor + serial number and displays an ASCII table with warranty infos.
  2) Option `-Json`   : JSON structured output (for integration into other tools)

## Manufacturer support (current state)

| Manufacturer | Method | Status |
|:--|:--|:--|
| ASUS | EU RMA Portal (HTML + CSRF) | OK |
| HP | To be implemented | TODO |
| Dell | To be implemented | TODO |
| Lenovo | To be implemented | TODO |
| Acer | To be implemented | TODO |

> Note: ASUS is implemented via `https://eu-rma.asus.com/...` (not `www.asus.com`) in order to avoid reCAPTCHA blocking.

---

## Installation (manual)

1. Place the `Get-Warranty/` folder somewhere (ex: `C:\Tools\Get-Warranty`)
2. Import the module:

```powershell
Import-Module "C:\Tools\Get-Warranty\Get-Warranty.psd1" -Force
```

Optional: To avoid typing `Import-Module` every time, You can copy the `Get-Warranty` folder into one of the your PS env paths :

```powershell
$env:PSModulePath -split ';'
```

#### From PowerShell Gallery
```powershell
Install-Module -Name "Get-Warranty"
```

---

## Uses

#### 1) Check the warranty of the local machine

```powershell
Get-Warranty
```

#### 2) Force a manufacturer + serial number

```powershell
Get-Warranty -Manufacturer asus -Serial "ABCDEFGH1234567"
```

#### 3) JSON output

```powershell
Get-Warranty -Manufacturer asus -Serial "ABCDEFGH1234567" -Json
```

---

## Output structure (JSON)

Example (indicative format):

```json
{
  "manufacturer": "ASUS",
  "model": "G713PV-HX051W",
  "serial": "ABCDEFGH1234567",
  "product": null,
  "checked_at": "2026-03-10T19:31:43.0000000Z",
  "source": "asus-eu-rma",
  "warranties": [
    {
      "name": "Standard",
      "start": "2023-10-28",
      "end": "2025-10-28",
      "status": "expired",
      "notes": "Country: US"
    }
  ],
  "meta": {
    "region": "uk",
    "country": "US",
    "url": "https://eu-rma.asus.com/uk/info/warranty"
  }
}
```
