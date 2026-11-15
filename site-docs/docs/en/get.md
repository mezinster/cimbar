# Get the app

## Web app

Open **[nfcarchiver.com/cimbar](https://nfcarchiver.com/cimbar/)** in a browser. It works on phones and computers, and needs no installation or account.

Scanning with the camera needs the page to be opened over `https://` (as it is at that address). A copy opened from a file on your computer can still send, and decode a GIF or photos, but browsers won't start its camera scanner.

## Android { #android }

The app is called **CimBar Scanner**. It needs Android 7.0 or later. It asks for one permission, the camera, and has no internet access.

- **[F-Droid](https://f-droid.org/packages/com.nfcarchiver.cimbar/)**: built by F-Droid from the published source, and updated automatically through the F-Droid app.
- **[GitHub releases](https://github.com/mezinster/cimbar/releases)**: an APK attached to each release.

!!! note "F-Droid and GitHub builds don't mix"
    F-Droid signs its builds with its own key, so a GitHub APK can't update an F-Droid install or the other way round. To switch, save your decoded files, uninstall, and install from the other source.

Versions up to 0.10.1 had a different app ID (`com.cimbar.scanner`). Later versions install next to the old app instead of replacing it. Save any files you need from the old one, then uninstall it.

## iPhone and iPad { #iphone }

**CimBar** for iPhone and iPad (iOS 15 or later) is in testing on Apple's **TestFlight** and is not yet on the App Store. Until it is, the [web app](#web-app) works in Safari on iPhone and iPad, camera scanning included.
