# Get-Warranty (PowerShell)

Minimalist PowerShell module to check the warranty status of a device from the command line.

- **Main command:** `Get-Warranty`
- **Two output modes:**
  1. **ASCII table** (default) – human-friendly summary.
  2. **JSON** (`-Json` switch) – structured output for integration into scripts and tools.
- **Two retrieval strategies:**
  - **Pure HTTP** – fast, no UI; used when the manufacturer's site allows direct form submission (e.g. ASUS EU RMA).
  - **Chromium Headless** – used when the site requires reCAPTCHA. The module launches Edge or Chrome in invisible headless mode to obtain the reCAPTCHA token, then calls the manufacturer's backend API directly. No browser window, no user interaction.
  - **WebView2 browser** – available for future providers that require interactive captcha solving.

---

## Manufacturer support

| Manufacturer | Method | Status |
|:--|:--|:--|
| ASUS | HTTP – EU RMA Portal (HTML + CSRF token) | ✅ OK |
| HP | Chromium Headless – support.hp.com (reCAPTCHA token via headless Edge/Chrome + direct API) | :x: Not working |
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
| **Edge or Chrome** | Required for the HP provider (and any future Chromium Headless provider). Microsoft Edge ships with Windows 10/11; Google Chrome is an alternative. |
| **WebView2 Runtime** | Required only for future providers that use the interactive WebView2 strategy. Windows 11 includes it by default; on Windows 10 it is installed alongside Microsoft Edge, or can be installed separately from [Microsoft](https://developer.microsoft.com/en-us/microsoft-edge/webview2/). |

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

#### 4) HP warranty check (headless, no UI)

```powershell
Get-Warranty -Manufacturer hp -Serial "CND1234567"
```

Edge or Chrome is launched invisibly in headless mode to obtain a reCAPTCHA
token.  The token is then used to call the HP warranty backend API directly.
No browser window appears and no user interaction is required.  Subsequent
calls within ~90 seconds reuse the cached token, making them near-instant.

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

> The `meta.method` field indicates the retrieval strategy used (`HTTP`, `ChromiumHeadless`, or `WebView2`).

---

## Architecture

```
Get-Warranty/
├── Get-Warranty.psd1              Module manifest
├── Get-Warranty.psm1              Main module (Get-Warranty, Get-LocalDeviceIdentity)
├── Private/
│   ├── Format-WarrantyTable.ps1   ASCII table formatter
│   ├── Get-ChromiumPath.ps1       Chromium browser detection (Edge / Chrome)
│   ├── Initialize-WebView2.ps1    WebView2 Runtime detection & SDK setup
│   └── Invoke-WebView2Session.ps1 Reusable WebView2 browser session helper
├── Providers/
│   ├── Asus.ps1                   ASUS   — pure HTTP (EU RMA + CSRF)
│   ├── Hp.ps1                     HP     — Chromium Headless (reCAPTCHA token + direct API)
│   ├── Dell.ps1                   Dell   — stub (planned)
│   ├── Lenovo.ps1                 Lenovo — stub (planned)
│   └── Acer.ps1                   Acer   — stub (planned)
├── LICENSE                        MIT
└── README.md
```

### How providers work

Each provider is a function (`Get-<Manufacturer>Warranty`) that accepts a
`-Serial` parameter and returns a `[pscustomobject]` with a fixed schema
(manufacturer, model, serial, warranties[], meta).

* **HTTP providers** (e.g. ASUS) use `Invoke-WebRequest` with session cookies
  and CSRF tokens.
* **Chromium Headless providers** (e.g. HP) use `Get-ChromiumPath` to locate
  Edge or Chrome, launch it with `--headless --dump-dom` to harvest a
  reCAPTCHA v3 token, then call the manufacturer's backend API directly.
  No GUI window, no user interaction, no extra dependencies.
* **WebView2 providers** (future) call `Invoke-WebView2Session`, which opens
  a browser window, auto-fills the serial, lets the user solve the captcha,
  and extracts the result via injected JavaScript.

### Adding a new provider

1. Create `Providers/<Manufacturer>.ps1` with a `Get-<Manufacturer>Warranty`
   function that returns the standard schema.
2. Add a `switch` branch in `Get-Warranty.psm1`.
3. For reCAPTCHA sites with a known backend API, use `Get-ChromiumPath` and
   `--dump-dom` to get the token (see `Hp.ps1`).
4. For sites without a direct API, use `Invoke-WebView2Session` for interactive
   captcha solving.

---

## License

[MIT](LICENSE)
