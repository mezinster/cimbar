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
    expect(FrameHeader.decode(Uint8List.fromList([2, 8, 0, 0, 0, 0, 0, 1])).reason, 'flags');
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

  test('v2.1 flags: repair and compressed round trip', () {
    const h = FrameHeader(
        version: 2, encrypted: true, repair: true, compressed: true, fileId: 0x1234, seq: 65535, total: 3);
    final b = h.encode();
    expect(b, Uint8List.fromList([2, 7, 0x12, 0x34, 0xFF, 0xFF, 0, 3]));
    final d = FrameHeader.decode(b);
    expect(d.valid, isTrue, reason: 'a repair row id is not bounded by total');
    expect(d.reason, '');
    expect(d.header!.repair, isTrue);
    expect(d.header!.compressed, isTrue);
    expect(d.header!.encrypted, isTrue);
    expect(d.header!.seq, 65535);
    expect(d.header!.total, 3);
  });

  test('flag bits are independent', () {
    expect(const FrameHeader(version: 2, encrypted: false, repair: true, fileId: 1, seq: 0, total: 1).encode()[1], 2);
    expect(const FrameHeader(version: 2, encrypted: false, compressed: true, fileId: 1, seq: 0, total: 1).encode()[1], 4);
    final d = FrameHeader.decode(Uint8List.fromList([2, 4, 0, 1, 0, 0, 0, 1]));
    expect(d.valid, isTrue);
    expect(d.header!.compressed, isTrue);
    expect(d.header!.repair, isFalse);
    expect(d.header!.encrypted, isFalse);
  });

  test('reserved flag bits are rejected, defined ones are not', () {
    expect(FrameHeader.decode(Uint8List.fromList([2, 8, 0, 0, 0, 0, 0, 1])).reason, 'flags');
    expect(FrameHeader.decode(Uint8List.fromList([2, 0x80, 0, 0, 0, 0, 0, 1])).reason, 'flags');
    expect(FrameHeader.decode(Uint8List.fromList([2, 7, 0, 0, 0, 0, 0, 1])).reason, '');
  });

  test('a source frame with seq >= total is still rejected', () {
    expect(FrameHeader.decode(Uint8List.fromList([2, 4, 0, 0, 0, 5, 0, 5])).reason, 'seq');
    expect(FrameHeader.decode(Uint8List.fromList([2, 6, 0, 0, 0, 5, 0, 5])).reason, '', reason: 'repair rows exempt');
  });

  test('toString names the new flags', () {
    final s = const FrameHeader(version: 2, encrypted: false, repair: true, compressed: true, fileId: 1, seq: 0, total: 2)
        .toString();
    expect(s, contains('rep=true'));
    expect(s, contains('comp=true'));
  });
}
