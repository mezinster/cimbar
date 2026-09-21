/**
 * photo-decoder.js — the photo (camera) decode chain: one still image in,
 * one CimBar frame out (spec §4, §7.1).
 *
 * Transliteration of the camera path of
 * app/lib/core/decode/frame_decoder.dart — its `decode` (the RgbBuffer
 * entry point, which hands the whole image to every stage: the YUV ROI crop
 * has no browser equivalent and `decode` ignores the ROI too) and the shared
 * `decodeWithGrid` core. Stage order, statuses and diagnostics follow Dart so
 * the two sides report the same thing about the same photo.
 *
 *   RgbBuffer -> LumaPlane -> FinderLocator -> HomographyGridModel
 *     -> grid-size gate -> WhitePoint -> DriftSolver
 *     -> CellSampler x3840 -> CellClassifier -> unpackCells -> decodeRSFrame
 *     -> decodeHeader
 *
 * Loads after rs.js, format.js, cimbar.js and every photo module
 * (rgb-buffer.js, luma-plane.js, homography.js, finder-locator.js,
 * white-point.js, cell-sampler.js, cell-classifier.js, drift-solver.js).
 * IIFE; exposes window.CimbarPhoto / module.exports.
 */
'use strict';
(function () {
const isNode = typeof module !== 'undefined' && module.exports;
const Fmt = isNode ? require('./format.js') : window.CimbarFormat;
const Core = isNode ? require('./cimbar.js') : window.Cimbar;
const { ReedSolomon } = isNode ? require('./rs.js') : { ReedSolomon: window.ReedSolomon };
const { RgbBuffer } = isNode ? require('./rgb-buffer.js') : window.CimbarRgbBuffer;
const { LumaPlane } = isNode ? require('./luma-plane.js') : window.CimbarLumaPlane;
const { HomographyGridModel } = isNode ? require('./homography.js') : window.CimbarHomography;
const { FinderLocator } = isNode ? require('./finder-locator.js') : window.CimbarFinderLocator;
const { WhitePoint } = isNode ? require('./white-point.js') : window.CimbarWhitePoint;
const { CellSampler, newPatch } = isNode ? require('./cell-sampler.js') : window.CimbarCellSampler;
const { CellClassifier } = isNode ? require('./cell-classifier.js') : window.CimbarCellClassifier;
const { DriftSolver } = isNode ? require('./drift-solver.js') : window.CimbarDriftSolver;

// No supported grid size lies within +-10 of 64 (FrameDecoder.gridTolerance).
const GRID_TOLERANCE = 10;

/**
 * User-facing px-per-cell floor: CapturePolicy.minModulePx, the value Android
 * live scan uses to say "move closer". The locator's own floor (3 px on the
 * 2x-downscaled plane) is lower and guards against photo texture aliasing
 * into false candidates — a different threshold for a different purpose, but
 * both mean "the barcode is too small", so both map to status 'tooSmall'.
 * Note this gate is unreachable from the current test fixtures: shrinking a
 * rendered frame to 1/2, 1/3 or 1/4 makes the locator fail earlier with
 * failReason 'candidates' (it finds nothing at all) before its module
 * estimate could come back under 6. It is reachable in the field, where a
 * small barcode sits in a large, sharp photo and locates cleanly.
 */
const MIN_MODULE_PX = 6;

const _perf = (typeof performance !== 'undefined' && performance.now)
  ? performance
  : (isNode ? require('perf_hooks').performance : null);
function nowMs() { return _perf ? _perf.now() : Date.now(); }

function dist(a, b) {
  const dx = a[0] - b[0], dy = a[1] - b[1];
  return Math.sqrt(dx * dx + dy * dy);
}

function newDiag() {
  return {
    // locate
    candidates: 0, clusters: 0, devNorm: -1, module: 0, tlLuma: 0, secondLuma: 0,
    corners: null, failReason: null, failDetail: null, note: null,
    // geometry
    gridEstimate: 0, whitePoint: null,
    // drift
    driftUsed: false, driftMean: 0, driftMax: 0, widened: 0,
    // cells
    hammingMean: 0, hammingMax: 0, colorMarginMin: Infinity,
    // RS
    rsBlocks: 0, rsOk: 0, rsFail: 0,
    // timings (ms). sampleMs spans the whole decodeWithGrid cell stage, drift
    // included, exactly as Dart's single stopwatch does.
    locateMs: 0, sampleMs: 0, driftMs: 0, rsMs: 0, totalMs: 0,
  };
}

function result(status, diag, extra) {
  return Object.assign({ status, cells: null, raw: null, data: null, blocksFailed: 0, header: null, diag }, extra || {});
}

class CimbarPhoto {
  constructor(opts) {
    const o = opts || {};
    this.locator = o.locator || new FinderLocator();
    this.classifier = o.classifier || new CellClassifier();
    this.rs = o.rs || new ReedSolomon(Fmt.SPEC.rs.eccBytes);
  }

  /** Decodes an ImageData-like object ({width, height, data}) — the page path. */
  static decode(imageData, opts) { return DEFAULT.decode(imageData, opts); }

  decode(imageData, opts) {
    const o = opts || {};
    const t0 = nowMs();
    const diag = newDiag();
    const image = RgbBuffer.fromImageData(imageData);
    const luma = LumaPlane.fromRgb(image);

    const tLocate = nowMs();
    const loc = this.locator.locate(luma);
    diag.locateMs = Math.round(nowMs() - tLocate);
    diag.candidates = loc.candidates;
    diag.clusters = loc.clusters;
    diag.devNorm = loc.devNorm;
    diag.tlLuma = loc.tlLuma;
    diag.secondLuma = loc.secondLuma;
    if (!loc.ok) {
      diag.failReason = loc.failReason;
      diag.failDetail = loc.failDetail;
      diag.note = loc.failDetail;
      // The locator's own module floor means the barcode is too small to
      // scan; every other failure is "no barcode found here".
      const status = loc.failReason === 'tooSmall' ? 'tooSmall' : 'notLocated';
      diag.totalMs = Math.round(nowMs() - t0);
      return result(status, diag);
    }

    const tl = loc.tl, tr = loc.tr, bl = loc.bl, br = loc.br;
    diag.corners = [tl[0], tl[1], tr[0], tr[1], bl[0], bl[1], br[0], br[1]];
    diag.module = loc.module;
    if (loc.module < MIN_MODULE_PX) {
      diag.failReason = 'tooSmall';
      diag.failDetail = `module ${loc.module.toFixed(2)} px below the ${MIN_MODULE_PX} px floor`;
      diag.note = diag.failDetail;
      diag.totalMs = Math.round(nowMs() - t0);
      return result('tooSmall', diag);
    }

    const gm = HomographyGridModel.fromFinders({ tl, tr, bl, br });
    if (gm === null) {
      diag.failReason = 'homography';
      diag.failDetail = 'homography singular';
      diag.note = diag.failDetail;
      diag.totalMs = Math.round(nowMs() - t0);
      return result('notLocated', diag);
    }

    // Keystone compresses opposite sides oppositely; averaging all four sides
    // cancels it to first order. Grouping and term order match Dart exactly.
    const side = (dist(tl, tr) + dist(bl, br) + dist(tl, bl) + dist(tr, br)) / 4;
    const estimate = Math.round(side / loc.module) + Fmt.SPEC.finder.cells;
    diag.gridEstimate = estimate;
    if (Math.abs(estimate - Fmt.SPEC.grid.gridCells) > GRID_TOLERANCE) {
      diag.failReason = 'grid';
      diag.failDetail = `grid estimate ${estimate} cells (supported: ${Fmt.SPEC.grid.gridCells} +- ${GRID_TOLERANCE})`;
      diag.note = diag.failDetail;
      diag.totalMs = Math.round(nowMs() - t0);
      return result('unsupportedGrid', diag);
    }

    // Dart crops an ROI here for the YUV path only; its RgbBuffer `decode`
    // hands the whole image to every later stage, as we do.
    const wp = WhitePoint.fromFinders(image, gm);
    diag.whitePoint = wp;

    const useDrift = o.useDrift === undefined ? true : o.useDrift;
    const r = this.decodeWithGrid(image, gm, { whitePoint: wp, useDrift, luma, diag });
    r.diag.totalMs = Math.round(nowMs() - t0);
    return r;
  }

  /** The stage shared with the exact path: sample, classify, RS, header. */
  decodeWithGrid(image, grid, opts) {
    const o = opts || {};
    const whitePoint = o.whitePoint === undefined ? null : o.whitePoint;
    const useDrift = o.useDrift === undefined ? false : o.useDrift;
    const diag = o.diag || newDiag();
    const t0 = nowMs();

    const sampler = new CellSampler(image, grid, o.luma || null);
    const patch = newPatch();
    const positions = Fmt.usableCellPositions();
    const cells = new Uint8Array(positions.length);
    const gridCells = Fmt.SPEC.grid.gridCells;
    let hammingSum = 0, hammingMax = 0;

    let drift = null;
    if (useDrift) {
      const lp = o.luma || LumaPlane.fromRgb(image);
      const tDrift = nowMs();
      drift = new DriftSolver(new CellSampler(image, grid, lp), this.classifier).solve();
      diag.driftUsed = true;
      diag.driftMs = Math.round(nowMs() - tDrift);
      diag.driftMean = drift.meanAbs;
      diag.driftMax = drift.maxAbs;
      diag.widened = drift.widened;
    } else {
      diag.driftUsed = false;
    }

    for (let k = 0; k < positions.length; k++) {
      const col = positions[k][0], row = positions[k][1];
      if (drift !== null) {
        const idx = row * gridCells + col;
        sampler.sample(col, row, patch, drift.dx[idx], drift.dy[idx]);
      } else {
        sampler.sample(col, row, patch);
      }
      const c = this.classifier.classify(patch, whitePoint);
      cells[k] = Fmt.cellValue(c.symbol, c.color);
      hammingSum += c.hamming;
      if (c.hamming > hammingMax) hammingMax = c.hamming;
      if (c.colorMargin < diag.colorMarginMin) diag.colorMarginMin = c.colorMargin;
    }
    diag.hammingMean = hammingSum / positions.length;
    diag.hammingMax = hammingMax;
    diag.sampleMs = Math.round(nowMs() - t0);

    const tRs = nowMs();
    const raw = Fmt.unpackCells(cells);
    const rs = Core.decodeRSFrame(raw, this.rs);
    diag.rsMs = Math.round(nowMs() - tRs);
    diag.rsBlocks = rs.blocksOk + rs.blocksFailed;
    diag.rsOk = rs.blocksOk;
    diag.rsFail = rs.blocksFailed;
    if (rs.blocksFailed > 0) {
      diag.failReason = 'rs';
      diag.note = `${rs.blocksFailed} of ${diag.rsBlocks} RS blocks uncorrectable`;
      return result('rsFailed', diag, { cells, raw, data: rs.data, blocksFailed: rs.blocksFailed });
    }
    const header = Fmt.decodeHeader(rs.data);
    if (!header.valid) {
      diag.failReason = header.reason;
      diag.note = `frame header rejected (${header.reason})`;
      return result('badHeader', diag, { cells, raw, data: rs.data, blocksFailed: 0, header });
    }
    return result('ok', diag, { cells, raw, data: rs.data, blocksFailed: 0, header });
  }
}

CimbarPhoto.gridTolerance = GRID_TOLERANCE;
CimbarPhoto.minModulePx = MIN_MODULE_PX;

const DEFAULT = new CimbarPhoto();

const API = { CimbarPhoto };
if (isNode) module.exports = API; else window.CimbarPhoto = CimbarPhoto;
})();
