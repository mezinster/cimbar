# Store images

F-Droid reads these from the tagged commit; other locales fall back to en-US.

| File | Size | Source |
|------|------|--------|
| `icon.png` | 512×512 | generated |
| `featureGraphic.png` | 1024×500 | generated |
| `phoneScreenshots/1.png`, `2.png`, … | phone portrait, e.g. 1080×2400 | taken on a device |

`icon.png` and `featureGraphic.png` are generated, together with the app's launcher
icon, from `spec/cimbar-v2.json` — do not edit them by hand:

```bash
NODE_PATH=/path/to/node_modules node tools/gen_store_graphics.js   # needs Playwright + its Chromium for the PNGs
```

## Screenshots

Committed: `1.png`, Import after a GIF shared from the gallery decoded, and `2.png`, a live scan decoding a barcode off a monitor (Russian UI). Both come from a Pixel 8 Pro and are cropped below the status bar, scaled to 720 px wide and reduced to 256 colors. In `2.png`, the browser-tab strip of the photographed monitor is blurred.

Not generated: take them on a phone (e.g. `adb exec-out screencap -p > 1.png`, or
scrcpy's screenshot) in English, with the debug switch off. Suggested set, in order:

1. Live Scan mid-scan: a barcode shown by the web app's *Present full screen*, the
   aiming square locked on it and the rank progress bar part-way.
2. Result card after a completed scan, with Open / Save to device / Share.
3. Import GIF tab with a CimBar GIF picked and the passphrase field.
4. Camera tab (Take Photo / Gallery / Live Scan).
5. Files tab with a few decoded files.
6. The in-place passphrase prompt after an encrypted live scan.

Keep file names numeric and consecutive; the order is the listing order.
