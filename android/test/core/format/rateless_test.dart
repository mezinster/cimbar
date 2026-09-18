import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/rateless_assembler.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/frame_header.dart';
import 'package:cimbar_scanner/core/format/rateless.dart';
import 'package:cimbar_scanner/core/services/galois_field.dart';

/// Deterministic LCG body, byte-identical to the JS tests' seqBytes().
Uint8List body(int len, int seed) {
  final b = Uint8List(len);
  var s = seed & 0xFFFFFFFF;
  for (var i = 0; i < len; i++) {
    s = (s * 1664525 + 1013904223) & 0xFFFFFFFF;
    b[i] = s >> 24;
  }
  return b;
}

Uint8List repairFrame(int fileId, int r, List<Uint8List> bodies) {
  final f = Uint8List(CimbarSpec.dataBytesPerFrame);
  f.setRange(
      0,
      CimbarSpec.headerLen,
      FrameHeader(version: 2, encrypted: false, repair: true, fileId: fileId, seq: r, total: bodies.length).encode());
  final combined = Rateless.combine(bodies, Rateless.coefficients(fileId, r, bodies.length));
  f.setRange(CimbarSpec.headerLen, CimbarSpec.headerLen + combined.length, combined);
  return f;
}

void main() {
  test('coefficients match the spec vectors', () {
    expect(Rateless.coefficients(0x1234, 0, 12), [28, 109, 139, 16, 186, 124, 155, 221, 203, 51, 25, 61]);
    expect(Rateless.coefficients(0x1234, 1, 12), [128, 8, 126, 10, 167, 74, 57, 30, 16, 200, 144, 103]);
    expect(Rateless.coefficients(0, 0, 12), [14, 243, 204, 191, 171, 157, 143, 229, 84, 239, 176, 155]);
    expect(Rateless.coefficients(0xFFFF, 65535, 12), [3, 182, 181, 52, 55, 127, 108, 1, 42, 32, 112, 65]);
    // Deterministic, and a prefix of a longer row is the same row.
    expect(Rateless.coefficients(0x1234, 0, 400), Rateless.coefficients(0x1234, 0, 400));
    expect(Rateless.coefficients(0x1234, 0, 400).sublist(0, 12), Rateless.coefficients(0x1234, 0, 12));
  });

  test('coefficients are stated against spec/cimbar-v2.json constants', () {
    expect(CimbarSpec.codingIncrement, 0x9E3779B9);
    expect(CimbarSpec.codingMixMul1, 0x85EBCA6B);
    expect(CimbarSpec.codingMixMul2, 0xC2B2AE35);
    expect(CimbarSpec.codingMaxFrames, 4096);
  });

  test('combine: unit row copies, coefficient 1 xors, general case uses GF mul', () {
    final a = Uint8List.fromList([1, 2, 3, 250]), b = Uint8List.fromList([9, 8, 7, 6]);
    expect(Rateless.combine([a, b], Uint8List.fromList([1, 0])), a);
    expect(Rateless.combine([a, b], Uint8List.fromList([1, 1])), [1 ^ 9, 2 ^ 8, 3 ^ 7, 250 ^ 6]);
    final y = Rateless.combine([a, b], Uint8List.fromList([3, 7]));
    for (var i = 0; i < 4; i++) {
      expect(y[i], GaloisField.gfMul(3, a[i]) ^ GaloisField.gfMul(7, b[i]));
    }
    // An all-zero coefficient row combines to zero.
    expect(Rateless.combine([a, b], Uint8List(2)), Uint8List(4));
  });

  // Guard against a future linear generator (e.g. a plain xorshift/LFSR):
  // exactly N consecutive repair ids r = 0..N-1 must already be full rank,
  // with no slack repair rows to fall back on.
  for (final n in [7, 64, 345]) {
    test('N=$n: exactly N repair rows r=0..N-1 (no slack) reach full rank', () {
      final fileId = 0x5000 + n;
      final bodies = [for (var i = 0; i < n; i++) body(CimbarSpec.fileBytesPerFrame, 200 + n + i)];
      final asm = RatelessAssembler();
      for (var r = 0; r < n; r++) {
        final res = asm.add(repairFrame(fileId, r, bodies));
        expect(res.accepted, isTrue, reason: 'N=$n r=$r rejected: ${res.reason}');
      }
      expect(asm.isComplete, isTrue, reason: 'N=$n rank ${asm.rank}/${asm.total}');
      final out = asm.framedData();
      for (var i = 0; i < n; i++) {
        expect(out.sublist(i * CimbarSpec.fileBytesPerFrame, (i + 1) * CimbarSpec.fileBytesPerFrame), bodies[i],
            reason: 'N=$n body $i');
      }
    });
  }
}
