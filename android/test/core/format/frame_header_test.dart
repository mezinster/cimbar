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
