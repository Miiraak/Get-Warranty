# Get-Warranty (PowerShell)

Minimalist PowerShell module to check the warranty status of a device from the command line.

- **Main command:** `Get-Warranty`
- **Two output modes:**
  1. **ASCII table** (default) – human-friendly summary.
  2. **JSON** (`-Json` switch) – structured output for integration into scripts and tools.
- **Two retrieval strategies:**
  - **Pure HTTP** – fast, no UI; used when the manufacturer's site allows direct API or form submission (e.g. ASUS EU RMA, HP CSS API).
  - **WebView2 browser** – fallback when the site requires reCAPTCHA or heavy JavaScript. A browser window opens; the user solves the captcha while the module handles form-filling and data extraction automatically.

---

## Manufacturer support

| Manufacturer | Method | Status |
|:--|:--|:--|
| ASUS | HTTP – EU RMA Portal (HTML + CSRF token) | ✅ OK |
| HP | HTTP – HP CSS API (with API credentials) | ✅ OK |
| HP | WebView2 – support.hp.com (fallback, reCAPTCHA) | ✅ OK |
| Dell | WebView2 (planned) | ⏳ TODO |
| Lenovo | WebView2 (planned) | ⏳ TODO |
| Acer | WebView2 (planned) | ⏳ TODO |

> **Note:** ASUS uses the EU RMA portal (`eu-rma.asus.com`) instead of `www.asus.com` to avoid reCAPTCHA blocking.

---

## Prerequisites

| Requirement | Details |
|:--|:--|
| **PowerShell** | 5.1 (Windows PowerShell) or 7+ (PowerShell Core on Windows) |
| **OS** | Windows 10 / 11 (WMI is used for local-device detection) |
| **WebView2 Runtime** | Required only when using the WebView2 fallback (no HP API credentials, and future providers). Windows 11 includes it by default. On Windows 10 it is installed alongside Microsoft Edge, or can be installed separately from [Microsoft](https://developer.microsoft.com/en-us/microsoft-edge/webview2/). |
| **HP API credentials** | *Optional.* Register at the [HP Developer Portal](https://developers.hp.com/hp-warranty-api) to get an API key and secret for fast, no-GUI HP warranty lookups via HTTP. |

The WebView2 .NET SDK is **downloaded automatically** on first use and cached
under `%LOCALAPPDATA%\Get-Warranty\WebView2`. No manual NuGet step is needed.
The downloaded package is verified against a pinned SHA-256 hash.

To use a pre-provisioned / offline SDK path, set the environment variable
`GETWARRANTY_WV2_SDK` to the folder containing the WebView2 DLLs.

> **Note:** WebView2 providers require a **Single Threaded Apartment (STA)**
> thread. Windows PowerShell 5.1 runs STA by default. For PowerShell 7+,
> launch with `pwsh -STA` or host the call in an STA runspace.

---

## Installation

#### From PowerShell Gallery

```powershell
Install-Module -Name Get-Warranty
```

#### Manual

1. Place the `Get-Warranty/` folder somewhere (e.g. `C:\Tools\Get-Warranty`).
2. Import the module:

```powershell
Import-Module "C:\Tools\Get-Warranty\Get-Warranty.psd1" -Force
```

> **Tip:** To avoid running `Import-Module` each time, copy the `Get-Warranty` folder into one of the paths listed by `$env:PSModulePath`.

---

## Usage

#### 1) Check the warranty of the local machine

```powershell
Get-Warranty
```

#### 2) Specify a manufacturer and serial number

```powershell
Get-Warranty -Manufacturer asus -Serial "ABCDEFGH1234567"
```

#### 3) JSON output

```powershell
Get-Warranty -Manufacturer asus -Serial "ABCDEFGH1234567" -Json
```

#### 4) HP warranty check

**With API credentials (fast, no GUI):**

```powershell
$env:GETWARRANTY_HP_APIKEY    = "your-api-key"
$env:GETWARRANTY_HP_APISECRET = "your-api-secret"
Get-Warranty -Manufacturer hp -Serial "CND1234567"
```

Register at the [HP Developer Portal](https://developers.hp.com/hp-warranty-api)
to obtain API credentials.

**Without API credentials (WebView2 fallback):**

```powershell
Get-Warranty -Manufacturer hp -Serial "CND1234567"
```

A browser window will open on the HP support page.  The serial number is
auto-filled.  Solve the reCAPTCHA if prompted, then click **Submit**.  The
window closes automatically once the warranty results are detected and
extracted.

#### 5) Verbose logging (useful for debugging)

```powershell
Get-Warranty -Manufacturer asus -Serial "ABCDEFGH1234567" -Verbose
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
  "source": "https://eu-rma.asus.com",
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
    "url": "https://eu-rma.asus.com/uk/info/warranty",
    "method": "HTTP"
  }
}
```

> The `meta.method` field indicates the retrieval strategy used (`HTTP` or `WebView2`).

---

## Architecture

```
Get-Warranty/
├── Get-Warranty.psd1              Module manifest
├── Get-Warranty.psm1              Main module (Get-Warranty, Get-LocalDeviceIdentity)
├── Private/
│   ├── Format-WarrantyTable.ps1   ASCII table formatter
│   ├── Initialize-WebView2.ps1    WebView2 Runtime detection & SDK setup
│   └── Invoke-WebView2Session.ps1 Reusable WebView2 browser session helper
├── Providers/
│   ├── Asus.ps1                   ASUS — pure HTTP (EU RMA + CSRF)
│   ├── Hp.ps1                     HP   — HTTP API (+ WebView2 fallback)
│   ├── Dell.ps1                   Dell — stub (planned)
│   ├── Lenovo.ps1                 Lenovo — stub (planned)
│   └── Acer.ps1                   Acer — stub (planned)
├── Lib/                           (no longer used for SDK cache)
│   └── WebView2/                  (moved to %LOCALAPPDATA%\Get-Warranty\WebView2)
├── LICENSE                        MIT
└── README.md
```

### How providers work

Each provider is a function (`Get-<Manufacturer>Warranty`) that accepts a
`-Serial` parameter and returns a `[pscustomobject]` with a fixed schema
(manufacturer, model, serial, warranties[], meta).

* **HTTP providers** (e.g. ASUS, HP with API credentials) use `Invoke-WebRequest`
  / `Invoke-RestMethod` with session cookies, CSRF tokens, or OAuth.
* **WebView2 providers** (e.g. HP without API credentials) call
  `Invoke-WebView2Session`, which opens a browser window, auto-fills the
  serial, lets the user solve the captcha, and extracts the result via
  injected JavaScript.

### Adding a new provider

1. Create `Providers/<Manufacturer>.ps1` with a `Get-<Manufacturer>Warranty`
   function that returns the standard schema.
2. Add a `switch` branch in `Get-Warranty.psm1`.
3. If the site uses reCAPTCHA, use `Invoke-WebView2Session` (see `Hp.ps1` as
   an example).

---

## License

[MIT](LICENSE)
