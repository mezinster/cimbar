import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/services/payload_decoder.dart';

String repoPath(String rel) => '../$rel';
Uint8List fixedBytes(int n, int start) => Uint8List.fromList(List.generate(n, (i) => (start + i) & 0xFF));

void main() {
  final goldens = Directory(repoPath('test-data/goldens')).listSync().whereType<File>()
      .where((f) => f.path.endsWith('.json')).map((f) => GoldenSidecar.load(f.path)).toList();

  for (final g in goldens.where((g) => g.repairFrames == 0 && !g.compressed)) {
    test('${g.name}: bodies equal the golden source frames byte for byte', () {
      final p = PayloadEncoder.encode(
        name: g.fileName, bytes: g.fileBytes, passphrase: g.passphrase ?? '', fileId: g.fileId,
        allowCompression: false, salt: fixedBytes(16, 0xA0), iv: fixedBytes(12, 0xB0));
      expect(p.total, g.total);
      expect(p.framedLength, g.framedDataLength);
      expect(p.encrypted, g.passphrase != null);
      for (var i = 0; i < p.total; i++) {
        expect(p.bodies[i], g.frames[i].data.sublist(CimbarSpec.headerLen), reason: 'body $i');
      }
    });
  }

  for (final g in goldens.where((g) => g.compressed)) {
    test('${g.name}: compresses like the web encoder and decodes back', () {
      final p = PayloadEncoder.encode(name: g.fileName, bytes: g.fileBytes, passphrase: g.passphrase ?? '', fileId: g.fileId);
      expect(p.compressed, isTrue);
      final framed = Uint8List.fromList(p.bodies.expand((b) => b).toList());
      final f = decodeFramedPayload(framed, g.passphrase ?? '', compressed: true);
      expect(f.fileName, g.fileName);
      expect(f.fileBytes, g.fileBytes);
    });
  }

  test('incompressible bytes are sent raw', () {
    final rng = math.Random(42);
    final rnd = List.generate(5000, (_) => rng.nextInt(256));
    final p = PayloadEncoder.encode(name: 'r.bin', bytes: Uint8List.fromList(rnd));
    expect(p.compressed, isFalse);
  });

  test('shouldCompress mirrors compress.js: d <= floor(n * 0.95)', () {
    expect(PayloadEncoder.shouldCompress(100, 95), isTrue);
    expect(PayloadEncoder.shouldCompress(100, 96), isFalse);
    expect(PayloadEncoder.shouldCompress(0, 0), isFalse);
  });

  test('random fileId is 16-bit', () {
    final p = PayloadEncoder.encode(name: 'a.txt', bytes: Uint8List.fromList([65]));
    expect(p.fileId, inInclusiveRange(0, 0xFFFF));
    expect(p.total, 1);
    expect(p.bodies.single.length, CimbarSpec.fileBytesPerFrame);
  });
}
