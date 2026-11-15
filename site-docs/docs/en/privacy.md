# Privacy policy

**CimBar** · Last updated: 15 November 2026

This policy covers all three CimBar clients: the **web app** at [nfcarchiver.com/cimbar](https://nfcarchiver.com/cimbar/), the **Android** app CimBar Scanner (`com.nfcarchiver.cimbar`) and the **iPhone** and iPad app CimBar (`com.nfcarchiver.cimbar`). It also covers this documentation site.

## In short

CimBar collects nothing. Encoding, decoding, compression and encryption happen entirely on your device: in your browser, or in the app on your phone. The files and messages you send or receive, and your passphrases, are never sent to any server. A code travels only as light, from a screen to a camera.

## Data collection

**We do not collect any data.** Specifically:

- No personal information.
- No usage analytics or tracking.
- No crash reports.
- No cookies, advertising identifiers or other identifiers.
- No location data.
- No files or messages you send or receive, and no passphrases.

## Camera

The camera is used only to scan CimBar codes (live scan and photos). Camera frames and photos are decoded in memory and then discarded; none are kept or sent anywhere.

The one exception is a developer option. With **Debug Mode** switched on in the app's **About** tab, a capture button saves the frame you tap it for into the app's private storage. This happens only when you tap it, and the file stays on your device.

## Files and messages

- **Sending:** the file you pick, or the text you type, is read on your device and turned into a code there. A GIF you share goes only where you send it.
- **Receiving:** a GIF or photo you import is read through the system file picker, photo picker or share sheet; the app reads only what you choose.
- **Received files** are kept in the app's private storage (in the app) and leave it only when you choose **Open**, **Save to device** or **Share**. Uninstalling the app deletes them. The web app keeps nothing: a received file exists in the page until you save it or leave.

## Encryption

When you send with a passphrase, the content is encrypted on your device with AES-256-GCM; the key is derived from your passphrase with PBKDF2-SHA256 (150,000 iterations, random salt per file). The passphrase is never stored, logged or transmitted. If it is lost, nobody, including us, can recover the content. See [Encryption](encryption.md).

## Web app

- It runs entirely in your browser. Encoding and decoding make no network requests.
- The only thing it stores is your interface language, under the key `cimbar.lang` in the browser's local storage, so the language choice is remembered. It sets no cookies. Clearing the site's data removes it.
- **Fonts:** the page loads its typefaces from Google Fonts (`fonts.googleapis.com`, `fonts.gstatic.com`). As with any web resource, your browser's request shows Google your IP address and browser; see the [Google Fonts privacy FAQ](https://developers.google.com/fonts/faq/privacy). No file content or other data is sent.
- **Hosting:** the page is a static site served from Amazon S3 through Amazon CloudFront. Amazon keeps standard access logs (IP address, time, requested address, browser) under its own policies. The web app itself logs nothing.

## Android app

Every permission the app has, and what it is for:

- **Camera** (`CAMERA`): to scan CimBar codes. This is the only permission. The app has **no internet permission** and cannot connect to any server.

Your language choice and the Debug Mode switch are stored in the app's local preferences. Links in **About** (privacy policy, licence, source code) open in your browser; the app itself makes no network requests.

## iPhone and iPad app

What the app may ask for, and what it is for:

- **Camera** (`NSCameraUsageDescription`): to scan CimBar codes.
- **Photos** (`NSPhotoLibraryUsageDescription`): to open the photos you choose to decode the code in them. The app sees only the photos you pick.
- **Microphone** (`NSMicrophoneUsageDescription`): the app **never** records audio and never asks for the microphone. The description exists only because the camera component it uses also contains audio functions, and Apple requires the description for any app containing them.

When you share a file into CimBar from another app, the share extension passes it to the app through a storage area that only the two of them can use (an App Group). The app makes no network requests. Its privacy manifest declares no tracking and no collected data. Your language choice and the Debug Mode switch are stored on the device.

## This website

This documentation site sets no cookies, runs no analytics and loads no third-party fonts or scripts. Its search runs locally in your browser. It is hosted the same way as the web app (Amazon S3 and CloudFront, with standard access logs), and a copy is mirrored on GitHub Pages, which keeps its own logs under [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

## Third-party services

The apps use no third-party services: no analytics, no cloud storage, no remote servers, no social media integrations. The web app relies only on Google Fonts and its hosting, as described above.

## Children's privacy

CimBar collects no data from anyone, including children.

## Changes to this policy

If this policy changes, the new text will be published on this page and the date above updated. Its history is in the [source repository](https://github.com/mezinster/cimbar).

## Open source

The web app and the apps are open source (MIT licence): [github.com/mezinster/cimbar](https://github.com/mezinster/cimbar).

## Contact

Questions about this policy: [support@nfcarchiver.com](mailto:support@nfcarchiver.com).
