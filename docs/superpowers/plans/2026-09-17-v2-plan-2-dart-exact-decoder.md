# CimBar v2 — Plan 2: Dart Format Layer, Exact Decoder, Assembler, GIF Import, CLI, Corpus Scaffolding

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the v2 format to Dart, decode the golden GIFs byte-for-byte through a new `FrameDecoder`/`FrameAssembler`, switch the Android GIF import to v2, and ship the offline CLI decoder plus corpus-benchmark scaffolding that Plan 3's camera work will be measured with.

**Architecture:** New pure-Dart packages under `lib/core/format/` (constants mirrored from `spec/cimbar-v2.json` and asserted equal by a test, tiles, header, bit packing, RS framing, file container) and `lib/core/decode/` (RGB buffer, grid model, cell sampler, cell classifier, frame decoder, frame assembler, diagnostics, golden sidecar loader, report). The GIF path uses an `ExactGridModel`; Plan 3 adds the locator and a homography grid model behind the same `FrameDecoder.decode(image, grid)` call. No Flutter imports anywhere under `lib/core/format/` or `lib/core/decode/`, so `dart run tool/decode_image.dart` works without a device. v1 camera code stays in place (Plan 4 deletes it); only the GIF import pipeline moves to v2 here.

**Tech Stack:** Dart 3 (SDK ≥ 3.3), `image` ^4.2 (GIF/PNG/JPEG decode), existing `reed_solomon.dart`/`galois_field.dart`/`crypto_service.dart`. Tests via `flutter test` wrapped by `android/tests/run_all.sh`.

**Spec:** `docs/superpowers/specs/2026-09-17-cimbar-v2-format-design.md` — §3, §4, §6.1, §6.6–6.8 (exact path), §7.2, §9.2, §9.3 (scaffolding), §9.4 Dart rows for spec constants / header / packing / golden decode. The sidecar schema is `test-data/goldens/README.md`.

## Global Constraints

- All new code under `android/lib/core/format/` and `android/lib/core/decode/` and `android/tool/` imports only `dart:*`, `package:image`, `package:pointycastle` (via the existing crypto service) and files within `lib/core/`. **No `package:flutter`** there.
- Constants must equal `spec/cimbar-v2.json`: gridCells 64, cellPx 8, gapPx 1, pitchPx 9, gridPx 576, quietPx 16, framePx 608; finder cells 7, cornerCells 8, outerPx 63, ringInsetPx 9, corePx 27, coreInsetPx 18, dotPx 9, dotInsetPx 27, centers tl (3.5,3.5) tr (60.5,3.5) bl (3.5,60.5) br (60.5,60.5), dot on tr/bl/br; palette `[0,255,0] [0,255,255] [255,255,0] [255,85,255]`; symbolBits 4, colorBits 2; rs blockTotal 255, eccBytes 64, interleave `stride-skip-short`; header lengthBytes 8, version 2; capacity 3840 / 2880 / 2112 / 2104; the 16 tiles listed in Task 1.
- Bit packing: 6 bits per cell, 4 symbol bits high then 2 color bits low, MSB-first over the 2880 raw bytes, row-major over usable cells (first (8,0), last (55,63)).
- Interleave rule (spec §4.3, stride-skip-short): for `j` from 0 to max block size − 1, for `i` from 0 to N − 1, append byte `j` of block `i` if `j < size_i`. Block sizes: eleven 255 then one 75. **A literal `j × N + i` is wrong for `j ≥ 75`.**
- Header: `[ver 0x02][flags bit0=encrypted, bits 1–7 must be 0][fileId u16 BE][seq u16 BE][total u16 BE]`; decode reasons `short`, `version`, `flags`, `total`, `seq` (same strings as the JS).
- Assembler acceptance (spec §4.2): reject when any RS block failed (reason `rs`), invalid header (its reason), same fileId but different total (`total`), duplicate seq (`duplicate`); a new fileId resets the collection and is accepted.
- Cell sampling coordinates: cell units where one unit is one pitch (9 px), origin at the grid origin; tile pixel `(i, j)` of cell `(col, row)` is at cell coordinate `(col + (i + 0.5) / 9, row + (j + 0.5) / 9)`; `ExactGridModel` maps `(cx, cy)` to source `(16 + 9·cx, 16 + 9·cy)`. Finder centers are therefore at cell coords (3.5, 3.5) etc., matching the spec.
- Symbol = average hash (bit = luma > patch mean), min Hamming over the 16 tiles. Color = mean RGB over the winning tile's lit pixels, normalized chroma `(R−G, G−B, B−R) / max(R,G,B,1)`, nearest palette entry (palette references computed through the same formula), margin = second − best.
- Tests run from `android/`: `sh tests/run_all.sh` (never bare `flutter test` — its `\r` progress output truncates). Single file: `flutter test test/core/format/cimbar_spec_test.dart`. Tests read repo-root files via relative paths from `android/` (`../spec/cimbar-v2.json`, `../test-data/goldens/`).
- Lints in `analysis_options.yaml`: `prefer_const_constructors`, `prefer_const_declarations`, `avoid_print` (use `stdout.writeln` in the CLI), `prefer_single_quotes`. `flutter analyze` must stay clean.
- Commit after every task; message ends with the two lines:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi`

---

## File map

| Path (under `android/`) | Responsibility |
|---|---|
| `lib/core/format/cimbar_spec.dart` | Constants mirrored from the spec JSON, cell geometry helpers, RS block sizes |
| `lib/core/format/tiles.dart` | Tile hex ↔ bits, Hamming |
| `lib/core/format/frame_header.dart` | 8-byte header encode/decode with reasons |
| `lib/core/format/bit_packing.dart` | 6-bit cell values ↔ 2880 raw bytes |
| `lib/core/format/rs_framing.dart` | RS block partition, stride-skip-short interleave, encode/decode a frame |
| `lib/core/format/file_container.dart` | Length prefix strip, `[u32 nameLen][name][file]` parse, encryption magic detect |
| `lib/core/decode/rgb_buffer.dart` | Flat RGB byte buffer with bilinear sampling; built from `img.Image` |
| `lib/core/decode/grid_model.dart` | `GridModel` interface + `ExactGridModel` |
| `lib/core/decode/cell_sampler.dart` | Samples an 8×8 tile patch (luma + RGB) through a grid model |
| `lib/core/decode/cell_classifier.dart` | Symbol by average hash, color by normalized chroma |
| `lib/core/decode/diagnostics.dart` | `DecodeStatus`, `Diagnostics`, `FrameResult` |
| `lib/core/decode/frame_decoder.dart` | `decode(image, {grid})`, `decodeExact(image)` |
| `lib/core/decode/frame_assembler.dart` | Sequence-slot assembly with acceptance rules |
| `lib/core/decode/golden_sidecar.dart` | Loads `test-data/goldens/*.json` |
| `lib/core/decode/decode_report.dart` | Structured `stage=…` lines and truth comparison |
| `lib/core/services/decode_pipeline.dart` | GIF import on v2 (rewritten) |
| `tool/decode_image.dart` | CLI wrapper around the decoder + report |
| `test/core/format/*_test.dart`, `test/core/decode/*_test.dart` | Tests per file |
| `test/fixtures/corpus/README.md`, `test/fixtures/corpus/v1_720p_negative/meta.json` | Corpus scaffolding |
| `tests/run_all.sh` | Prints the corpus table after the suite |
| `android/CLAUDE.md`, `CLAUDE.md`, `CHANGELOG.md` | Docs |

Deleted in this plan: `test/core/services/decode_pipeline_test.dart`, `test/core/services/end_to_end_test.dart` (both test the v1 GIF path through the v1 decoder and are replaced by golden-based tests). The v1 test encoder and the remaining v1 tests stay until Plan 4.

Test helper used by several tests (define it in each test file that needs it; keep it tiny):

```dart
String repoPath(String rel) => '../$rel'; // tests run with cwd = android/
```

---

### Task 1: CimbarSpec constants and Tiles

**Files:**
- Create: `lib/core/format/cimbar_spec.dart`
- Create: `lib/core/format/tiles.dart`
- Test: `test/core/format/cimbar_spec_test.dart`

**Interfaces:**
- Produces `CimbarSpec` (all static): `version, gridCells, cellPx, gapPx, pitchPx, gridPx, quietPx, framePx, finderCells, cornerCells, finderOuterPx, finderRingInsetPx, finderCorePx, finderCoreInsetPx, finderDotPx, finderDotInsetPx, finderCenters (Map<String, List<double>>), finderDotOn (List<String>), palette (List<List<int>>), tiles (List<String>), symbolBits, colorBits, bitsPerCell, rsBlockTotal, rsEccBytes, rsInterleave, headerLen, usableCells, rawBytesPerFrame, dataBytesPerFrame, fileBytesPerFrame, defaultDelayMs, delayOptionsMs`; functions `isReservedCell(col,row)`, `usableCellPositions` (cached `List<CellPos>`), `cellOriginX(col)`, `cellOriginY(row)`, `rsBlockSizes()`.
- Produces `CellPos(col, row)`.
- Produces `Tiles`: `bits` (`List<Uint8List>` of 16×64), `hexToTile(String) → Uint8List`, `tileToHex(Uint8List) → String`, `hamming(a, b) → int`, `popcount(t) → int`.

- [ ] **Step 1: Write the failing test**

`test/core/format/cimbar_spec_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/tiles.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final spec = jsonDecode(File(repoPath('spec/cimbar-v2.json')).readAsStringSync())
      as Map<String, dynamic>;

  group('CimbarSpec matches spec/cimbar-v2.json', () {
    test('version and grid', () {
      final g = spec['grid'] as Map<String, dynamic>;
      expect(CimbarSpec.version, spec['version']);
      expect(CimbarSpec.gridCells, g['gridCells']);
      expect(CimbarSpec.cellPx, g['cellPx']);
      expect(CimbarSpec.gapPx, g['gapPx']);
      expect(CimbarSpec.pitchPx, g['pitchPx']);
      expect(CimbarSpec.gridPx, g['gridPx']);
      expect(CimbarSpec.quietPx, g['quietPx']);
      expect(CimbarSpec.framePx, g['framePx']);
    });

    test('finder', () {
      final f = spec['finder'] as Map<String, dynamic>;
      expect(CimbarSpec.finderCells, f['cells']);
      expect(CimbarSpec.cornerCells, f['cornerCells']);
      expect(CimbarSpec.finderOuterPx, f['outerPx']);
      expect(CimbarSpec.finderRingInsetPx, f['ringInsetPx']);
      expect(CimbarSpec.finderCorePx, f['corePx']);
      expect(CimbarSpec.finderCoreInsetPx, f['coreInsetPx']);
      expect(CimbarSpec.finderDotPx, f['dotPx']);
      expect(CimbarSpec.finderDotInsetPx, f['dotInsetPx']);
      final centers = f['centers'] as Map<String, dynamic>;
      for (final k in ['tl', 'tr', 'bl', 'br']) {
        expect(CimbarSpec.finderCenters[k], (centers[k] as List).cast<num>().map((n) => n.toDouble()).toList());
      }
      expect(CimbarSpec.finderDotOn, (f['dotOn'] as List).cast<String>());
    });

    test('palette, tiles, bits, rs, header, capacity, gif', () {
      expect(CimbarSpec.palette, (spec['palette'] as List).map((c) => (c as List).cast<int>()).toList());
      expect(CimbarSpec.tiles, (spec['tiles'] as List).cast<String>());
      final bits = spec['bits'] as Map<String, dynamic>;
      expect(CimbarSpec.symbolBits, bits['symbolBits']);
      expect(CimbarSpec.colorBits, bits['colorBits']);
      expect(CimbarSpec.bitsPerCell, CimbarSpec.symbolBits + CimbarSpec.colorBits);
      final rs = spec['rs'] as Map<String, dynamic>;
      expect(CimbarSpec.rsBlockTotal, rs['blockTotal']);
      expect(CimbarSpec.rsEccBytes, rs['eccBytes']);
      expect(CimbarSpec.rsInterleave, rs['interleave']);
      final h = spec['header'] as Map<String, dynamic>;
      expect(CimbarSpec.headerLen, h['lengthBytes']);
      expect(CimbarSpec.version, h['version']);
      final c = spec['capacity'] as Map<String, dynamic>;
      expect(CimbarSpec.usableCells, c['usableCells']);
      expect(CimbarSpec.rawBytesPerFrame, c['rawBytesPerFrame']);
      expect(CimbarSpec.dataBytesPerFrame, c['dataBytesPerFrame']);
      expect(CimbarSpec.fileBytesPerFrame, c['fileBytesPerFrame']);
      final gif = spec['gif'] as Map<String, dynamic>;
      expect(CimbarSpec.defaultDelayMs, gif['defaultDelayMs']);
      expect(CimbarSpec.delayOptionsMs, (gif['delayOptionsMs'] as List).cast<int>());
    });
  });

  group('CimbarSpec geometry', () {
    test('reserved cells are the four 8x8 corners', () {
      expect(CimbarSpec.isReservedCell(0, 0), isTrue);
      expect(CimbarSpec.isReservedCell(7, 7), isTrue);
      expect(CimbarSpec.isReservedCell(56, 0), isTrue);
      expect(CimbarSpec.isReservedCell(0, 63), isTrue);
      expect(CimbarSpec.isReservedCell(63, 63), isTrue);
      expect(CimbarSpec.isReservedCell(8, 0), isFalse);
      expect(CimbarSpec.isReservedCell(7, 8), isFalse);
      expect(CimbarSpec.isReservedCell(32, 32), isFalse);
      expect(CimbarSpec.isReservedCell(0, 32), isFalse);
    });

    test('usable cell positions: 3840, row-major, first (8,0), last (55,63)', () {
      final pos = CimbarSpec.usableCellPositions;
      expect(pos.length, 3840);
      expect(pos.first, const CellPos(8, 0));
      expect(pos.last, const CellPos(55, 63));
      expect(pos[48], const CellPos(8, 1)); // row 0 has 48 usable cells (cols 8..55)
    });

    test('cell origins', () {
      expect(CimbarSpec.cellOriginX(0), 16);
      expect(CimbarSpec.cellOriginX(8), 88);
      expect(CimbarSpec.cellOriginY(63), 583);
    });

    test('derived capacity and RS block sizes', () {
      expect(CimbarSpec.rawBytesPerFrame, CimbarSpec.usableCells * CimbarSpec.bitsPerCell ~/ 8);
      expect(CimbarSpec.rsBlockSizes(), [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 75]);
      final data = CimbarSpec.rsBlockSizes().fold<int>(0, (s, b) => s + b - CimbarSpec.rsEccBytes);
      expect(CimbarSpec.dataBytesPerFrame, data);
      expect(CimbarSpec.fileBytesPerFrame, data - CimbarSpec.headerLen);
    });
  });

  group('Tiles', () {
    test('hex round trip, MSB is top-left', () {
      final t = Tiles.hexToTile('8000000000000001');
      expect(t[0], 1);
      expect(t[63], 1);
      expect(Tiles.popcount(t), 2);
      expect(Tiles.tileToHex(t), '8000000000000001');
    });

    test('16 tiles decoded from the spec, fill 26..38', () {
      expect(Tiles.bits.length, 16);
      for (var s = 0; s < 16; s++) {
        expect(Tiles.tileToHex(Tiles.bits[s]), CimbarSpec.tiles[s]);
        final n = Tiles.popcount(Tiles.bits[s]);
        expect(n >= 26 && n <= 38, isTrue, reason: 'tile $s fill $n');
      }
    });

    test('pairwise hamming >= 24', () {
      for (var a = 0; a < 16; a++) {
        for (var b = a + 1; b < 16; b++) {
          expect(Tiles.hamming(Tiles.bits[a], Tiles.bits[b]) >= 24, isTrue, reason: 'tiles $a,$b');
        }
      }
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd android && flutter test test/core/format/cimbar_spec_test.dart 2>&1 | tail -5`
Expected: compile error, `cimbar_spec.dart` not found.

- [ ] **Step 3: Write cimbar_spec.dart**

`lib/core/format/cimbar_spec.dart`:

```dart
/// CimBar v2 format constants.
///
/// Mirrors `spec/cimbar-v2.json` (the constants file shared with the web app).
/// `test/core/format/cimbar_spec_test.dart` asserts every value against the JSON,
/// so a change on either side fails the suite. Layout rules that are not
/// constants (bit order, cell order, RS partition, interleave) live in the design
/// spec `docs/superpowers/specs/2026-09-17-cimbar-v2-format-design.md` and in
/// `bit_packing.dart` / `rs_framing.dart`.
class CimbarSpec {
  CimbarSpec._();

  static const int version = 2;

  // Grid
  static const int gridCells = 64;
  static const int cellPx = 8;
  static const int gapPx = 1;
  static const int pitchPx = 9;
  static const int gridPx = 576;
  static const int quietPx = 16;
  static const int framePx = 608;

  // Finders
  static const int finderCells = 7;
  static const int cornerCells = 8;
  static const int finderOuterPx = 63;
  static const int finderRingInsetPx = 9;
  static const int finderCorePx = 27;
  static const int finderCoreInsetPx = 18;
  static const int finderDotPx = 9;
  static const int finderDotInsetPx = 27;
  static const Map<String, List<double>> finderCenters = {
    'tl': [3.5, 3.5],
    'tr': [60.5, 3.5],
    'bl': [3.5, 60.5],
    'br': [60.5, 60.5],
  };
  static const List<String> finderDotOn = ['tr', 'bl', 'br'];

  // Colors
  static const List<List<int>> palette = [
    [0, 255, 0],
    [0, 255, 255],
    [255, 255, 0],
    [255, 85, 255],
  ];

  // Tiles (16 x 8x8, row-major, MSB = top-left) — from spec/cimbar-v2.json, seed 1
  static const List<String> tiles = [
    '3c3cf0f0fcfc0303',
    '00000f0ff3f3f3f3',
    'fcfc33330f0fc0c0',
    'cfcf30303f3f0f0f',
    'cfcf03030000fcfc',
    'cccc0f0f03030f0f',
    'c0c0f3f33c3cf0f0',
    '0303c0c0ccccfcfc',
    '3f3fffffc0c00000',
    '3f3fcccc3333c0c0',
    '30303f3fcfcf0303',
    '0000c0c03f3f3f3f',
    '0f0fc3c3cfcf0303',
    '3c3c3030c0c0ffff',
    '3333f3f33030cfcf',
    '03033c3cfcfccfcf',
  ];

  // Bits
  static const int symbolBits = 4;
  static const int colorBits = 2;
  static const int bitsPerCell = symbolBits + colorBits;

  // Reed-Solomon
  static const int rsBlockTotal = 255;
  static const int rsEccBytes = 64;
  static const String rsInterleave = 'stride-skip-short';

  // Header
  static const int headerLen = 8;

  // Capacity
  static const int usableCells = 3840;
  static const int rawBytesPerFrame = 2880;
  static const int dataBytesPerFrame = 2112;
  static const int fileBytesPerFrame = 2104;

  // GIF
  static const int defaultDelayMs = 200;
  static const List<int> delayOptionsMs = [100, 200, 400];

  static bool isReservedCell(int col, int row) {
    final horiz = col < cornerCells || col >= gridCells - cornerCells;
    final vert = row < cornerCells || row >= gridCells - cornerCells;
    return horiz && vert;
  }

  static List<CellPos>? _positions;

  /// Usable cells in row-major order (finder corners skipped). Length 3840.
  static List<CellPos> get usableCellPositions {
    final cached = _positions;
    if (cached != null) return cached;
    final p = <CellPos>[];
    for (var row = 0; row < gridCells; row++) {
      for (var col = 0; col < gridCells; col++) {
        if (!isReservedCell(col, row)) p.add(CellPos(col, row));
      }
    }
    _positions = List.unmodifiable(p);
    return _positions!;
  }

  static int cellOriginX(int col) => quietPx + col * pitchPx;
  static int cellOriginY(int row) => quietPx + row * pitchPx;

  /// RS block sizes for one frame: eleven 255-byte blocks then one 75-byte block.
  static List<int> rsBlockSizes() {
    final sizes = <int>[];
    var total = 0;
    while (total < rawBytesPerFrame) {
      final left = rawBytesPerFrame - total;
      if (left <= rsEccBytes) break;
      final bt = left < rsBlockTotal ? left : rsBlockTotal;
      sizes.add(bt);
      total += bt;
    }
    return sizes;
  }
}

class CellPos {
  final int col;
  final int row;
  const CellPos(this.col, this.row);

  @override
  bool operator ==(Object other) => other is CellPos && other.col == col && other.row == row;

  @override
  int get hashCode => col * 64 + row;

  @override
  String toString() => 'CellPos($col, $row)';
}
```

- [ ] **Step 4: Write tiles.dart**

`lib/core/format/tiles.dart`:

```dart
import 'dart:typed_data';

import 'cimbar_spec.dart';

/// The 16 symbol tiles as 64-entry 0/1 arrays (row-major, index = row*8 + col).
class Tiles {
  Tiles._();

  static final List<Uint8List> bits =
      List.unmodifiable(CimbarSpec.tiles.map(hexToTile));

  static Uint8List hexToTile(String hex) {
    if (hex.length != 16) throw ArgumentError('tile hex must be 16 chars');
    final t = Uint8List(64);
    for (var i = 0; i < 16; i++) {
      final nib = int.parse(hex[i], radix: 16);
      for (var b = 0; b < 4; b++) {
        t[i * 4 + b] = (nib >> (3 - b)) & 1;
      }
    }
    return t;
  }

  static String tileToHex(Uint8List t) {
    final sb = StringBuffer();
    for (var i = 0; i < 16; i++) {
      var nib = 0;
      for (var b = 0; b < 4; b++) {
        nib = (nib << 1) | t[i * 4 + b];
      }
      sb.write(nib.toRadixString(16));
    }
    return sb.toString();
  }

  static int popcount(Uint8List t) {
    var n = 0;
    for (var i = 0; i < 64; i++) {
      n += t[i];
    }
    return n;
  }

  static int hamming(Uint8List a, Uint8List b) {
    var n = 0;
    for (var i = 0; i < 64; i++) {
      n += a[i] ^ b[i];
    }
    return n;
  }
}
```

- [ ] **Step 5: Run tests and analyzer**

Run: `cd android && flutter test test/core/format/cimbar_spec_test.dart 2>&1 | tail -3` → Expected: `All tests passed!` (10 tests).
Run: `cd android && flutter analyze lib/core/format 2>&1 | tail -2` → Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add android/lib/core/format/cimbar_spec.dart android/lib/core/format/tiles.dart android/test/core/format/cimbar_spec_test.dart
git commit -m "Add Dart CimbarSpec constants and Tiles, asserted against spec/cimbar-v2.json

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 2: FrameHeader and BitPacking

**Files:**
- Create: `lib/core/format/frame_header.dart`
- Create: `lib/core/format/bit_packing.dart`
- Test: `test/core/format/frame_header_test.dart`, `test/core/format/bit_packing_test.dart`

**Interfaces:**
- `FrameHeader({required version, required encrypted, required fileId, required seq, required total})`, `Uint8List encode()`, `static HeaderDecode decode(Uint8List bytes)`.
- `HeaderDecode { FrameHeader? header; String reason; bool get valid }` — `reason` is `''` when valid, else one of `short`, `version`, `flags`, `total`, `seq`.
- `BitPacking.packCells(Uint8List raw) → Uint8List(3840)`, `unpackCells(Uint8List cells) → Uint8List(2880)`, `cellValue(sym, color)`, `cellSymbol(v)`, `cellColor(v)`.

- [ ] **Step 1: Write the failing tests**

`test/core/format/frame_header_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/format/frame_header.dart';

void main() {
  test('encode layout', () {
    final h = const FrameHeader(version: 2, encrypted: true, fileId: 0xBEEF, seq: 3, total: 12).encode();
    expect(h, Uint8List.fromList([2, 1, 0xBE, 0xEF, 0, 3, 0, 12]));
  });

  test('decode round trip', () {
    final d = FrameHeader.decode(Uint8List.fromList([2, 1, 0xBE, 0xEF, 0, 3, 0, 12]));
    expect(d.valid, isTrue);
    expect(d.reason, '');
    expect(d.header!.fileId, 0xBEEF);
    expect(d.header!.seq, 3);
    expect(d.header!.total, 12);
    expect(d.header!.encrypted, isTrue);
  });

  test('rejections with JS-compatible reasons', () {
    expect(FrameHeader.decode(Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 1])).reason, 'version');
    expect(FrameHeader.decode(Uint8List.fromList([2, 2, 0, 0, 0, 0, 0, 1])).reason, 'flags');
    expect(FrameHeader.decode(Uint8List.fromList([2, 0, 0, 0, 0, 0, 0, 0])).reason, 'total');
    expect(FrameHeader.decode(Uint8List.fromList([2, 0, 0, 0, 0, 5, 0, 5])).reason, 'seq');
    expect(FrameHeader.decode(Uint8List.fromList([2, 0, 0])).reason, 'short');
    expect(FrameHeader.decode(Uint8List.fromList([2, 0, 0])).valid, isFalse);
  });

  test('decode reads only the first 8 bytes of a longer buffer', () {
    final buf = Uint8List(2112);
    buf.setRange(0, 8, [2, 0, 0x10, 0x01, 0, 0, 0, 1]);
    final d = FrameHeader.decode(buf);
    expect(d.valid, isTrue);
    expect(d.header!.fileId, 0x1001);
  });
}
```

`test/core/format/bit_packing_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/format/bit_packing.dart';

void main() {
  test('cellValue/cellSymbol/cellColor', () {
    expect(BitPacking.cellValue(15, 3), 63);
    expect(BitPacking.cellValue(9, 2), (9 << 2) | 2);
    expect(BitPacking.cellSymbol(BitPacking.cellValue(9, 2)), 9);
    expect(BitPacking.cellColor(BitPacking.cellValue(9, 2)), 2);
  });

  test('packCells/unpackCells round trip, MSB-first', () {
    final raw = Uint8List(2880);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = (i * 37 + 11) & 0xFF;
    }
    final cells = BitPacking.packCells(raw);
    expect(cells.length, 3840);
    expect(cells[0], raw[0] >> 2);
    expect(cells[1], ((raw[0] & 3) << 4) | (raw[1] >> 4));
    for (final v in cells) {
      expect(v >= 0 && v < 64, isTrue);
    }
    final back = BitPacking.unpackCells(cells);
    expect(back, raw);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd android && flutter test test/core/format/frame_header_test.dart test/core/format/bit_packing_test.dart 2>&1 | tail -3` → Expected: compile errors (files missing).

- [ ] **Step 3: Write frame_header.dart**

```dart
import 'dart:typed_data';

import 'cimbar_spec.dart';

/// The 8-byte frame header at the start of every frame's RS-protected data.
/// `[ver 0x02][flags bit0=encrypted][fileId u16 BE][seq u16 BE][total u16 BE]`
class FrameHeader {
  final int version;
  final bool encrypted;
  final int fileId;
  final int seq;
  final int total;

  const FrameHeader({
    required this.version,
    required this.encrypted,
    required this.fileId,
    required this.seq,
    required this.total,
  });

  Uint8List encode() {
    final b = Uint8List(CimbarSpec.headerLen);
    b[0] = version;
    b[1] = encrypted ? 1 : 0;
    b[2] = (fileId >> 8) & 0xFF;
    b[3] = fileId & 0xFF;
    b[4] = (seq >> 8) & 0xFF;
    b[5] = seq & 0xFF;
    b[6] = (total >> 8) & 0xFF;
    b[7] = total & 0xFF;
    return b;
  }

  /// Decode and validate. Reasons match web-app/format.js decodeHeader:
  /// 'short', 'version', 'flags', 'total', 'seq'; '' when valid.
  static HeaderDecode decode(Uint8List bytes) {
    if (bytes.length < CimbarSpec.headerLen) return const HeaderDecode(null, 'short');
    final version = bytes[0];
    final flags = bytes[1];
    final h = FrameHeader(
      version: version,
      encrypted: (flags & 1) == 1,
      fileId: (bytes[2] << 8) | bytes[3],
      seq: (bytes[4] << 8) | bytes[5],
      total: (bytes[6] << 8) | bytes[7],
    );
    if (version != CimbarSpec.version) return HeaderDecode(h, 'version');
    if ((flags & 0xFE) != 0) return HeaderDecode(h, 'flags');
    if (h.total < 1) return HeaderDecode(h, 'total');
    if (h.seq >= h.total) return HeaderDecode(h, 'seq');
    return HeaderDecode(h, '');
  }

  @override
  String toString() =>
      'FrameHeader(v$version enc=$encrypted fileId=0x${fileId.toRadixString(16)} seq=$seq total=$total)';
}

class HeaderDecode {
  final FrameHeader? header;
  final String reason;
  const HeaderDecode(this.header, this.reason);
  bool get valid => reason.isEmpty;
}
```

- [ ] **Step 4: Write bit_packing.dart**

```dart
import 'dart:typed_data';

import 'cimbar_spec.dart';

/// 6-bit cell values <-> the frame's raw byte stream (MSB-first).
/// Cell value = (symbol << 2) | color.
class BitPacking {
  BitPacking._();

  static int cellValue(int sym, int color) =>
      ((sym & 0xF) << CimbarSpec.colorBits) | (color & 0x3);
  static int cellSymbol(int v) => (v >> CimbarSpec.colorBits) & 0xF;
  static int cellColor(int v) => v & 0x3;

  /// raw: up to 2880 bytes (missing bytes read as 0). Returns 3840 cell values.
  static Uint8List packCells(Uint8List raw) {
    final n = CimbarSpec.usableCells;
    final out = Uint8List(n);
    var bitPos = 0;
    for (var k = 0; k < n; k++) {
      var v = 0;
      for (var b = 0; b < CimbarSpec.bitsPerCell; b++) {
        final byte = bitPos >> 3;
        final bit = 7 - (bitPos & 7);
        final d = byte < raw.length ? (raw[byte] >> bit) & 1 : 0;
        v = (v << 1) | d;
        bitPos++;
      }
      out[k] = v;
    }
    return out;
  }

  /// cells: 3840 values 0..63. Returns 2880 raw bytes.
  static Uint8List unpackCells(Uint8List cells) {
    final raw = Uint8List(CimbarSpec.rawBytesPerFrame);
    var bitPos = 0;
    for (var k = 0; k < cells.length; k++) {
      for (var b = CimbarSpec.bitsPerCell - 1; b >= 0; b--) {
        if ((cells[k] >> b) & 1 == 1) {
          raw[bitPos >> 3] |= 1 << (7 - (bitPos & 7));
        }
        bitPos++;
      }
    }
    return raw;
  }
}
```

- [ ] **Step 5: Run tests and analyzer**

Run: `cd android && flutter test test/core/format/ 2>&1 | tail -3` → Expected: `All tests passed!` (16 tests).
Run: `cd android && flutter analyze lib/core/format 2>&1 | tail -2` → `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add android/lib/core/format/frame_header.dart android/lib/core/format/bit_packing.dart android/test/core/format/frame_header_test.dart android/test/core/format/bit_packing_test.dart
git commit -m "Add Dart FrameHeader codec and 6-bit cell BitPacking

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 3: RsFraming, FileContainer, GoldenSidecar — cross-checked against the goldens

**Files:**
- Create: `lib/core/format/rs_framing.dart`
- Create: `lib/core/format/file_container.dart`
- Create: `lib/core/decode/golden_sidecar.dart`
- Test: `test/core/format/rs_framing_test.dart`, `test/core/format/file_container_test.dart`

**Interfaces:**
- `RsFraming.encodeFrame(Uint8List data, ReedSolomon rs) → Uint8List(2880)`; `RsFraming.decodeFrame(Uint8List raw, ReedSolomon rs) → RsFrameResult { Uint8List data (2112); int blocksOk; int blocksFailed; }`.
- `FileContainer.stripLengthPrefix(Uint8List) → Uint8List` (throws `FormatException` on invalid length); `FileContainer.isEncrypted(Uint8List payload) → bool` (CB 42 magic); `FileContainer.parsePayload(Uint8List) → ParsedFile { String fileName; Uint8List fileBytes; }` (throws `FormatException`).
- `GoldenSidecar.load(String jsonPath) → GoldenSidecar { name, fileName, Uint8List fileBytes, String? passphrase, int fileId, int total, int delayMs, int framedDataLength, List<GoldenFrame> frames }`; `GoldenFrame { int seq; FrameHeader header; Uint8List data; Uint8List raw; Uint8List cells; }`. Also `static Uint8List hexToBytes(String)`.

- [ ] **Step 1: Write the failing tests**

`test/core/format/rs_framing_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/rs_framing.dart';
import 'package:cimbar_scanner/core/services/reed_solomon.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final rs = ReedSolomon(CimbarSpec.rsEccBytes);
  final golden = GoldenSidecar.load(repoPath('test-data/goldens/lorem_12k.json'));

  test('encodeFrame reproduces the golden raw bytes (interleave cross-check with JS)', () {
    for (final f in golden.frames) {
      final raw = RsFraming.encodeFrame(f.data, rs);
      expect(raw, f.raw, reason: 'frame ${f.seq}');
    }
  });

  test('decodeFrame recovers golden data with 12 ok blocks', () {
    for (final f in golden.frames) {
      final r = RsFraming.decodeFrame(f.raw, rs);
      expect(r.blocksOk, 12);
      expect(r.blocksFailed, 0);
      expect(r.data, f.data, reason: 'frame ${f.seq}');
    }
  });

  test('corrects 30 spread errors', () {
    final f = golden.frames[0];
    final bad = Uint8List.fromList(f.raw);
    for (var i = 0; i < 30; i++) {
      bad[i * 90] ^= 0xFF;
    }
    final r = RsFraming.decodeFrame(bad, rs);
    expect(r.blocksFailed, 0);
    expect(r.data, f.data);
  });

  test('reports failed blocks and zero-fills them', () {
    final f = golden.frames[0];
    final bad = Uint8List.fromList(f.raw);
    for (var i = 0; i < bad.length; i++) {
      bad[i] ^= ((i * 37 + 11) & 0xFE) | 1;
    }
    final r = RsFraming.decodeFrame(bad, rs);
    expect(r.blocksFailed, 12);
    expect(r.data.length, CimbarSpec.dataBytesPerFrame);
  });

  test('tail block positions follow stride-skip-short', () {
    // Byte 0 of block 11 (the 75-byte block) sits at position 11; byte 74 at 74*12+11;
    // there is no byte 75 of block 11, so position 900 is byte 75 of block 0.
    final f = golden.frames[0];
    final sizes = CimbarSpec.rsBlockSizes();
    final blocks = <Uint8List>[];
    var off = 0;
    for (final s in sizes) {
      final bd = s - CimbarSpec.rsEccBytes;
      blocks.add(rs.encode(f.data.sublist(off, off + bd)));
      off += bd;
    }
    expect(f.raw[11], blocks[11][0]);
    expect(f.raw[74 * 12 + 11], blocks[11][74]);
    expect(f.raw[900], blocks[0][75]);
    expect(f.raw[911], blocks[0][76]);
  });
}
```

`test/core/format/file_container_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/format/file_container.dart';

void main() {
  Uint8List payload(String name, List<int> bytes) {
    final n = utf8.encode(name);
    final out = Uint8List(4 + n.length + bytes.length);
    out[3] = n.length;
    out.setRange(4, 4 + n.length, n);
    out.setRange(4 + n.length, out.length, bytes);
    return out;
  }

  test('parsePayload', () {
    final p = FileContainer.parsePayload(payload('hello.txt', [1, 2, 3]));
    expect(p.fileName, 'hello.txt');
    expect(p.fileBytes, Uint8List.fromList([1, 2, 3]));
  });

  test('parsePayload rejects bad name length', () {
    expect(() => FileContainer.parsePayload(Uint8List.fromList([0, 0, 9, 9, 1])), throwsFormatException);
  });

  test('stripLengthPrefix strips zero padding and validates', () {
    final body = payload('a.bin', [7, 8]);
    final framed = Uint8List(4 + body.length + 50);
    framed[3] = body.length;
    framed.setRange(4, 4 + body.length, body);
    expect(FileContainer.stripLengthPrefix(framed), body);
    expect(() => FileContainer.stripLengthPrefix(Uint8List.fromList([0, 0, 0, 99, 1])), throwsFormatException);
    expect(() => FileContainer.stripLengthPrefix(Uint8List.fromList([0, 0, 0, 0, 1])), throwsFormatException);
  });

  test('isEncrypted checks the CB 42 magic', () {
    expect(FileContainer.isEncrypted(Uint8List.fromList([0xCB, 0x42, 1, 0, 9])), isTrue);
    expect(FileContainer.isEncrypted(Uint8List.fromList([0, 0, 0, 5])), isFalse);
    expect(FileContainer.isEncrypted(Uint8List(1)), isFalse);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd android && flutter test test/core/format/rs_framing_test.dart test/core/format/file_container_test.dart 2>&1 | tail -3` → compile errors.

- [ ] **Step 3: Write rs_framing.dart**

```dart
import 'dart:typed_data';

import '../services/reed_solomon.dart';
import 'cimbar_spec.dart';

class RsFrameResult {
  final Uint8List data;
  final int blocksOk;
  final int blocksFailed;
  const RsFrameResult(this.data, this.blocksOk, this.blocksFailed);
}

/// RS block partition and byte-stride interleaving for one frame.
///
/// Interleave rule (spec §4.3, "stride-skip-short"): for j from 0 to the
/// largest block size - 1, for i from 0 to N - 1, append byte j of block i if
/// block i has a byte j. With sizes [255 x 11, 75] the position is j*12+i for
/// j < 75 and 900 + (j-75)*11 + i afterwards.
class RsFraming {
  RsFraming._();

  static Uint8List encodeFrame(Uint8List data, ReedSolomon rs) {
    final sizes = CimbarSpec.rsBlockSizes();
    final blocks = <Uint8List>[];
    var off = 0;
    for (final bt in sizes) {
      final bd = bt - CimbarSpec.rsEccBytes;
      final chunk = Uint8List(bd);
      final take = (data.length - off).clamp(0, bd);
      if (take > 0) chunk.setRange(0, take, data, off);
      off += take;
      blocks.add(rs.encode(chunk));
    }
    return _interleave(blocks, CimbarSpec.rawBytesPerFrame);
  }

  static Uint8List _interleave(List<Uint8List> blocks, int rawLen) {
    final out = Uint8List(rawLen);
    var maxLen = 0;
    for (final b in blocks) {
      if (b.length > maxLen) maxLen = b.length;
    }
    var pos = 0;
    for (var j = 0; j < maxLen; j++) {
      for (var i = 0; i < blocks.length; i++) {
        if (j < blocks[i].length) out[pos++] = blocks[i][j];
      }
    }
    return out;
  }

  static RsFrameResult decodeFrame(Uint8List raw, ReedSolomon rs) {
    final sizes = CimbarSpec.rsBlockSizes();
    final n = sizes.length;
    final blocks = [for (final s in sizes) Uint8List(s)];
    var maxLen = 0;
    for (final s in sizes) {
      if (s > maxLen) maxLen = s;
    }
    var pos = 0;
    for (var j = 0; j < maxLen; j++) {
      for (var i = 0; i < n; i++) {
        if (j < sizes[i]) {
          blocks[i][j] = pos < raw.length ? raw[pos] : 0;
          pos++;
        }
      }
    }
    final data = Uint8List(CimbarSpec.dataBytesPerFrame);
    var off = 0;
    var ok = 0;
    var failed = 0;
    for (var i = 0; i < n; i++) {
      final bd = sizes[i] - CimbarSpec.rsEccBytes;
      try {
        final dec = rs.decode(blocks[i]);
        data.setRange(off, off + bd, dec);
        ok++;
      } catch (_) {
        failed++;
      }
      off += bd;
    }
    return RsFrameResult(data, ok, failed);
  }
}
```

- [ ] **Step 4: Write file_container.dart**

```dart
import 'dart:convert';
import 'dart:typed_data';

class ParsedFile {
  final String fileName;
  final Uint8List fileBytes;
  const ParsedFile(this.fileName, this.fileBytes);
}

/// The file container shared with the web app (unchanged from v1):
/// framedData = [u32 len][framedPayload]; payload = [u32 nameLen][name][file];
/// framedPayload is the payload or its AES-GCM wire blob starting with CB 42.
class FileContainer {
  FileContainer._();

  static const int maxNameLen = 512;

  static int _u32(Uint8List b, int off) =>
      (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

  static Uint8List stripLengthPrefix(Uint8List framed) {
    if (framed.length < 4) throw const FormatException('missing length prefix');
    final len = _u32(framed, 0);
    if (len < 1 || len > framed.length - 4) {
      throw FormatException('payload length $len is invalid');
    }
    return framed.sublist(4, 4 + len);
  }

  static bool isEncrypted(Uint8List payload) =>
      payload.length >= 2 && payload[0] == 0xCB && payload[1] == 0x42;

  static ParsedFile parsePayload(Uint8List bytes) {
    if (bytes.length < 4) throw const FormatException('payload too short');
    final nameLen = _u32(bytes, 0);
    if (nameLen > maxNameLen || 4 + nameLen > bytes.length) {
      throw FormatException('filename length $nameLen is invalid');
    }
    final name = utf8.decode(bytes.sublist(4, 4 + nameLen));
    return ParsedFile(name, bytes.sublist(4 + nameLen));
  }
}
```

- [ ] **Step 5: Write golden_sidecar.dart**

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../format/frame_header.dart';

/// One frame of ground truth from test-data/goldens/<name>.json.
class GoldenFrame {
  final int seq;
  final FrameHeader header;
  final Uint8List data; // 2112 protected bytes incl. header, pre-RS
  final Uint8List raw; // 2880 bytes after RS encode + interleave
  final Uint8List cells; // 3840 values (symbol << 2) | color
  const GoldenFrame(this.seq, this.header, this.data, this.raw, this.cells);
}

/// Loader for the golden sidecars (schema: test-data/goldens/README.md).
class GoldenSidecar {
  final String name;
  final String fileName;
  final Uint8List fileBytes;
  final String? passphrase;
  final int fileId;
  final int total;
  final int delayMs;
  final int framedDataLength;
  final List<GoldenFrame> frames;

  const GoldenSidecar({
    required this.name,
    required this.fileName,
    required this.fileBytes,
    required this.passphrase,
    required this.fileId,
    required this.total,
    required this.delayMs,
    required this.framedDataLength,
    required this.frames,
  });

  static GoldenSidecar load(String jsonPath) {
    final m = jsonDecode(File(jsonPath).readAsStringSync()) as Map<String, dynamic>;
    final frames = (m['frames'] as List).map((e) {
      final f = e as Map<String, dynamic>;
      final h = f['header'] as Map<String, dynamic>;
      return GoldenFrame(
        f['seq'] as int,
        FrameHeader(
          version: h['version'] as int,
          encrypted: h['encrypted'] as bool,
          fileId: h['fileId'] as int,
          seq: h['seq'] as int,
          total: h['total'] as int,
        ),
        hexToBytes(f['dataHex'] as String),
        hexToBytes(f['rawHex'] as String),
        Uint8List.fromList((f['cells'] as List).cast<int>()),
      );
    }).toList(growable: false);
    return GoldenSidecar(
      name: m['name'] as String,
      fileName: m['fileName'] as String,
      fileBytes: base64Decode(m['fileBytesBase64'] as String),
      passphrase: m['passphrase'] as String?,
      fileId: m['fileId'] as int,
      total: m['total'] as int,
      delayMs: m['delayMs'] as int,
      framedDataLength: m['framedDataLength'] as int,
      frames: frames,
    );
  }

  /// Path of the sibling .gif for this sidecar.
  static String gifPathFor(String jsonPath) => jsonPath.replaceAll(RegExp(r'\.json$'), '.gif');

  static Uint8List hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
```

- [ ] **Step 6: Run tests and analyzer**

Run: `cd android && flutter test test/core/format/ 2>&1 | tail -3` → `All tests passed!` (25 tests).
Run: `cd android && flutter analyze lib/core 2>&1 | tail -2` → `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add android/lib/core/format/rs_framing.dart android/lib/core/format/file_container.dart android/lib/core/decode/golden_sidecar.dart android/test/core/format/rs_framing_test.dart android/test/core/format/file_container_test.dart
git commit -m "Add RsFraming (stride-skip-short), FileContainer and GoldenSidecar loader, cross-checked against goldens

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 4: RgbBuffer, GridModel, CellSampler, CellClassifier

**Files:**
- Create: `lib/core/decode/rgb_buffer.dart`, `lib/core/decode/grid_model.dart`, `lib/core/decode/cell_sampler.dart`, `lib/core/decode/cell_classifier.dart`
- Test: `test/core/decode/cell_sampler_test.dart`, `test/core/decode/cell_classifier_test.dart`

**Interfaces:**
- `RgbBuffer { int width, height; Uint8List rgb; RgbBuffer(width, height, rgb); factory RgbBuffer.fromImage(img.Image); int r(x,y), g(x,y), b(x,y); void bilinear(double x, double y, Float32List out, int outOff) }` where `(x, y)` are continuous source coordinates with pixel `k` covering `[k, k+1)` and its center at `k + 0.5`; out-of-range clamps to the edge.
- `abstract class GridModel { const GridModel(); (double, double) toSource(double cx, double cy); }`, `class ExactGridModel extends GridModel`.
- `CellPatch { Float32List luma (64); Float32List rgb (192); }`
- `CellSampler(RgbBuffer image, GridModel grid)`; `void sample(int col, int row, CellPatch out, {double dx = 0, double dy = 0})`.
- `CellClassification { int symbol; int hamming; int color; double colorMargin; }`
- `CellClassifier()`; `CellClassification classify(CellPatch p, {List<double>? whitePoint})` (white point scales channels to 255 before chroma; null = no white balance).

- [ ] **Step 1: Write the failing tests**

`test/core/decode/cell_sampler_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/decode/cell_sampler.dart';
import 'package:cimbar_scanner/core/decode/grid_model.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/tiles.dart';

void main() {
  test('RgbBuffer.fromImage copies pixels and clamps at edges', () {
    final im = img.Image(width: 4, height: 3);
    im.setPixelRgb(1, 2, 10, 20, 30);
    final buf = RgbBuffer.fromImage(im);
    expect(buf.width, 4);
    expect(buf.height, 3);
    expect([buf.r(1, 2), buf.g(1, 2), buf.b(1, 2)], [10, 20, 30]);
    expect(buf.r(0, 0), 0);
  });

  test('bilinear at a pixel center is exact; halfway blends', () {
    final im = img.Image(width: 2, height: 1);
    im.setPixelRgb(0, 0, 0, 0, 0);
    im.setPixelRgb(1, 0, 200, 100, 50);
    final buf = RgbBuffer.fromImage(im);
    final out = Float32List(3);
    buf.bilinear(1.5, 0.5, out, 0);
    expect(out, [200, 100, 50]);
    buf.bilinear(1.0, 0.5, out, 0);
    expect(out[0], closeTo(100, 0.01));
    expect(out[2], closeTo(25, 0.01));
  });

  test('ExactGridModel maps cell units to quiet + pitch * units', () {
    const g = ExactGridModel();
    expect(g.toSource(0, 0), (16.0, 16.0));
    expect(g.toSource(3.5, 3.5), (47.5, 47.5));
    expect(g.toSource(8, 1), (88.0, 25.0));
  });

  test('CellSampler reads an exact tile rendered at cell (8,0)', () {
    final im = img.Image(width: CimbarSpec.framePx, height: CimbarSpec.framePx);
    final t = Tiles.bits[5];
    final ox = CimbarSpec.cellOriginX(8), oy = CimbarSpec.cellOriginY(0);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        if (t[y * 8 + x] == 1) im.setPixelRgb(ox + x, oy + y, 255, 255, 0);
      }
    }
    final sampler = CellSampler(RgbBuffer.fromImage(im), const ExactGridModel());
    final patch = CellPatch();
    sampler.sample(8, 0, patch);
    for (var p = 0; p < 64; p++) {
      final lit = t[p] == 1;
      expect(patch.rgb[p * 3], lit ? 255 : 0, reason: 'r at $p');
      expect(patch.rgb[p * 3 + 1], lit ? 255 : 0, reason: 'g at $p');
      expect(patch.rgb[p * 3 + 2], 0, reason: 'b at $p');
      expect(patch.luma[p] > 100, lit, reason: 'luma at $p');
    }
  });
}
```

`test/core/decode/cell_classifier_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/cell_classifier.dart';
import 'package:cimbar_scanner/core/decode/cell_sampler.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/tiles.dart';

CellPatch patchFor(int sym, List<int> color, {double scale = 1.0}) {
  final p = CellPatch();
  final t = Tiles.bits[sym];
  for (var i = 0; i < 64; i++) {
    final lit = t[i] == 1;
    final r = lit ? color[0] * scale : 0.0;
    final g = lit ? color[1] * scale : 0.0;
    final b = lit ? color[2] * scale : 0.0;
    p.rgb[i * 3] = r;
    p.rgb[i * 3 + 1] = g;
    p.rgb[i * 3 + 2] = b;
    p.luma[i] = 0.299 * r + 0.587 * g + 0.114 * b;
  }
  return p;
}

void main() {
  final c = CellClassifier();

  test('all 64 symbol/color combinations classify exactly', () {
    for (var s = 0; s < 16; s++) {
      for (var k = 0; k < 4; k++) {
        final r = c.classify(patchFor(s, CimbarSpec.palette[k]));
        expect(r.symbol, s, reason: 'sym $s color $k');
        expect(r.color, k, reason: 'sym $s color $k');
        expect(r.hamming, 0);
        expect(r.colorMargin > 0.3, isTrue);
      }
    }
  });

  test('dimmed cells still classify (chroma is brightness-normalized)', () {
    for (var k = 0; k < 4; k++) {
      final r = c.classify(patchFor(3, CimbarSpec.palette[k], scale: 0.4));
      expect(r.color, k);
      expect(r.symbol, 3);
    }
  });

  test('white point rescales channels before chroma', () {
    // A strong blue deficit (blue x0.3) turns cyan (0,255,255) into (0,255,77),
    // whose chroma is closer to green than to cyan without white balance.
    final p = patchFor(7, [0, 255, 77]);
    expect(c.classify(p).color, 0, reason: 'without WB the cast reads as green');
    final r = c.classify(p, whitePoint: [255, 255, 77]);
    expect(r.color, 1, reason: 'with WB it reads as cyan');
    expect(r.symbol, 7);
  });

  test('a flipped-bit patch still finds the nearest tile with hamming > 0', () {
    final p = patchFor(9, CimbarSpec.palette[2]);
    p.luma[0] = p.luma[0] > 100 ? 0 : 255;
    p.luma[1] = p.luma[1] > 100 ? 0 : 255;
    final r = c.classify(p);
    expect(r.symbol, 9);
    expect(r.hamming, 2);
  });
}
```

- [ ] **Step 2: Run to verify failure** — `cd android && flutter test test/core/decode/ 2>&1 | tail -3` → compile errors.

- [ ] **Step 3: Write rgb_buffer.dart**

```dart
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Flat 8-bit RGB buffer with bilinear sampling.
/// Continuous coordinates: pixel k covers [k, k+1), center at k + 0.5.
class RgbBuffer {
  final int width;
  final int height;
  final Uint8List rgb; // width * height * 3

  RgbBuffer(this.width, this.height, this.rgb) {
    if (rgb.length != width * height * 3) {
      throw ArgumentError('rgb length ${rgb.length} != $width*$height*3');
    }
  }

  factory RgbBuffer.fromImage(img.Image image) {
    final w = image.width, h = image.height;
    final out = Uint8List(w * h * 3);
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        out[i++] = p.r.toInt();
        out[i++] = p.g.toInt();
        out[i++] = p.b.toInt();
      }
    }
    return RgbBuffer(w, h, out);
  }

  int r(int x, int y) => rgb[(y * width + x) * 3];
  int g(int x, int y) => rgb[(y * width + x) * 3 + 1];
  int b(int x, int y) => rgb[(y * width + x) * 3 + 2];

  /// Bilinear sample at continuous (x, y); writes r,g,b to out[outOff..outOff+2].
  void bilinear(double x, double y, Float32List out, int outOff) {
    final fx = x - 0.5, fy = y - 0.5;
    var x0 = fx.floor(), y0 = fy.floor();
    final tx = fx - x0, ty = fy - y0;
    var x1 = x0 + 1, y1 = y0 + 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 < 0) x1 = 0;
    if (y1 < 0) y1 = 0;
    if (x0 >= width) x0 = width - 1;
    if (x1 >= width) x1 = width - 1;
    if (y0 >= height) y0 = height - 1;
    if (y1 >= height) y1 = height - 1;
    final i00 = (y0 * width + x0) * 3, i10 = (y0 * width + x1) * 3;
    final i01 = (y1 * width + x0) * 3, i11 = (y1 * width + x1) * 3;
    final w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty;
    for (var c = 0; c < 3; c++) {
      out[outOff + c] = rgb[i00 + c] * w00 + rgb[i10 + c] * w10 + rgb[i01 + c] * w01 + rgb[i11 + c] * w11;
    }
  }
}
```

- [ ] **Step 4: Write grid_model.dart**

```dart
import '../format/cimbar_spec.dart';

/// Maps cell-unit coordinates to source-image pixel coordinates.
/// One cell unit is one pitch (9 px); the grid origin is cell (0, 0)'s
/// top-left corner; finder centers are at (3.5, 3.5), (60.5, 3.5), ...
abstract class GridModel {
  const GridModel();
  (double, double) toSource(double cx, double cy);
}

/// Identity model for frames whose pixels are at exact spec positions (GIF path).
class ExactGridModel extends GridModel {
  const ExactGridModel();

  @override
  (double, double) toSource(double cx, double cy) => (
        CimbarSpec.quietPx + cx * CimbarSpec.pitchPx,
        CimbarSpec.quietPx + cy * CimbarSpec.pitchPx,
      );
}
```

- [ ] **Step 5: Write cell_sampler.dart**

```dart
import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import 'grid_model.dart';
import 'rgb_buffer.dart';

/// One sampled 8x8 tile: luma[64] and rgb[192], row-major.
class CellPatch {
  final Float32List luma = Float32List(64);
  final Float32List rgb = Float32List(192);
}

/// Samples the 64 tile pixels of a cell through a GridModel, bilinear,
/// at the source resolution. dx/dy shift the sample position in source pixels.
class CellSampler {
  final RgbBuffer image;
  final GridModel grid;
  CellSampler(this.image, this.grid);

  void sample(int col, int row, CellPatch out, {double dx = 0, double dy = 0}) {
    const pitch = CimbarSpec.pitchPx;
    for (var j = 0; j < 8; j++) {
      for (var i = 0; i < 8; i++) {
        final (sx, sy) = grid.toSource(col + (i + 0.5) / pitch, row + (j + 0.5) / pitch);
        final p = j * 8 + i;
        image.bilinear(sx + dx, sy + dy, out.rgb, p * 3);
        out.luma[p] = 0.299 * out.rgb[p * 3] + 0.587 * out.rgb[p * 3 + 1] + 0.114 * out.rgb[p * 3 + 2];
      }
    }
  }
}
```

- [ ] **Step 6: Write cell_classifier.dart**

```dart
import 'dart:math' as math;

import '../format/cimbar_spec.dart';
import '../format/tiles.dart';
import 'cell_sampler.dart';

class CellClassification {
  final int symbol;
  final int hamming;
  final int color;
  final double colorMargin;
  const CellClassification(this.symbol, this.hamming, this.color, this.colorMargin);
}

/// Symbol by average hash + Hamming distance to the 16 tiles; color by
/// brightness-normalized chroma over the winning tile's lit pixels (spec §6.6–6.7).
class CellClassifier {
  late final List<List<double>> _paletteChroma;

  CellClassifier() {
    _paletteChroma = [
      for (final c in CimbarSpec.palette) _chroma(c[0].toDouble(), c[1].toDouble(), c[2].toDouble()),
    ];
  }

  static List<double> _chroma(double r, double g, double b) {
    final m = math.max(1.0, math.max(r, math.max(g, b)));
    return [(r - g) / m, (g - b) / m, (b - r) / m];
  }

  CellClassification classify(CellPatch p, {List<double>? whitePoint}) {
    var mean = 0.0;
    for (var i = 0; i < 64; i++) {
      mean += p.luma[i];
    }
    mean /= 64;

    var bestSym = 0, bestDist = 65;
    for (var s = 0; s < 16; s++) {
      final t = Tiles.bits[s];
      var d = 0;
      for (var i = 0; i < 64; i++) {
        d += ((p.luma[i] > mean) ? 1 : 0) ^ t[i];
      }
      if (d < bestDist) {
        bestDist = d;
        bestSym = s;
      }
    }

    final t = Tiles.bits[bestSym];
    var r = 0.0, g = 0.0, b = 0.0, n = 0;
    for (var i = 0; i < 64; i++) {
      if (t[i] == 1) {
        r += p.rgb[i * 3];
        g += p.rgb[i * 3 + 1];
        b += p.rgb[i * 3 + 2];
        n++;
      }
    }
    if (n > 0) {
      r /= n;
      g /= n;
      b /= n;
    }
    if (whitePoint != null) {
      r = r * 255 / math.max(1.0, whitePoint[0]);
      g = g * 255 / math.max(1.0, whitePoint[1]);
      b = b * 255 / math.max(1.0, whitePoint[2]);
    }
    final ch = _chroma(r, g, b);
    var bestC = 0;
    var bestD = double.infinity, secondD = double.infinity;
    for (var c = 0; c < _paletteChroma.length; c++) {
      final pc = _paletteChroma[c];
      final dd = (ch[0] - pc[0]) * (ch[0] - pc[0]) + (ch[1] - pc[1]) * (ch[1] - pc[1]) + (ch[2] - pc[2]) * (ch[2] - pc[2]);
      if (dd < bestD) {
        secondD = bestD;
        bestD = dd;
        bestC = c;
      } else if (dd < secondD) {
        secondD = dd;
      }
    }
    return CellClassification(bestSym, bestDist, bestC, math.sqrt(secondD) - math.sqrt(bestD));
  }
}
```

- [ ] **Step 7: Run tests and analyzer**

Run: `cd android && flutter test test/core/decode/ 2>&1 | tail -3` → `All tests passed!` (8 tests).
Run: `cd android && flutter analyze lib/core 2>&1 | tail -2` → `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add android/lib/core/decode/rgb_buffer.dart android/lib/core/decode/grid_model.dart android/lib/core/decode/cell_sampler.dart android/lib/core/decode/cell_classifier.dart android/test/core/decode/cell_sampler_test.dart android/test/core/decode/cell_classifier_test.dart
git commit -m "Add RgbBuffer, GridModel, CellSampler and CellClassifier for v2 decode

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 5: Diagnostics, FrameDecoder (exact path), golden decode test

**Files:**
- Create: `lib/core/decode/diagnostics.dart`, `lib/core/decode/frame_decoder.dart`
- Test: `test/core/decode/frame_decoder_golden_test.dart`

**Interfaces:**
- `enum DecodeStatus { ok, notLocated, unsupportedGrid, rsFailed, badHeader }`
- `class Diagnostics { int hammingMax; double hammingMean; double colorMarginMin; List<int> hammingHist (4 bins: <8, <16, <24, ≥24); int rsBlocks, rsOk, rsFailed; String headerReason; String note; int sampleMs, rsMs; Map<String, String> toMap(); }`
- `class FrameResult { DecodeStatus status; Uint8List? cells; Uint8List? raw; Uint8List? data; FrameHeader? header; Diagnostics diag; bool get isOk }`
- `class FrameDecoder { FrameDecoder(); FrameResult decode(RgbBuffer image, {GridModel? grid}); FrameResult decodeExact(RgbBuffer image); }`
  - `decode` with `grid == null` returns `notLocated` with `note = 'locator not implemented (Plan 3)'` — Plan 3 replaces that branch with the finder locator.
  - `decodeExact` returns `unsupportedGrid` with a note naming the size (`expected 608x608, got WxH (v1 GIF?)`) when the image is not exactly 608×608, else `decode(image, grid: const ExactGridModel())`.
  - Status rules: RS any failed → `rsFailed` (cells/raw/data still attached); header invalid → `badHeader` with `diag.headerReason`; else `ok`.

- [ ] **Step 1: Write the failing test**

`test/core/decode/frame_decoder_golden_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/services/gif_parser.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final dir = Directory(repoPath('test-data/goldens'));
  final sidecars = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map((f) => f.path)
      .toList()
    ..sort();

  test('at least five goldens are present', () {
    expect(sidecars.length, greaterThanOrEqualTo(5));
  });

  for (final jsonPath in sidecars) {
    test('golden ${jsonPath.split('/').last}: exact decode matches sidecar', () {
      final golden = GoldenSidecar.load(jsonPath);
      final frames = GifParser.parseFrames(File(GoldenSidecar.gifPathFor(jsonPath)).readAsBytesSync());
      expect(frames.length, golden.total);
      final decoder = FrameDecoder();
      for (var i = 0; i < frames.length; i++) {
        final r = decoder.decodeExact(RgbBuffer.fromImage(frames[i]));
        expect(r.status, DecodeStatus.ok, reason: 'frame $i: ${r.diag.toMap()}');
        expect(r.diag.hammingMax, 0, reason: 'frame $i');
        expect(r.cells, golden.frames[i].cells, reason: 'frame $i cells');
        expect(r.raw, golden.frames[i].raw, reason: 'frame $i raw');
        expect(r.data, golden.frames[i].data, reason: 'frame $i data');
        expect(r.header!.seq, golden.frames[i].header.seq);
        expect(r.header!.fileId, golden.fileId);
        expect(r.header!.total, golden.total);
        expect(r.header!.encrypted, golden.passphrase != null);
        expect(r.diag.rsOk, 12);
      }
    });
  }

  test('decodeExact rejects non-608 images as unsupportedGrid (v1 GIF)', () {
    final v1 = GifParser.parseFrames(File('test/fixtures/test_hello.gif').readAsBytesSync());
    final r = FrameDecoder().decodeExact(RgbBuffer.fromImage(v1.first));
    expect(r.status, DecodeStatus.unsupportedGrid);
    expect(r.diag.note, contains('608'));
  });

  test('decode without a grid is notLocated until Plan 3', () {
    final r = FrameDecoder().decode(RgbBuffer(4, 4, Uint8List(48)));
    expect(r.status, DecodeStatus.notLocated);
  });

  test('a frame with corrupted cells reports rsFailed with counts', () {
    final jsonPath = repoPath('test-data/goldens/hello.json');
    final frame = GifParser.parseFrames(File(GoldenSidecar.gifPathFor(jsonPath)).readAsBytesSync()).first;
    // Blank the tiles of the first 16 usable rows (768 cells = 576 raw bytes,
    // i.e. 48 wrong bytes in every one of the 12 interleaved blocks, beyond the
    // 32-byte correction limit). Mutate the RGB buffer, not the paletted GIF frame.
    final buf = RgbBuffer.fromImage(frame);
    for (var row = 0; row < 16; row++) {
      for (var col = 8; col < 56; col++) {
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 8; x++) {
            final px = 16 + col * 9 + x, py = 16 + row * 9 + y;
            final i = (py * buf.width + px) * 3;
            buf.rgb[i] = 0;
            buf.rgb[i + 1] = 0;
            buf.rgb[i + 2] = 0;
          }
        }
      }
    }
    final r = FrameDecoder().decodeExact(buf);
    expect(r.status, DecodeStatus.rsFailed);
    expect(r.diag.rsFailed, 12);
    expect(r.diag.rsBlocks, 12);
    expect(r.cells, isNotNull);
  });
}
```

- [ ] **Step 2: Run to verify failure** — compile errors.

- [ ] **Step 3: Write diagnostics.dart**

```dart
import 'dart:typed_data';

import '../format/frame_header.dart';

enum DecodeStatus { ok, notLocated, unsupportedGrid, rsFailed, badHeader }

/// Per-frame decode diagnostics, printed as `key=value` pairs by DecodeReport.
class Diagnostics {
  int hammingMax = 0;
  double hammingMean = 0;
  double colorMarginMin = double.infinity;
  final List<int> hammingHist = [0, 0, 0, 0]; // <8, <16, <24, >=24
  int rsBlocks = 0;
  int rsOk = 0;
  int rsFailed = 0;
  String headerReason = '';
  String note = '';
  int sampleMs = 0;
  int rsMs = 0;

  void addHamming(int h) {
    if (h > hammingMax) hammingMax = h;
    hammingHist[h < 8 ? 0 : (h < 16 ? 1 : (h < 24 ? 2 : 3))]++;
  }

  Map<String, String> toMap() => {
        'hammingMax': '$hammingMax',
        'hammingMean': hammingMean.toStringAsFixed(2),
        'hammingHist': hammingHist.join('/'),
        'colorMarginMin': colorMarginMin == double.infinity ? '-' : colorMarginMin.toStringAsFixed(3),
        'rsBlocks': '$rsBlocks',
        'rsOk': '$rsOk',
        'rsFailed': '$rsFailed',
        if (headerReason.isNotEmpty) 'headerReason': headerReason,
        if (note.isNotEmpty) 'note': note,
        'sampleMs': '$sampleMs',
        'rsMs': '$rsMs',
      };
}

class FrameResult {
  final DecodeStatus status;
  final Uint8List? cells;
  final Uint8List? raw;
  final Uint8List? data;
  final FrameHeader? header;
  final Diagnostics diag;

  const FrameResult({
    required this.status,
    required this.diag,
    this.cells,
    this.raw,
    this.data,
    this.header,
  });

  bool get isOk => status == DecodeStatus.ok;
}
```

- [ ] **Step 4: Write frame_decoder.dart**

```dart
import 'dart:typed_data';

import '../format/bit_packing.dart';
import '../format/cimbar_spec.dart';
import '../format/frame_header.dart';
import '../format/rs_framing.dart';
import '../services/reed_solomon.dart';
import 'cell_classifier.dart';
import 'cell_sampler.dart';
import 'diagnostics.dart';
import 'grid_model.dart';
import 'rgb_buffer.dart';

/// The single v2 frame decoder (spec §6.1). GIF paths call [decodeExact];
/// camera paths call [decode] and (from Plan 3) get a located grid model.
class FrameDecoder {
  final ReedSolomon _rs = ReedSolomon(CimbarSpec.rsEccBytes);
  final CellClassifier _classifier = CellClassifier();

  FrameResult decode(RgbBuffer image, {GridModel? grid}) {
    if (grid == null) {
      return FrameResult(
        status: DecodeStatus.notLocated,
        diag: Diagnostics()..note = 'locator not implemented (Plan 3)',
      );
    }
    return decodeWithGrid(image, grid);
  }

  FrameResult decodeExact(RgbBuffer image) {
    const size = CimbarSpec.framePx;
    if (image.width != size || image.height != size) {
      return FrameResult(
        status: DecodeStatus.unsupportedGrid,
        diag: Diagnostics()
          ..note = 'expected ${size}x$size, got ${image.width}x${image.height} (v1 GIF?)',
      );
    }
    return decodeWithGrid(image, const ExactGridModel());
  }

  FrameResult decodeWithGrid(RgbBuffer image, GridModel grid, {List<double>? whitePoint}) {
    final diag = Diagnostics();
    final sw = Stopwatch()..start();
    final sampler = CellSampler(image, grid);
    final patch = CellPatch();
    final positions = CimbarSpec.usableCellPositions;
    final cells = Uint8List(positions.length);
    var hammingSum = 0;
    for (var k = 0; k < positions.length; k++) {
      final pos = positions[k];
      sampler.sample(pos.col, pos.row, patch);
      final c = _classifier.classify(patch, whitePoint: whitePoint);
      cells[k] = BitPacking.cellValue(c.symbol, c.color);
      hammingSum += c.hamming;
      diag.addHamming(c.hamming);
      if (c.colorMargin < diag.colorMarginMin) diag.colorMarginMin = c.colorMargin;
    }
    diag.hammingMean = hammingSum / positions.length;
    diag.sampleMs = sw.elapsedMilliseconds;

    sw.reset();
    final raw = BitPacking.unpackCells(cells);
    final rs = RsFraming.decodeFrame(raw, _rs);
    diag.rsMs = sw.elapsedMilliseconds;
    diag.rsBlocks = rs.blocksOk + rs.blocksFailed;
    diag.rsOk = rs.blocksOk;
    diag.rsFailed = rs.blocksFailed;
    if (rs.blocksFailed > 0) {
      return FrameResult(status: DecodeStatus.rsFailed, diag: diag, cells: cells, raw: raw, data: rs.data);
    }

    final hd = FrameHeader.decode(rs.data);
    if (!hd.valid) {
      diag.headerReason = hd.reason;
      return FrameResult(status: DecodeStatus.badHeader, diag: diag, cells: cells, raw: raw, data: rs.data, header: hd.header);
    }
    return FrameResult(status: DecodeStatus.ok, diag: diag, cells: cells, raw: raw, data: rs.data, header: hd.header);
  }
}
```

- [ ] **Step 5: Run tests and analyzer**

Run: `cd android && flutter test test/core/decode/frame_decoder_golden_test.dart 2>&1 | tail -3` → `All tests passed!` (9 tests: presence + 5 goldens + 3).
Run: `cd android && flutter analyze lib/core 2>&1 | tail -2` → `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add android/lib/core/decode/diagnostics.dart android/lib/core/decode/frame_decoder.dart android/test/core/decode/frame_decoder_golden_test.dart
git commit -m "Add FrameDecoder exact path with diagnostics; goldens decode byte-for-byte in Dart

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 6: FrameAssembler

**Files:**
- Create: `lib/core/decode/frame_assembler.dart`
- Test: `test/core/decode/frame_assembler_test.dart`

**Interfaces:**
- `class AddResult { bool accepted; String reason; FrameHeader? header; }`
- `class FrameAssembler { int? fileId; int total; bool encrypted; int filled; AddResult add(Uint8List data, {int blocksFailed = 0}); bool get isComplete; List<int> missingSeqs(); Uint8List framedData(); void reset(); }`
- Reasons: `rs`, then header reasons (`short`/`version`/`flags`/`total`/`seq`), `total` (same fileId, different total), `duplicate`; `''` when accepted. A different fileId resets and accepts.

- [ ] **Step 1: Write the failing test**

`test/core/decode/frame_assembler_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/frame_assembler.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/frame_header.dart';

Uint8List frame({required int fileId, required int seq, required int total, int fill = 0x5A}) {
  final f = Uint8List(CimbarSpec.dataBytesPerFrame);
  f.setRange(0, 8, FrameHeader(version: 2, encrypted: false, fileId: fileId, seq: seq, total: total).encode());
  for (var i = 8; i < f.length; i++) {
    f[i] = (fill + seq + i) & 0xFF;
  }
  return f;
}

void main() {
  test('accepts frames in any order, dedups, completes, assembles', () {
    final a = FrameAssembler();
    expect(a.add(frame(fileId: 7, seq: 1, total: 2)).accepted, isTrue);
    expect(a.total, 2);
    expect(a.filled, 1);
    expect(a.isComplete, isFalse);
    expect(a.missingSeqs(), [0]);
    expect(a.add(frame(fileId: 7, seq: 1, total: 2)).reason, 'duplicate');
    expect(a.add(frame(fileId: 7, seq: 0, total: 2)).accepted, isTrue);
    expect(a.isComplete, isTrue);
    final out = a.framedData();
    expect(out.length, 2 * CimbarSpec.fileBytesPerFrame);
    expect(out[0], frame(fileId: 7, seq: 0, total: 2)[8]);
    expect(out[CimbarSpec.fileBytesPerFrame], frame(fileId: 7, seq: 1, total: 2)[8]);
  });

  test('rejects RS-failed frames before looking at the header', () {
    final a = FrameAssembler();
    final r = a.add(frame(fileId: 7, seq: 0, total: 1), blocksFailed: 1);
    expect(r.accepted, isFalse);
    expect(r.reason, 'rs');
    expect(a.total, 0);
  });

  test('rejects invalid headers with the header reason', () {
    final a = FrameAssembler();
    final bad = frame(fileId: 7, seq: 0, total: 1);
    bad[0] = 1;
    expect(a.add(bad).reason, 'version');
    expect(a.add(Uint8List(3)).reason, 'short');
  });

  test('same fileId with a different total is rejected', () {
    final a = FrameAssembler();
    expect(a.add(frame(fileId: 7, seq: 0, total: 3)).accepted, isTrue);
    expect(a.add(frame(fileId: 7, seq: 1, total: 4)).reason, 'total');
  });

  test('a new fileId resets the collection and is accepted', () {
    final a = FrameAssembler();
    expect(a.add(frame(fileId: 7, seq: 0, total: 3)).accepted, isTrue);
    expect(a.add(frame(fileId: 8, seq: 2, total: 5)).accepted, isTrue);
    expect(a.fileId, 8);
    expect(a.total, 5);
    expect(a.filled, 1);
    expect(a.missingSeqs(), [0, 1, 3, 4]);
  });

  test('framedData throws while incomplete', () {
    final a = FrameAssembler();
    a.add(frame(fileId: 7, seq: 0, total: 2));
    expect(() => a.framedData(), throwsStateError);
  });
}
```

- [ ] **Step 2: Run to verify failure** — compile error.

- [ ] **Step 3: Write frame_assembler.dart**

```dart
import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import '../format/frame_header.dart';

class AddResult {
  final bool accepted;
  final String reason;
  final FrameHeader? header;
  const AddResult(this.accepted, this.reason, this.header);
}

/// Sequence-slot frame assembly (spec §4.4) with the §4.2 acceptance rules.
/// Reasons match web-app/cimbar.js FrameAssembler: 'rs', header reasons,
/// 'total', 'duplicate'; '' when accepted.
class FrameAssembler {
  int? fileId;
  int total = 0;
  bool encrypted = false;
  int filled = 0;
  List<Uint8List?> _slots = const [];

  void reset() {
    fileId = null;
    total = 0;
    encrypted = false;
    filled = 0;
    _slots = const [];
  }

  /// data: dataBytesPerFrame bytes after RS decode; blocksFailed: from RsFraming.
  AddResult add(Uint8List data, {int blocksFailed = 0}) {
    if (blocksFailed > 0) return const AddResult(false, 'rs', null);
    final hd = FrameHeader.decode(data);
    if (!hd.valid) return AddResult(false, hd.reason, hd.header);
    final h = hd.header!;
    if (fileId != null && h.fileId != fileId) reset();
    if (fileId != null && h.total != total) return AddResult(false, 'total', h);
    if (fileId == null) {
      fileId = h.fileId;
      total = h.total;
      encrypted = h.encrypted;
      _slots = List<Uint8List?>.filled(h.total, null);
    }
    if (_slots[h.seq] != null) return AddResult(false, 'duplicate', h);
    _slots[h.seq] = data.sublist(CimbarSpec.headerLen); // copy: caller may reuse its buffer
    filled++;
    return AddResult(true, '', h);
  }

  bool get isComplete => total > 0 && filled == total;

  List<int> missingSeqs() => [
        for (var i = 0; i < total; i++)
          if (_slots[i] == null) i,
      ];

  /// Concatenated frame bodies (still carrying the u32 length prefix + padding).
  Uint8List framedData() {
    if (!isComplete) throw StateError('Incomplete: $filled/$total frames');
    const per = CimbarSpec.fileBytesPerFrame;
    final out = Uint8List(per * total);
    for (var i = 0; i < total; i++) {
      out.setRange(i * per, (i + 1) * per, _slots[i]!);
    }
    return out;
  }
}
```

- [ ] **Step 4: Run tests and analyzer** — `flutter test test/core/decode/frame_assembler_test.dart` → 6 pass; `flutter analyze lib/core` clean.

- [ ] **Step 5: Commit**

```bash
git add android/lib/core/decode/frame_assembler.dart android/test/core/decode/frame_assembler_test.dart
git commit -m "Add FrameAssembler with v2 acceptance rules

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 7: GIF import pipeline on v2 (Android)

**Files:**
- Rewrite: `lib/core/services/decode_pipeline.dart`
- Delete: `test/core/services/decode_pipeline_test.dart`, `test/core/services/end_to_end_test.dart`
- Test: `test/core/services/decode_pipeline_v2_test.dart`

**Interfaces:**
- Unchanged public surface: `DecodePipeline().decodeGif(Uint8List gifBytes, String passphrase) → Stream<DecodeProgress>`, `lastResult`. Callers `import_controller.dart` and `camera_controller.dart` need no change.
- `CryptoService.decrypt(Uint8List, String)` unchanged.

- [ ] **Step 1: Write the failing test**

`test/core/services/decode_pipeline_v2_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/models/decode_result.dart';
import 'package:cimbar_scanner/core/services/decode_pipeline.dart';

String repoPath(String rel) => '../$rel';

Future<(DecodeProgress?, DecodePipeline)> run(String golden, String passphrase) async {
  final jsonPath = repoPath('test-data/goldens/$golden.json');
  final gif = File(GoldenSidecar.gifPathFor(jsonPath)).readAsBytesSync();
  final pipeline = DecodePipeline();
  DecodeProgress? last;
  await for (final p in pipeline.decodeGif(gif, passphrase)) {
    last = p;
  }
  return (last, pipeline);
}

void main() {
  for (final name in ['hello', 'lorem_12k', 'edge_one_frame', 'edge_two_frames']) {
    test('golden $name decodes through the GIF pipeline', () async {
      final golden = GoldenSidecar.load(repoPath('test-data/goldens/$name.json'));
      final (last, pipeline) = await run(name, '');
      expect(last?.state, DecodeState.done, reason: last?.message);
      expect(pipeline.lastResult!.filename, golden.fileName);
      expect(pipeline.lastResult!.data, golden.fileBytes);
    });
  }

  test('encrypted golden decrypts with its passphrase', () async {
    final golden = GoldenSidecar.load(repoPath('test-data/goldens/lorem_12k_enc.json'));
    final (last, pipeline) = await run('lorem_12k_enc', golden.passphrase!);
    expect(last?.state, DecodeState.done, reason: last?.message);
    expect(pipeline.lastResult!.data, golden.fileBytes);
  });

  test('encrypted golden with wrong passphrase reports an error', () async {
    final (last, _) = await run('lorem_12k_enc', 'nope');
    expect(last?.state, DecodeState.error);
    expect(last?.message, contains('Decryption failed'));
  });

  test('encrypted golden with empty passphrase asks for one', () async {
    final (last, _) = await run('lorem_12k_enc', '');
    expect(last?.state, DecodeState.error);
    expect(last?.message, contains('passphrase'));
  });

  test('a v1 GIF is rejected with a message naming v2', () async {
    final pipeline = DecodePipeline();
    DecodeProgress? last;
    await for (final p in pipeline.decodeGif(File('test/fixtures/test_hello.gif').readAsBytesSync(), '')) {
      last = p;
    }
    expect(last?.state, DecodeState.error);
    expect(last?.message, contains('608'));
  });
}
```

- [ ] **Step 2: Delete the v1 GIF tests and run to verify failure**

```bash
git rm android/test/core/services/decode_pipeline_test.dart android/test/core/services/end_to_end_test.dart
```
Run: `cd android && flutter test test/core/services/decode_pipeline_v2_test.dart 2>&1 | tail -5` → failures (the v1 pipeline cannot decode 608 px frames; `Failed to parse`/error states).

- [ ] **Step 3: Rewrite decode_pipeline.dart**

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../decode/diagnostics.dart';
import '../decode/frame_assembler.dart';
import '../decode/frame_decoder.dart';
import '../decode/rgb_buffer.dart';
import '../format/file_container.dart';
import '../models/decode_result.dart';
import 'crypto_service.dart';
import 'gif_parser.dart';

/// GIF import: GIF -> frames -> FrameDecoder (exact) -> FrameAssembler ->
/// length prefix -> [decrypt] -> file. Mirrors web-app/index.html startDecode.
class DecodePipeline {
  final FrameDecoder _decoder = FrameDecoder();

  Stream<DecodeProgress> decodeGif(Uint8List gifBytes, String passphrase) async* {
    yield const DecodeProgress(state: DecodeState.parsingGif, message: 'Parsing GIF...');

    final List<img.Image> frames;
    try {
      frames = GifParser.parseFrames(gifBytes);
    } catch (e) {
      yield DecodeProgress(state: DecodeState.error, message: 'Failed to parse GIF: $e');
      return;
    }

    yield const DecodeProgress(state: DecodeState.decodingFrames, message: 'Decoding frames...');

    final assembler = FrameAssembler();
    var rejected = 0;
    for (var i = 0; i < frames.length; i++) {
      final r = _decoder.decodeExact(RgbBuffer.fromImage(frames[i]));
      if (r.status == DecodeStatus.unsupportedGrid) {
        yield DecodeProgress(
          state: DecodeState.error,
          message: 'Not a CimBar v2 GIF: frames must be 608x608 px (${r.diag.note}). v1 GIFs must be re-encoded.',
        );
        return;
      }
      final added = assembler.add(r.data!, blocksFailed: r.diag.rsFailed);
      if (!added.accepted) rejected++;
      yield DecodeProgress(
        state: DecodeState.decodingFrames,
        progress: (i + 1) / frames.length,
        message: 'Frame ${i + 1}/${frames.length}: ${added.accepted ? 'ok' : 'rejected (${added.reason})'}',
      );
    }

    if (!assembler.isComplete) {
      yield DecodeProgress(
        state: DecodeState.error,
        message: 'Incomplete: ${assembler.filled} of ${assembler.total} frames decoded ($rejected rejected)',
      );
      return;
    }

    final Uint8List payloadBytes;
    try {
      payloadBytes = FileContainer.stripLengthPrefix(assembler.framedData());
    } on FormatException catch (e) {
      yield DecodeProgress(state: DecodeState.error, message: 'Header corrupt: ${e.message}');
      return;
    }

    final Uint8List plain;
    if (FileContainer.isEncrypted(payloadBytes)) {
      if (passphrase.isEmpty) {
        yield const DecodeProgress(state: DecodeState.error, message: 'This GIF is encrypted: a passphrase is required');
        return;
      }
      yield const DecodeProgress(state: DecodeState.decrypting, progress: 0.5, message: 'Decrypting...');
      try {
        plain = CryptoService.decrypt(payloadBytes, passphrase);
      } catch (e) {
        yield DecodeProgress(state: DecodeState.error, message: 'Decryption failed: $e');
        return;
      }
    } else {
      plain = payloadBytes;
    }

    final ParsedFile file;
    try {
      file = FileContainer.parsePayload(plain);
    } on FormatException catch (e) {
      yield DecodeProgress(state: DecodeState.error, message: 'File header corrupt: ${e.message}');
      return;
    }

    // Store result BEFORE yield — async* generators suspend at yield.
    _lastResult = DecodeResult(filename: file.fileName, data: file.fileBytes);
    yield DecodeProgress(
      state: DecodeState.done,
      progress: 1.0,
      message: 'Decoded: ${file.fileName} (${file.fileBytes.length} bytes)',
    );
  }

  DecodeResult? _lastResult;
  DecodeResult? get lastResult => _lastResult;
}
```

- [ ] **Step 4: Run the new test, then the whole suite**

Run: `cd android && flutter test test/core/services/decode_pipeline_v2_test.dart 2>&1 | tail -3` → 8 pass.
Run: `cd android && sh tests/run_all.sh` → all pass (v1 camera tests untouched; 127 − 11 deleted + new ones).
Run: `cd android && flutter analyze 2>&1 | tail -2` → `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add -A android/lib/core/services/decode_pipeline.dart android/test/core/services/
git commit -m "Switch Android GIF import to the v2 FrameDecoder and FrameAssembler

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 8: DecodeReport and the CLI decoder

**Files:**
- Create: `lib/core/decode/decode_report.dart`
- Create: `tool/decode_image.dart`
- Test: `test/core/decode/decode_report_test.dart`

**Interfaces:**
- `class TruthComparison { int cells; int symbolCorrect; int colorCorrect; int cellCorrect; List<int> wrongCellIndices; double get symbolAccuracy; double get colorAccuracy; double get cellAccuracy; }`
- `DecodeReport.compare(Uint8List cells, Uint8List truthCells) → TruthComparison`
- `DecodeReport.lines(FrameResult r, {int frameIndex = 0, GoldenFrame? truth}) → List<String>` — lines: `frame=<i> stage=cells hammingMax=… hammingMean=… hammingHist=… colorMarginMin=… sampleMs=…`, `frame=<i> stage=rs blocks=… ok=… failed=… rsMs=…`, `frame=<i> stage=header valid=… version=… fileId=0x… seq=… total=… encrypted=…` (or `valid=false reason=…`), `frame=<i> stage=result status=<ok|…> note=…`, and with truth `frame=<i> stage=truth symbolAcc=0.998 colorAcc=… cellAcc=… wrongCells=N`.
- `DecodeReport.heatmap(Uint8List cells, Uint8List truthCells) → img.Image` (608×608: correct cell gray, wrong symbol red, wrong color blue, both magenta).
- CLI: `dart run tool/decode_image.dart <image.png|jpg|gif> [--frame N] [--golden path.json] [--heatmap out.png] [--mode exact|camera]`. Default mode: `exact` for `.gif`, `camera` otherwise; `camera` prints `stage=result status=notLocated note=locator not implemented (Plan 3)` and exits 1. Exit 0 iff status ok.

- [ ] **Step 1: Write the failing test**

`test/core/decode/decode_report_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/decode_report.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/services/gif_parser.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final jsonPath = repoPath('test-data/goldens/hello.json');
  final golden = GoldenSidecar.load(jsonPath);
  final frame = GifParser.parseFrames(File(GoldenSidecar.gifPathFor(jsonPath)).readAsBytesSync()).first;

  test('compare counts symbol/color/cell correctness', () {
    final truth = golden.frames[0].cells;
    final cells = Uint8List.fromList(truth);
    cells[0] ^= 0x04; // symbol bit
    cells[1] ^= 0x01; // color bit
    cells[2] ^= 0x05; // both
    final c = DecodeReport.compare(cells, truth);
    expect(c.cells, 3840);
    expect(c.symbolCorrect, 3838);
    expect(c.colorCorrect, 3838);
    expect(c.cellCorrect, 3837);
    expect(c.wrongCellIndices, [0, 1, 2]);
    expect(c.cellAccuracy, closeTo(3837 / 3840, 1e-9));
  });

  test('lines contain the stage keys and truth accuracy', () {
    final r = FrameDecoder().decodeExact(RgbBuffer.fromImage(frame));
    final lines = DecodeReport.lines(r, frameIndex: 0, truth: golden.frames[0]);
    expect(lines.any((l) => l.startsWith('frame=0 stage=cells ') && l.contains('hammingMax=0')), isTrue);
    expect(lines.any((l) => l.startsWith('frame=0 stage=rs ') && l.contains('ok=12')), isTrue);
    expect(lines.any((l) => l.startsWith('frame=0 stage=header ') && l.contains('fileId=0x1001')), isTrue);
    expect(lines.any((l) => l.startsWith('frame=0 stage=result status=ok')), isTrue);
    expect(lines.any((l) => l.startsWith('frame=0 stage=truth ') && l.contains('cellAcc=1.000') && l.contains('wrongCells=0')), isTrue);
  });

  test('heatmap is 608x608 and marks wrong cells', () {
    final truth = golden.frames[0].cells;
    final cells = Uint8List.fromList(truth);
    cells[0] ^= 0x04;
    final hm = DecodeReport.heatmap(cells, truth);
    expect(hm.width, 608);
    final p = hm.getPixel(88 + 4, 16 + 4); // cell (8,0) center
    expect(p.r > 200 && p.g < 80, isTrue, reason: 'wrong symbol is red');
    final q = hm.getPixel(88 + 9 + 4, 16 + 4); // cell (9,0)
    expect(q.r == q.g && q.g == q.b, isTrue, reason: 'correct cell is gray');
  });
}
```

- [ ] **Step 2: Run to verify failure** — compile error.

- [ ] **Step 3: Write decode_report.dart**

```dart
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../format/bit_packing.dart';
import '../format/cimbar_spec.dart';
import 'diagnostics.dart';
import 'golden_sidecar.dart';

class TruthComparison {
  final int cells;
  final int symbolCorrect;
  final int colorCorrect;
  final int cellCorrect;
  final List<int> wrongCellIndices;
  const TruthComparison(this.cells, this.symbolCorrect, this.colorCorrect, this.cellCorrect, this.wrongCellIndices);
  double get symbolAccuracy => symbolCorrect / cells;
  double get colorAccuracy => colorCorrect / cells;
  double get cellAccuracy => cellCorrect / cells;
}

/// Structured `frame=N stage=… key=value` lines and ground-truth comparison.
class DecodeReport {
  DecodeReport._();

  static TruthComparison compare(Uint8List cells, Uint8List truth) {
    var sym = 0, col = 0, both = 0;
    final wrong = <int>[];
    for (var k = 0; k < truth.length; k++) {
      final s = BitPacking.cellSymbol(cells[k]) == BitPacking.cellSymbol(truth[k]);
      final c = BitPacking.cellColor(cells[k]) == BitPacking.cellColor(truth[k]);
      if (s) sym++;
      if (c) col++;
      if (s && c) {
        both++;
      } else {
        wrong.add(k);
      }
    }
    return TruthComparison(truth.length, sym, col, both, wrong);
  }

  static String _kv(Map<String, String> m) => m.entries.map((e) => '${e.key}=${e.value}').join(' ');

  static List<String> lines(FrameResult r, {int frameIndex = 0, GoldenFrame? truth}) {
    final d = r.diag.toMap();
    final out = <String>[];
    final p = 'frame=$frameIndex';
    out.add('$p stage=cells ${_kv({
          'hammingMax': d['hammingMax']!,
          'hammingMean': d['hammingMean']!,
          'hammingHist': d['hammingHist']!,
          'colorMarginMin': d['colorMarginMin']!,
          'sampleMs': d['sampleMs']!,
        })}');
    out.add('$p stage=rs ${_kv({'blocks': d['rsBlocks']!, 'ok': d['rsOk']!, 'failed': d['rsFailed']!, 'rsMs': d['rsMs']!})}');
    final h = r.header;
    if (h != null && r.diag.headerReason.isEmpty && r.status != DecodeStatus.rsFailed) {
      out.add('$p stage=header ${_kv({
            'valid': 'true',
            'version': '${h.version}',
            'fileId': '0x${h.fileId.toRadixString(16)}',
            'seq': '${h.seq}',
            'total': '${h.total}',
            'encrypted': '${h.encrypted}',
          })}');
    } else {
      out.add('$p stage=header valid=false reason=${r.diag.headerReason.isEmpty ? '-' : r.diag.headerReason}');
    }
    out.add('$p stage=result status=${r.status.name}${r.diag.note.isEmpty ? '' : ' note=${r.diag.note}'}');
    if (truth != null && r.cells != null) {
      final c = compare(r.cells!, truth.cells);
      out.add('$p stage=truth ${_kv({
            'symbolAcc': c.symbolAccuracy.toStringAsFixed(3),
            'colorAcc': c.colorAccuracy.toStringAsFixed(3),
            'cellAcc': c.cellAccuracy.toStringAsFixed(3),
            'wrongCells': '${c.wrongCellIndices.length}',
          })}');
    }
    return out;
  }

  /// 608x608 image: correct cells gray, wrong symbol red, wrong color blue, both magenta.
  static img.Image heatmap(Uint8List cells, Uint8List truth) {
    final im = img.Image(width: CimbarSpec.framePx, height: CimbarSpec.framePx);
    final positions = CimbarSpec.usableCellPositions;
    for (var k = 0; k < positions.length; k++) {
      final s = BitPacking.cellSymbol(cells[k]) == BitPacking.cellSymbol(truth[k]);
      final c = BitPacking.cellColor(cells[k]) == BitPacking.cellColor(truth[k]);
      final r = s ? (c ? 96 : 0) : 230;
      final g = s && c ? 96 : 0;
      final b = c ? (s ? 96 : 0) : 230;
      final ox = CimbarSpec.cellOriginX(positions[k].col), oy = CimbarSpec.cellOriginY(positions[k].row);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          im.setPixelRgb(ox + x, oy + y, r, g, b);
        }
      }
    }
    return im;
  }
}
```

- [ ] **Step 4: Write tool/decode_image.dart**

```dart
// Offline CimBar v2 decoder. Pure Dart: `dart run tool/decode_image.dart …` from android/.
//
// Usage:
//   dart run tool/decode_image.dart <image.png|jpg|gif> [--frame N] [--golden name.json]
//                                   [--heatmap out.png] [--mode exact|camera]
// Prints `frame=N stage=… key=value` lines. Exit 0 iff the frame decodes (status ok).
import 'dart:io';

import 'package:image/image.dart' as img;

import 'package:cimbar_scanner/core/decode/decode_report.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/services/gif_parser.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: decode_image.dart <image> [--frame N] [--golden x.json] [--heatmap out.png] [--mode exact|camera]');
    exit(2);
  }
  final path = args[0];
  var frameIndex = 0;
  String? goldenPath;
  String? heatmapPath;
  String? mode;
  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--frame':
        frameIndex = int.parse(args[++i]);
      case '--golden':
        goldenPath = args[++i];
      case '--heatmap':
        heatmapPath = args[++i];
      case '--mode':
        mode = args[++i];
      default:
        stderr.writeln('unknown argument ${args[i]}');
        exit(2);
    }
  }
  final bytes = File(path).readAsBytesSync();
  final isGif = path.toLowerCase().endsWith('.gif');
  mode ??= isGif ? 'exact' : 'camera';

  final img.Image image;
  var frameCount = 1;
  if (isGif) {
    final frames = GifParser.parseFrames(bytes);
    frameCount = frames.length;
    if (frameIndex >= frames.length) {
      stderr.writeln('frame $frameIndex out of range (${frames.length} frames)');
      exit(2);
    }
    image = frames[frameIndex];
  } else {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      stderr.writeln('cannot decode image $path');
      exit(2);
    }
    image = decoded;
  }
  stdout.writeln('frame=$frameIndex stage=input path=$path width=${image.width} height=${image.height} frames=$frameCount mode=$mode');

  final buffer = RgbBuffer.fromImage(image);
  final decoder = FrameDecoder();
  final result = mode == 'exact' ? decoder.decodeExact(buffer) : decoder.decode(buffer);

  GoldenFrame? truth;
  if (goldenPath != null) {
    final golden = GoldenSidecar.load(goldenPath);
    if (frameIndex < golden.frames.length) truth = golden.frames[frameIndex];
  }
  for (final line in DecodeReport.lines(result, frameIndex: frameIndex, truth: truth)) {
    stdout.writeln(line);
  }
  if (heatmapPath != null && truth != null && result.cells != null) {
    File(heatmapPath).writeAsBytesSync(img.encodePng(DecodeReport.heatmap(result.cells!, truth.cells)));
    stdout.writeln('frame=$frameIndex stage=heatmap path=$heatmapPath');
  }
  exit(result.status == DecodeStatus.ok ? 0 : 1);
}
```

- [ ] **Step 5: Run tests, analyzer and the CLI**

Run: `cd android && flutter test test/core/decode/decode_report_test.dart 2>&1 | tail -3` → 3 pass.
Run: `cd android && flutter analyze 2>&1 | tail -2` → clean.
Run: `cd android && dart run tool/decode_image.dart ../test-data/goldens/hello.gif --golden ../test-data/goldens/hello.json --heatmap /tmp/hm.png; echo exit=$?`
Expected: lines `frame=0 stage=input …`, `stage=cells hammingMax=0 …`, `stage=rs blocks=12 ok=12 failed=0 …`, `stage=header valid=true … fileId=0x1001 seq=0 total=1 encrypted=false`, `stage=result status=ok`, `stage=truth symbolAcc=1.000 colorAcc=1.000 cellAcc=1.000 wrongCells=0`, `stage=heatmap path=/tmp/hm.png`, `exit=0`.
Run: `cd android && dart run tool/decode_image.dart test/fixtures/camera_raw_1280x720_a.png; echo exit=$?` → `stage=result status=notLocated note=locator not implemented (Plan 3)`, `exit=1`.

- [ ] **Step 6: Commit**

```bash
git add android/lib/core/decode/decode_report.dart android/tool/decode_image.dart android/test/core/decode/decode_report_test.dart
git commit -m "Add DecodeReport and the offline decode_image CLI

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

### Task 9: Corpus benchmark scaffolding, runner output, docs

**Files:**
- Create: `test/fixtures/corpus/README.md`, `test/fixtures/corpus/v1_720p_negative_a/meta.json`, `test/fixtures/corpus/v1_720p_negative_b/meta.json`
- Create: `test/core/decode/corpus_benchmark_test.dart`
- Modify: `tests/run_all.sh` (print the corpus table after the suite)
- Modify: `android/CLAUDE.md`, `CLAUDE.md`, `CHANGELOG.md`

**Interfaces:**
- `meta.json` schema: `{ "capture": "capture.png" (path relative to the case dir), "device": "", "display": "", "distanceCm": 0, "golden": "hello" | null, "frame": 0, "expect": { "status": ["ok"], "symbolAccuracy": 0.0, "colorAccuracy": 0.0, "rsOkBlocks": 0 } }` — `status` is the list of acceptable statuses; the accuracy/rsOk thresholds are asserted only when `golden` is set and the status is `ok`.
- The benchmark test writes `build/corpus_report.txt` (one header line + one row per case) and asserts each case's expectations.

- [ ] **Step 1: Corpus README and the two negative cases**

`test/fixtures/corpus/README.md`:

```markdown
# Real-capture corpus

Each case is a directory with a `meta.json` and (normally) a `capture.png`, plus a pointer to
the golden that was on screen. `test/core/decode/corpus_benchmark_test.dart` decodes every
case, prints one table row each (also written to `build/corpus_report.txt`, echoed by
`tests/run_all.sh`), and asserts the case's `expect` block. Thresholds are only ever raised.

`meta.json`:

```json
{
  "capture": "capture.png",
  "device": "Pixel 7",
  "display": "Dell U2720Q 27in 4K, present mode",
  "distanceCm": 40,
  "golden": "hello",
  "frame": 0,
  "expect": { "status": ["ok"], "symbolAccuracy": 0.99, "colorAccuracy": 0.99, "rsOkBlocks": 12 }
}
```

- `golden`: name of the sidecar in `test-data/goldens/` shown when the capture was taken, or
  `null` for negative cases. `frame`: which frame of that golden was on screen.
- `expect.status`: acceptable `DecodeStatus` names. Accuracy and RS thresholds apply only
  when `golden` is set and the status is `ok`.

Capture checklist (spec §9.3): for `hello` and `lorem_12k`, in present mode, using the app's
debug capture button: laptop monitor at 30 cm and 60 cm, straight-on and ~20° angled;
phone-to-phone at 15 cm and 30 cm; one in dim light. Record device and display names.

The two `v1_720p_negative_*` cases point at the existing v1 captures and must never decode.
```

`test/fixtures/corpus/v1_720p_negative_a/meta.json`:

```json
{
  "capture": "../../camera_raw_1280x720_a.png",
  "device": "unknown phone (v1 era)",
  "display": "Dell monitor, v1 256px barcode",
  "distanceCm": 0,
  "golden": null,
  "frame": 0,
  "expect": { "status": ["notLocated", "unsupportedGrid"] }
}
```

`v1_720p_negative_b/meta.json`: same with `camera_raw_1280x720_b.png`.

- [ ] **Step 2: Write the benchmark test**

`test/core/decode/corpus_benchmark_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/decode/decode_report.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final corpus = Directory('test/fixtures/corpus');
  final cases = corpus
      .listSync()
      .whereType<Directory>()
      .where((d) => File('${d.path}/meta.json').existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final rows = <String>['case | status | symbolAcc | colorAcc | rsOk/blocks | hammingMean | ms'];

  for (final dir in cases) {
    final name = dir.path.split('/').last;
    test('corpus $name', () {
      final meta = jsonDecode(File('${dir.path}/meta.json').readAsStringSync()) as Map<String, dynamic>;
      final capturePath = '${dir.path}/${meta['capture'] as String}';
      final image = img.decodeImage(File(capturePath).readAsBytesSync());
      expect(image, isNotNull, reason: 'cannot decode $capturePath');
      final sw = Stopwatch()..start();
      final r = FrameDecoder().decode(RgbBuffer.fromImage(image!));
      final ms = sw.elapsedMilliseconds;

      var symAcc = '-', colAcc = '-';
      TruthComparison? cmp;
      final goldenName = meta['golden'] as String?;
      if (goldenName != null && r.cells != null) {
        final golden = GoldenSidecar.load(repoPath('test-data/goldens/$goldenName.json'));
        cmp = DecodeReport.compare(r.cells!, golden.frames[meta['frame'] as int].cells);
        symAcc = cmp.symbolAccuracy.toStringAsFixed(3);
        colAcc = cmp.colorAccuracy.toStringAsFixed(3);
      }
      rows.add('$name | ${r.status.name} | $symAcc | $colAcc | ${r.diag.rsOk}/${r.diag.rsBlocks} | ${r.diag.hammingMean.toStringAsFixed(1)} | $ms');

      final expectBlock = meta['expect'] as Map<String, dynamic>;
      final okStatuses = (expectBlock['status'] as List).cast<String>();
      expect(okStatuses, contains(r.status.name), reason: '$name: status ${r.status.name} not in $okStatuses (${r.diag.toMap()})');
      if (goldenName != null && r.status == DecodeStatus.ok && cmp != null) {
        expect(cmp.symbolAccuracy, greaterThanOrEqualTo((expectBlock['symbolAccuracy'] as num).toDouble()));
        expect(cmp.colorAccuracy, greaterThanOrEqualTo((expectBlock['colorAccuracy'] as num).toDouble()));
        expect(r.diag.rsOk, greaterThanOrEqualTo(expectBlock['rsOkBlocks'] as int));
      }
    });
  }

  tearDownAll(() {
    Directory('build').createSync(recursive: true);
    File('build/corpus_report.txt').writeAsStringSync('${rows.join('\n')}\n');
  });
}
```

- [ ] **Step 3: Runner prints the table**

In `tests/run_all.sh`:
1. Delete the line `set -e` (the script's only command is the `flutter test … | python3 -c "…"` pipeline, whose exit status is captured explicitly below).
2. Right after `echo ""` that follows `echo "=== Flutter Test Suite ==="`, add `rm -f build/corpus_report.txt` so a stale report from an earlier run is never shown.
3. The file currently ends with the closing `"` of the `python3 -c "…"` heredoc-style argument. Append after that closing quote:

```sh
STATUS=$?
if [ -f build/corpus_report.txt ]; then
  echo ""
  echo "=== Corpus benchmark ==="
  cat build/corpus_report.txt
fi
exit $STATUS
```

(`$?` of a pipeline is the exit status of its last command, the Python summarizer, which exits 1 on any failure — so a failing suite still exits non-zero.)

Run: `cd android && sh tests/run_all.sh` → suite passes and the corpus table shows two `notLocated` rows.

- [ ] **Step 4: Docs**

`android/CLAUDE.md`:
- Under "Decoding Pipelines", replace the `GIF import:` line with: `GIF import: GIF → parse frames (image pkg) → FrameDecoder.decodeExact (core/decode) → FrameAssembler → length prefix → [decrypt] → File`, and add a sentence: "Camera photo and live scan are still on the v1 decoder until Plans 3–4."
- Add a section "## v2 Format and Decode Layer (`lib/core/format/`, `lib/core/decode/`)" listing each file from this plan's file map with one line each, the `FrameDecoder` contract (`decode(image, {grid})` / `decodeExact`, statuses), the assembler rules, and: "No Flutter imports under these directories; `tool/decode_image.dart` runs with `dart run`."
- Add "## CLI decoder" with the usage line and an example command + example output lines from Task 8 Step 5.
- Add "## Corpus benchmark" pointing at `test/fixtures/corpus/README.md` and `build/corpus_report.txt`.
- In the Tests table, add rows for the new test files and remove `decode_pipeline_test.dart` / `end_to_end_test.dart`.

Root `CLAUDE.md` Interoperability section: change the Android sentence to "The Android app decodes v2 GIFs via file import (Plan 2); its camera paths still run the v1 decoder until Plans 3–4 land."

`CHANGELOG.md` under `## [Unreleased]`, add:

```markdown
### Changed
- **CimBar v2 format** (breaking): 64×64 grid of 8 px tiles with 1 px gaps, four QR-style finders, 4 colors × 16 tiles = 6 bits/cell, RS(255,191), per-frame header `[ver][flags][fileId][seq][total]`, single 608 px frame. Web app encodes/decodes v2; Android GIF import decodes v2. v1 GIFs must be re-encoded.
- Web app: frame-size menu removed, present-mode full-screen display added.

### Added
- Golden GIFs with ground-truth sidecars (`test-data/goldens/`) shared by the JS and Dart test suites.
- Offline Dart CLI decoder `android/tool/decode_image.dart` and a real-capture corpus benchmark scaffold.
```

- [ ] **Step 5: Full suite, analyzer, commit**

Run: `cd android && flutter analyze 2>&1 | tail -2` → clean. Run: `cd android && sh tests/run_all.sh` → all pass + corpus table.

```bash
git add android/test/fixtures/corpus android/test/core/decode/corpus_benchmark_test.dart android/tests/run_all.sh android/CLAUDE.md CLAUDE.md CHANGELOG.md
git commit -m "Add corpus benchmark scaffolding and document the v2 Dart decode layer

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X5nB1mM1wabuXdwYEKgSgi"
```

---

## Self-review notes

- Spec coverage: §3 constants + §7.1 Dart side (Task 1), §3.5 packing and §4.2 header (Task 2), §4.3 RS layout incl. the interleave rule cross-checked against goldens (Task 3), §4.1 container (Task 3), §6.1/6.4/6.6/6.7/6.8 exact path (Tasks 4–5), §4.4 assembler (Task 6), GIF import switch (Task 7, build-order step 4), §9.2 CLI and §9.3 scaffolding (Tasks 8–9, build-order step 3), §9.4 Dart rows for spec constants / header / packing / golden decode. Locator, homography grid model, drift and the synthetic-degradation tests are Plan 3; camera acquisition and v1 deletion are Plan 4.
- Deviation from spec §9.1 recorded here: the Dart test encoder is **not** deleted in this plan because the surviving v1 camera tests still use it; Plan 4 deletes both together.
- Names used across tasks: `CimbarSpec.*`, `Tiles.bits/hamming`, `FrameHeader.decode → HeaderDecode{header, reason, valid}`, `BitPacking.*`, `RsFraming.encodeFrame/decodeFrame → RsFrameResult{data, blocksOk, blocksFailed}`, `FileContainer.*`, `GoldenSidecar.load/gifPathFor`, `RgbBuffer.fromImage/bilinear`, `GridModel.toSource → (double, double)`, `ExactGridModel`, `CellSampler.sample`, `CellPatch{luma, rgb}`, `CellClassifier.classify → CellClassification{symbol, hamming, color, colorMargin}`, `Diagnostics`, `FrameResult{status, cells, raw, data, header, diag}`, `FrameDecoder.decode/decodeExact/decodeWithGrid`, `FrameAssembler.add(data, {blocksFailed}) → AddResult{accepted, reason, header}`, `DecodeReport.compare/lines/heatmap` — spelled identically in every task that uses them.
- Dart records `(double, double)` and switch-expression `case` syntax need Dart ≥ 3.0; the project's SDK floor is 3.3.
