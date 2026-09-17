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
