# Print Direct Agent

Open-source print agent for the **Print Direct** Odoo module (Odoo 18 / 19 / 20).
It runs next to your printers (Windows, Linux, Android; macOS/iOS sources included) and prints
what Odoo sends: ESC/POS thermal tickets, ZPL labels and PDFs.

## How it works

1. Download the app from the host form in Odoo (*Devices > Print Boxes*) and install it on the PC (or tablet) the printers are connected to.
2. Open the app. Odoo shows "App detected and active on this computer".
3. Click **Detect and Link this Device**. The host is linked and all printers are detected and synced automatically.

No copying or pasting is needed. Only for a **remote connection** (the device is on a different physical network)
copy the Server URL and Security Token shown in Odoo into the app once.

The agent exposes a local server (`http://127.0.0.1:18069`, HTTPS on `18070`) used by the browser, and can also poll
your Odoo server (cloud relay) so tablets and phones can print through it.

## What it connects to

- **Your own Odoo server** (the URL you enter): printer sync, job relay and update check
  (`/web/print_agent/version.json`). Requests are signed with HMAC-SHA256 using your token.
- Nothing else. No telemetry, no analytics, no third-party servers.
- The UI loads Google Fonts. The local HTTPS certificate is created with [mkcert](https://github.com/FiloSottile/mkcert)
  (bundled on Windows; downloaded from its official GitHub releases on macOS/Linux if missing).
- The update check only offers the download URL configured in **your** Odoo.

## Build

Requires Flutter (Dart >= 3.5).

```bash
flutter pub get
flutter run -d windows   # or linux / android
flutter build windows --release
```

Third-party binaries are **not** in this repository. For Windows builds place them manually:

- `assets/mkcert/mkcert.exe` (from the mkcert releases)
- `assets/apps/PDFtoPrinter.exe` (used to send PDFs to printers on Windows)

## License

MIT, see [LICENSE](LICENSE).
