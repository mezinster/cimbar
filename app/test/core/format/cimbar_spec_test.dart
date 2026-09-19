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

    test('v2.1 coding constants and header flag bits', () {
      final c = spec['coding'] as Map<String, dynamic>;
      expect(CimbarSpec.codingIncrement, c['increment']);
      expect(CimbarSpec.codingMixMul1, c['mixMul1']);
      expect(CimbarSpec.codingMixMul2, c['mixMul2']);
      expect(CimbarSpec.codingMaxFrames, c['maxFrames']);
      expect(CimbarSpec.gifRepairRatio, c['gifRepairRatio']);
      final comp = spec['compression'] as Map<String, dynamic>;
      expect(CimbarSpec.maxInflatedBytes, comp['maxInflatedBytes']);
      // The JSON stores bit indices; CimbarSpec stores the masks.
      final flags = (spec['header'] as Map<String, dynamic>)['flags'] as Map<String, dynamic>;
      expect(CimbarSpec.flagEncrypted, 1 << (flags['encrypted'] as int));
      expect(CimbarSpec.flagRepair, 1 << (flags['repair'] as int));
      expect(CimbarSpec.flagCompressed, 1 << (flags['compressed'] as int));
      expect(CimbarSpec.flagReserved,
          0xFF & ~(CimbarSpec.flagEncrypted | CimbarSpec.flagRepair | CimbarSpec.flagCompressed));
      expect(CimbarSpec.gifRepairCount(1), 0);
      expect(CimbarSpec.gifRepairCount(2), 1);
      expect(CimbarSpec.gifRepairCount(5), 2);
      expect(CimbarSpec.gifRepairCount(345), 87);
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
