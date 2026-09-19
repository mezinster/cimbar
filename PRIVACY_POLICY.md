# Privacy Policy

**Last updated: September 19, 2026**

This policy covers the CimBar web app (https://nfcarchiver.com/cimbar/) and the CimBar Scanner Android app (`com.nfcarchiver.cimbar`).

## Overview

CimBar is a privacy-first tool. All encoding, decoding, compression and encryption happen entirely on your device — in your browser (web app) or on your Android phone (Android app). The files you encode or decode, and your passphrases, are never transmitted to any server.

## Data We Collect

**We collect nothing.**

- No personal information
- No usage analytics or telemetry
- No crash reports
- No advertising identifiers
- No location data
- No files you encode or decode
- No passphrases

## Web App

- Runs entirely in your browser via JavaScript. Encoding and decoding make no network requests.
- Files you drop or pick are read locally by the browser's File API and never leave your machine. The GIF is generated in the browser and downloaded directly to your device.
- The only thing the web app stores is your interface language, under the key `cimbar.lang` in the browser's localStorage, so the language picker remembers your choice. It uses no cookies and no other storage. Clearing the site's data removes it.
- **Fonts:** the page loads its typefaces from Google Fonts (`fonts.googleapis.com` / `fonts.gstatic.com`). As with any web resource, your browser's request reveals your IP address and user agent to Google; see the [Google Fonts privacy FAQ](https://developers.google.com/fonts/faq/privacy). No file content or other data is sent.
- **Hosting:** the web app is a static site served from Amazon S3 through Amazon CloudFront. The hosting provider may keep standard access logs (IP address, timestamp, requested URL, user agent) under its own policies. No application-level data is logged.

## Android App

- **Permissions:** the app requests only the **camera**, used solely to scan barcodes (live scan and in-app photo). It has no internet permission and cannot connect to any server.
- Camera frames and photos are decoded in memory and discarded; none are retained or transmitted. (Exception: with the developer debug switch enabled in About, the capture button saves the frame you tap it for, as `capture_<time>.png`/`.txt`, into the app's private storage — only when you tap it.)
- GIFs and images you import are opened through the Android system picker or shared to the app by another app; the app reads only the file you choose.
- Decoded files are saved to the app's private storage. They leave it only when you choose Open, Save to device or Share.
- Your language choice and the developer debug switch are stored locally in the app's preferences.
- Links in About (privacy policy, license, source code) open in your browser; the app itself makes no network requests.
- Uninstalling the app deletes its private storage, including decoded files you have not saved elsewhere.

## Encryption

Files can optionally be encrypted with AES-256-GCM before being encoded into a CimBar barcode. The passphrase you enter never leaves your device and is not stored anywhere. Key derivation uses PBKDF2-SHA256 with 150,000 iterations and a random salt per file. Without the correct passphrase, the encoded data is computationally infeasible to decrypt.

## Third-Party Services

The Android app uses no third-party services. The web app relies only on Google Fonts and its static hosting, as described above.

## Children

The apps collect no data from anyone, including children.

## Changes

Changes to this policy are published in this file, with its history in the source repository.

## Open Source

Both the web app and the Android app are open source (MIT license). You can inspect every line of code at:

**https://github.com/mezinster/cimbar**

## Contact

If you have questions about this privacy policy, please open an issue at https://github.com/mezinster/cimbar/issues.
