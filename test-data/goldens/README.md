# Golden test data

Each case is a pair: `<name>.gif` (a real CimBar v2 GIF) and `<name>.json` (a ground-truth
sidecar), used by `web-app/tests/test_goldens.js` to check the decode pipeline byte-for-byte
against known-good values.

Sidecar schema:

- `name`, `fileName` — case name and the original file's name.
- `fileBytesBase64` — the original file, base64-encoded, before payload/encryption/RS.
- `passphrase` — `null` for unencrypted cases, else the string passphrase used to encrypt.
- `fileId`, `total`, `delayMs` — values written into every frame header / the GIF's frame delay.
- `framedDataLength` — byte length of `framedData` (payload plus length prefix, after encryption if any) before it is split into frames.
- `frames[]` — one entry per GIF frame: `seq`; `header` (`{version, encrypted, fileId, seq, total}`, decoded from the frame's first 8 bytes); `dataHex` (2112 protected bytes including the 8-byte header, before RS encoding); `rawHex` (2880 bytes after RS encode + byte-stride interleave — exactly what the frame's cells carry); `cells` (3840 entries, `(symbol << 2) | color`, in row-major order skipping the four 8×8-cell corner finder blocks).

Regenerate with `node web-app/tools/gen_goldens.js` from the repo root (or `node tools/gen_goldens.js` from `web-app/`). Generation is deterministic (fixed seeds, fileIds, salt/IV), so a clean regenerate produces byte-identical files — a diff after regenerating means the format or encoder changed.
