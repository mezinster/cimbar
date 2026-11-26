/**
 * jpeg-metadata.js — removes APP1-APP15 and COM segments from a JPEG (EXIF,
 * XMP, GPS, comments), keeping APP0/JFIF, tables, frame, scan and entropy data
 * untouched, and drops everything after the first EOI (an appended gain map
 * would carry its own metadata). Port of nfcarchiver's jpeg-metadata.ts.
 * Throws on non-JPEG or malformed input.
 */
'use strict';

// Private scope: classic scripts share one global lexical scope.
(function () {

function stripJpegMetadata(jpeg) {
  if (jpeg.length < 4 || jpeg[0] !== 0xff || jpeg[1] !== 0xd8) throw new Error('Not a JPEG');
  // Every kept piece is a contiguous range of the input: a marker's own FF is
  // the byte before it (fill bytes before that are skipped), so each kept
  // segment is [marker - 1, end). Ranges are collected, then copied once.
  const ranges = [0, 2]; // SOI; flat [start, end) pairs
  const keep = (from, to) => {
    if (ranges[ranges.length - 1] === from) ranges[ranges.length - 1] = to; // adjacent: extend
    else ranges.push(from, to);
  };
  let i = 2;
  while (i < jpeg.length) {
    if (jpeg[i] !== 0xff) throw new Error('Malformed JPEG marker');
    while (i < jpeg.length && jpeg[i] === 0xff) i++; // fill bytes
    if (i >= jpeg.length) throw new Error('Truncated JPEG');
    const markerFF = i - 1; // the FF just before the marker byte
    const marker = jpeg[i++];
    // Standalone markers (no length): TEM, RSTn, SOI, EOI.
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd9)) {
      keep(markerFF, i);
      if (marker === 0xd9) break;
      continue;
    }
    if (i + 2 > jpeg.length) throw new Error('Truncated JPEG');
    const len = (jpeg[i] << 8) | jpeg[i + 1];
    if (len < 2 || i + len > jpeg.length) throw new Error('Bad segment length');
    const segEnd = i + len;
    if (marker === 0xda) {
      // Scan header, then entropy data up to the next real marker: inside
      // entropy data FF is followed only by 00 or D0-D7.
      let j = segEnd;
      for (;;) {
        j = jpeg.indexOf(0xff, j);
        if (j < 0 || j + 1 >= jpeg.length) throw new Error('Truncated JPEG');
        const next = jpeg[j + 1];
        if (next !== 0x00 && !(next >= 0xd0 && next <= 0xd7)) break;
        j++;
      }
      keep(markerFF, j);
      i = j;
      continue;
    }
    const drop = (marker >= 0xe1 && marker <= 0xef) || marker === 0xfe;
    if (!drop) keep(markerFF, segEnd);
    i = segEnd;
  }
  let total = 0;
  for (let k = 0; k < ranges.length; k += 2) total += ranges[k + 1] - ranges[k];
  const out = new Uint8Array(total);
  let at = 0;
  for (let k = 0; k < ranges.length; k += 2) {
    out.set(jpeg.subarray(ranges[k], ranges[k + 1]), at);
    at += ranges[k + 1] - ranges[k];
  }
  return out;
}

const API = { stripJpegMetadata };

if (typeof module !== 'undefined' && module.exports) module.exports = API;
else window.CimbarJpegMeta = API;

})();
