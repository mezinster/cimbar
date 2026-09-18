# Golden test data

Each case is a pair: `<name>.gif` (a real CimBar v2 GIF) and `<name>.json` (a ground-truth
sidecar), used by `web-app/tests/test_goldens.js` to check the decode pipeline byte-for-byte
against known-good values.

Sidecar schema:

- `name`, `fileName` — case name and the original file's name.
- `fileBytesBase64` — the original file, base64-encoded, before payload/encryption/RS.
- `passphrase` — `null` for unencrypted cases, else the string passphrase used to encrypt.
- `fileId`, `total`, `delayMs` — values written into every frame header / the GIF's frame delay. `total` is always the source frame count (`N`), even for coded cases — it is the RatelessAssembler's completion target, not the GIF's frame count.
- `framedDataLength` — byte length of `framedData` (payload, compressed if `compressed`, then encrypted if any, then length-prefixed) before it is split into frames.
- `frames[]` — one entry per GIF frame: `seq`; `header` (`{version, encrypted, fileId, seq, total}`, decoded from the frame's first 8 bytes); `dataHex` (2112 protected bytes including the 8-byte header, before RS encoding); `rawHex` (2880 bytes after RS encode + byte-stride interleave — exactly what the frame's cells carry); `cells` (3840 entries, `(symbol << 2) | color`, in row-major order skipping the four 8×8-cell corner finder blocks).

## Coded goldens (v2.1)

Two cases — `lorem_coded` and `lorem_coded_enc` — exercise the v2.1 rateless repair-frame and
zlib-compression layers on top of the v2 frame/RS format. Every other case (`hello`, `lorem_12k`,
`lorem_12k_enc`, `edge_one_frame`, `edge_two_frames`) is built with `coded: false` in
`web-app/tools/gen_goldens.js` and gets **no** v2.1 sidecar fields at all — their `.gif`/`.json`
bytes are unchanged from before v2.1, so v2.0 decoders (and `test_goldens.js`'s own fallbacks,
see below) keep working against them unmodified.

For `coded: true` cases, the sidecar carries these additions:

- Top level: `compressed` (bool — whether the payload was deflated before framing; the container is
  only compressed when it saves ≥ `compression.minSaving` (5%) of the uncompressed payload size,
  per spec), `sourceFrames` (`N`, same value as `total`), `repairFrames` (`R`, `Cimbar.gifRepairCount(N)`
  extra frames appended after the `N` source frames), `frameCount` (`N + R`, the actual GIF frame count).
- Per frame: `repair` (bool), `r` (the repair id for a repair frame, else `null` — note `seq` also
  equals `r` for repair frames, since a repair frame's header field `seq` *is* its repair id), `header`
  gains `repair`/`compressed` flags (decoded from the frame's flag byte), and `coef12` (the first 12
  GF(256) coding coefficients from `format.js`'s `codingCoefficients(fileId, seq, total)`, for repair
  frames only — `null` for source frames).

`lorem_coded`/`lorem_coded_enc` use 40 000 chars of repeating lorem-ipsum text (highly compressible)
followed by 8 000 pseudo-random bytes (incompressible), so the deflated container lands at ~8.4–8.5 KB
— compressible enough to trip `compressed: true`, but with genuine random tail bytes RS/repair must
still carry losslessly. This currently yields `sourceFrames: 5`, `repairFrames: 2` for both cases
(confirmed by `gen_goldens.js`'s printed output on regeneration) — comfortably over the brief's
`N >= 4, R >= 1` minimum.

`test_goldens.js` reads `frameCount`/`sourceFrames`/`repairFrames`/header `repair`/`compressed` via
`??` fallbacks (e.g. `side.frameCount ?? side.total`), so it works unmodified against both the plain
v2 goldens (missing these fields entirely) and the new coded goldens.

Regenerate with `node web-app/tools/gen_goldens.js` from the repo root (or `node tools/gen_goldens.js` from `web-app/`). Generation is deterministic (fixed seeds, fileIds, salt/IV), so a clean regenerate produces byte-identical files — a diff after regenerating means the format or encoder changed. The five `coded: false` cases in particular MUST stay byte-identical across a regenerate (`git status --short test-data/goldens` should show no changes to them); if one changes, the generator broke v2.0 compatibility and must be fixed rather than the golden re-committed.
