# Privacy Policy

**Last updated: February 21, 2026**

## Overview

CimBar is a privacy-first tool. All encoding, decoding, and encryption happens entirely on your device — in your browser (web app) or on your Android phone (Android app). No data is ever transmitted to any server.

## Data We Collect

**We collect nothing.**

- No personal information
- No usage analytics or telemetry
- No crash reports
- No advertising identifiers
- No location data
- No files you encode or decode

## How the Apps Work

### Web App (`web-app/`)

- Runs entirely in your browser via JavaScript.
- Files you drag-and-drop never leave your machine — they are read locally by the browser's File API.
- The encrypted GIF is generated in-browser and downloaded directly to your device.
- No network requests are made during encoding or decoding.
- No cookies, localStorage, or IndexedDB are used.

### Android App (`android/`)

- Decodes CimBar GIFs using your device's camera or files stored on your device.
- All Reed-Solomon decoding, AES-256-GCM decryption, and file reconstruction happen on-device.
- Decoded files are saved to the app's private storage directory. They are not uploaded anywhere.
- Camera permissions are used solely for live barcode scanning. No images are retained or transmitted.
- Storage permissions (Android ≤ 12) are used to read GIF files you select. No files are uploaded.
- Language preferences are stored locally in `SharedPreferences` on your device.

## Encryption

Files are encrypted with AES-256-GCM before being encoded into a CimBar barcode. The passphrase you enter never leaves your device and is not stored anywhere. Key derivation uses PBKDF2-SHA256 with 150,000 iterations. Without the correct passphrase, the encoded data is computationally infeasible to decrypt.

## Third-Party Services

The web app is hosted as a static site. Standard web server access logs (IP address, timestamp, requested URL) may be retained by the hosting provider per their own policies. No application-level data is logged.

The Android app does not communicate with any third-party services.

## Open Source

Both the web app and Android app are fully open source. You can inspect every line of code at:

**https://github.com/mezinster/cimbar**

## Contact

If you have questions about this privacy policy, please open an issue on the GitHub repository.
