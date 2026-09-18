import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/rateless_assembler.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/frame_header.dart';
import 'package:cimbar_scanner/core/format/rateless.dart';

/// A source frame with a constant-ish filler body (ported from the old sequence-slot assembler's tests).
Uint8List frame({required int fileId, required int seq, required int total, int fill = 0x5A}) {
  final f = Uint8List(CimbarSpec.dataBytesPerFrame);
  f.setRange(0, 8, FrameHeader(version: 2, encrypted: false, fileId: fileId, seq: seq, total: total).encode());
  for (var i = 8; i < f.length; i++) {
    f[i] = (fill + seq + i) & 0xFF;
  }
  return f;
}

/// Deterministic LCG body, byte-identical to the JS tests' seqBytes().
Uint8List body(int seed) {
  final b = Uint8List(CimbarSpec.fileBytesPerFrame);
  var s = seed & 0xFFFFFFFF;
  for (var i = 0; i < b.length; i++) {
    s = (s * 1664525 + 1013904223) & 0xFFFFFFFF;
    b[i] = s >> 24;
  }
  return b;
}

Uint8List source(int fileId, int seq, int total, Uint8List b, {bool compressed = false}) {
  final f = Uint8List(CimbarSpec.dataBytesPerFrame);
  f.setRange(
      0,
      8,
      FrameHeader(version: 2, encrypted: false, compressed: compressed, fileId: fileId, seq: seq, total: total)
          .encode());
  f.setRange(8, 8 + b.length, b);
  return f;
}

Uint8List repair(int fileId, int r, List<Uint8List> bodies, {bool compressed = false}) {
  final f = Uint8List(CimbarSpec.dataBytesPerFrame);
  f.setRange(
      0,
      8,
      FrameHeader(
              version: 2,
              encrypted: false,
              repair: true,
              compressed: compressed,
              fileId: fileId,
              seq: r,
              total: bodies.length)
          .encode());
  f.setRange(8, 8 + CimbarSpec.fileBytesPerFrame,
      Rateless.combine(bodies, Rateless.coefficients(fileId, r, bodies.length)));
  return f;
}

void main() {
  // ── ported sequence-slot-assembler cases (filled -> rank, no missingSeqs) ──

  test('accepts frames in any order, dedups, completes, assembles', () {
    final a = RatelessAssembler();
    expect(a.add(frame(fileId: 7, seq: 1, total: 2)).accepted, isTrue);
    expect(a.total, 2);
    expect(a.rank, 1);
    expect(a.isComplete, isFalse);
    expect(a.add(frame(fileId: 7, seq: 1, total: 2)).reason, 'duplicate');
    expect(a.add(frame(fileId: 7, seq: 0, total: 2)).accepted, isTrue);
    expect(a.isComplete, isTrue);
    final out = a.framedData();
    expect(out.length, 2 * CimbarSpec.fileBytesPerFrame);
    expect(out[0], frame(fileId: 7, seq: 0, total: 2)[8]);
    expect(out[CimbarSpec.fileBytesPerFrame], frame(fileId: 7, seq: 1, total: 2)[8]);
  });

  test('rejects RS-failed frames before looking at the header', () {
    final a = RatelessAssembler();
    final r = a.add(frame(fileId: 7, seq: 0, total: 1), blocksFailed: 1);
    expect(r.accepted, isFalse);
    expect(r.reason, 'rs');
    expect(r.header, isNull);
    expect(a.total, 0);
  });

  test('rejects a short frame buffer before header decode', () {
    final a = RatelessAssembler();
    final full = frame(fileId: 7, seq: 0, total: 3);
    final truncated = Uint8List.sublistView(full, 0, CimbarSpec.dataBytesPerFrame - 1);
    final r = a.add(truncated);
    expect(r.accepted, isFalse);
    expect(r.reason, 'short');
    expect(r.header, isNull);
    expect(a.total, 0, reason: 'assembler state untouched');
    expect(a.add(full).accepted, isTrue, reason: 'a full frame is still accepted afterwards');
  });

  test('rejects invalid headers with the header reason', () {
    final a = RatelessAssembler();
    final bad = frame(fileId: 7, seq: 0, total: 1);
    bad[0] = 1;
    expect(a.add(bad).reason, 'version');
    expect(a.add(Uint8List(3)).reason, 'short');
  });

  test('same fileId with a different total is rejected', () {
    final a = RatelessAssembler();
    expect(a.add(frame(fileId: 7, seq: 0, total: 3)).accepted, isTrue);
    expect(a.add(frame(fileId: 7, seq: 1, total: 4)).reason, 'total');
  });

  test('a new fileId resets the collection and is accepted', () {
    final a = RatelessAssembler();
    expect(a.add(frame(fileId: 7, seq: 0, total: 3)).accepted, isTrue);
    expect(a.add(frame(fileId: 8, seq: 2, total: 5)).accepted, isTrue);
    expect(a.fileId, 8);
    expect(a.total, 5);
    expect(a.rank, 1);
  });

  test('framedData throws while incomplete', () {
    final a = RatelessAssembler();
    a.add(frame(fileId: 7, seq: 0, total: 2));
    expect(() => a.framedData(), throwsStateError);
  });

  // ── v2.1 coding ──

  for (final n in [1, 2, 7, 64, 345]) {
    test('N=$n: source-only, repair-only and shuffled mixes decode', () {
      final bodies = [for (var i = 0; i < n; i++) body(100 + n + i)];
      final src = [for (var i = 0; i < n; i++) source(0x2000 + n, i, n, bodies[i])];
      // Only n + 2 repair rows are ever consumed below; building 2n would
      // double an already O(n^2 * bodyLen) test with no extra coverage.
      final rep = [for (var r = 0; r < n + 2; r++) repair(0x2000 + n, r, bodies)];
      void check(List<Uint8List> rows, String label) {
        final a = RatelessAssembler();
        for (final d in rows) {
          final res = a.add(d);
          expect(res.accepted || res.reason == 'dependent', isTrue, reason: '$label ${res.reason}');
        }
        expect(a.isComplete, isTrue, reason: '$label rank ${a.rank}/${a.total}');
        final out = a.framedData();
        for (var i = 0; i < n; i++) {
          expect(out.sublist(i * CimbarSpec.fileBytesPerFrame, (i + 1) * CimbarSpec.fileBytesPerFrame), bodies[i],
              reason: '$label body $i');
        }
      }

      check(src, 'source');
      if (n > 1) {
        check(rep.take(n + 2).toList(), 'repair only');
        final mixed = [...src.take(n ~/ 2), ...rep.take(n - n ~/ 2 + 2)]..shuffle(Random(n));
        check(mixed, 'mixed');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }

  test('duplicate, dependent, flags mismatch and counters', () {
    final bodies = [for (var i = 0; i < 4; i++) body(7 + i)];
    final src = [for (var i = 0; i < 4; i++) source(0x3000, i, 4, bodies[i], compressed: true)];
    final a = RatelessAssembler();
    expect(a.add(src[0]).accepted, isTrue);
    expect(a.add(src[0]).reason, 'duplicate');
    expect(a.rank, 1);
    expect(a.add(repair(0x3000, 0, bodies, compressed: true)).accepted, isTrue);
    expect(a.rank, 2);
    expect(a.add(repair(0x3000, 0, bodies, compressed: true)).reason, 'duplicate');
    expect(a.duplicateCount, 2);
    final mismatch = source(0x3000, 1, 4, bodies[1]); // compressed bit clear
    expect(a.add(mismatch).reason, 'flags');
    expect(a.add(src[1], blocksFailed: 1).reason, 'rs');

    final b = RatelessAssembler();
    for (final d in src) {
      expect(b.add(d).accepted, isTrue);
    }
    expect(b.isComplete, isTrue);
    expect(b.add(repair(0x3000, 3, bodies, compressed: true)).reason, 'dependent');
    expect(b.sourceCount, 4);
    expect(b.repairCount, 0, reason: 'a dependent repair row must not be counted as accepted');
    expect(b.dependentCount, 1);
    expect(b.compressed, isTrue);
    expect(b.encrypted, isFalse);
  });

  // ── amendments: sparse unit rows, the `uncoded` guard and counters ──

  test('memory bound: an all-source, in-order file never materialises a dense row', () {
    const n = 200;
    final bodies = [for (var i = 0; i < n; i++) body(11 + i)];
    final a = RatelessAssembler();
    for (var i = 0; i < n; i++) {
      expect(a.add(source(0x6000, i, n, bodies[i])).accepted, isTrue);
    }
    expect(a.isComplete, isTrue);
    expect(a.denseRows, 0, reason: 'an all-source, in-order file must never materialise a dense row');
    expect(a.sourceCount, n);
    expect(a.repairCount, 0);
    final out = a.framedData();
    for (var i = 0; i < n; i++) {
      expect(out.sublist(i * CimbarSpec.fileBytesPerFrame, (i + 1) * CimbarSpec.fileBytesPerFrame), bodies[i],
          reason: 'body $i');
    }

    final b = RatelessAssembler();
    expect(b.add(repair(0x6000, 0, bodies)).accepted, isTrue);
    expect(b.denseRows, 1, reason: 'a repair row is always materialised');
    expect(b.repairCount, 1);
  });

  test('memory bound: total beyond codingMaxFrames accepts source frames only (uncoded mode)', () {
    const n = CimbarSpec.codingMaxFrames + 1;
    const fileId = 0x7000;
    final srcFrame = source(fileId, 0, n, body(42));
    final repFrame = Uint8List(CimbarSpec.dataBytesPerFrame);
    repFrame.setRange(
        0,
        8,
        const FrameHeader(version: 2, encrypted: false, repair: true, fileId: fileId, seq: 0, total: n)
            .encode());
    repFrame.setRange(8, 8 + CimbarSpec.fileBytesPerFrame, body(43));

    final a = RatelessAssembler();
    expect(a.add(srcFrame).accepted, isTrue, reason: 'source accepted even when total exceeds maxFrames');
    expect(a.total, n);
    expect(a.add(repFrame).reason, 'uncoded');
    expect(a.repairCount, 0);
    expect(a.denseRows, 0, reason: 'uncoded-mode acceptance never materialises a dense row');
  });

  test('a source frame landing on a repair-held column is materialised and eliminated', () {
    final bodies = [for (var i = 0; i < 4; i++) body(300 + i)];
    final a = RatelessAssembler();
    // A repair row takes pivot column 0 first; the source frame for seq 0 then
    // has to be materialised and eliminated against it.
    expect(a.add(repair(0x8000, 0, bodies)).accepted, isTrue);
    expect(a.denseRows, 1);
    for (var i = 0; i < 4; i++) {
      expect(a.add(source(0x8000, i, 4, bodies[i])).accepted || a.rank == 4, isTrue);
    }
    expect(a.isComplete, isTrue);
    expect(a.denseRows, greaterThanOrEqualTo(1));
    final out = a.framedData();
    for (var i = 0; i < 4; i++) {
      expect(out.sublist(i * CimbarSpec.fileBytesPerFrame, (i + 1) * CimbarSpec.fileBytesPerFrame), bodies[i],
          reason: 'body $i');
    }
  });

  test('reset clears file state and counters', () {
    final bodies = [for (var i = 0; i < 2; i++) body(500 + i)];
    final a = RatelessAssembler();
    expect(a.add(source(0x9000, 0, 2, bodies[0])).accepted, isTrue);
    a.reset();
    expect(a.fileId, isNull);
    expect(a.total, 0);
    expect(a.rank, 0);
    expect(a.sourceCount, 0);
    expect(a.isComplete, isFalse);
    expect(a.denseRows, 0);
  });
}
