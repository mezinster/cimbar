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
    expect(r.data.every((b) => b == 0), isTrue);
  });

  test('encodeFrame rejects data longer than dataBytesPerFrame', () {
    final tooLong = Uint8List(2113);
    expect(() => RsFraming.encodeFrame(tooLong, rs), throwsArgumentError);
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
