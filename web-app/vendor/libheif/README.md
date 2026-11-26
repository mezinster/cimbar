# Vendored libheif (HEIC/HEIF decoder)

`libheif.js` and `libheif.wasm` are the WebAssembly build of libheif from
**libheif-js 1.23.5** (`libheif-wasm/` in the npm package), unmodified; replace
both files to upgrade. `heic-worker.js` loads them only when a picked photo is
HEIF and the browser could not decode it itself.

- libheif-js 1.23.5: https://github.com/catdad-experiments/libheif-js
  (npm `libheif-js@1.23.5`, tarball integrity
  `sha512-umXZPthnWZtF3iG/5mQG+AZ2V6i0UeYpo3z2CkggTEgL8dKmIIwJT6TDuAMuabXa1yTW8uJ1ZAgR+CxNTklYYw==`)
- libheif 1.23.5 (LGPL-3.0): https://github.com/strukturag/libheif
- libde265 1.0.15 (LGPL-3.0), the HEVC decoder inside the wasm: https://github.com/strukturag/libde265
- dav1d (BSD-2-Clause), the AV1 decoder inside the wasm: https://code.videolan.org/videolan/dav1d

Licences:

- `LICENSE` — the libheif notice and the LGPL-3.0 text, copied unmodified
  from `libheif-wasm/LICENSE` in the same package.
- `DAV1D-LICENSE` — dav1d's BSD-2-Clause licence, copied from `COPYING` in the
  upstream dav1d repository.

To upgrade: `npm pack libheif-js@<version>` outside the repo, copy
`package/libheif-wasm/libheif.js`, `libheif.wasm` and `LICENSE` here, update
the versions and checksums below, and run `sh tests/run_all.sh` from `web-app/`
(`tests/test_image_decode.js` checks these checksums and decodes a real HEIC
through the vendored files).

SHA-256:

```
376c0bb483c23ac458cd22d718074693748ea75eddc3e4929353d4153e365a2e  libheif.js
184d3d20f8323877f13e9f5254f9c6a0ce272c9a3a2f823b0b2bcd2ee9f73f80  libheif.wasm
fa81ce652315b013359d6e8e4744335f31a50c7c192907176d3632f78a3b4596  LICENSE
dd92c3c2247c5651606fc23a5e2d6a1ebc5ace9a3e49cbde0e12f05ad1cb1ee5  DAV1D-LICENSE
```
