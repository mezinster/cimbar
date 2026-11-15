# Troubleshooting

## The scanner doesn't find the code

- Fit the whole code inside the square, with a little margin around it. The four corner squares must all be visible.
- Turn the sending screen's brightness up, and avoid reflections of lamps or windows on it.
- Hold the phone steady and roughly parallel to the screen.
- Follow the hint on screen: **Move closer**, **Move back**, **Hold still**, **Adjust angle or lighting**.
- **Web app:** camera scanning needs the page opened over `https://`. If the browser asked for camera access and you refused, allow it in the browser's site settings.
- **App:** if you refused camera access, allow it in the system settings for CimBar.

## The counter stops going up

- Keep the code playing. A presented code never runs out of new frames; a GIF repeats, so wait for the next loop.
- Choose a slower frame speed on the sender (400 ms) for long codes; phones can miss frames that change too fast.
- Wavy stripes on the screen (moiré) come from the camera and the screen's pixel grid: move a little further back, or change the angle slightly.

## "This file spans N frames — use Live Scan"

A photo holds only one frame. In the app, a photo works only for single-frame codes; use **Live Scan** for longer ones.

## The web app asks whether to discard the current scan

The photo or frame you just added belongs to a different file from the one being collected. Choose whether to keep the frames you have or start over with the new file.

## Wrong passphrase

Enter it again: the frames are kept, so there is no need to re-scan. Passphrases are case-sensitive. If nobody knows the passphrase, the file can't be opened. See [Encryption](encryption.md).

## "Invalid or unsupported GIF file"

The GIF isn't a CimBar code, or it was changed on the way: some messengers re-compress GIFs or turn them into videos. Send it as a file (document) instead, or use **Present** and scan directly. GIFs from the project's earliest releases aren't readable by current versions.

## "File is too large to process"

The file is larger than CimBar handles. For sending, keep **Share GIF** codes under 500 frames; **Present** handles up to 4096.

## The app can't open a received file

"No app on this phone can open this file" means no installed app handles that file type. Use **Save to device** or share it instead.

## Still stuck?

See [Support](support.md).
