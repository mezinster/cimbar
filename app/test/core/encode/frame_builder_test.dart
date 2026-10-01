import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rateless_assembler.dart';
import 'package:cimbar_scanner/core/encode/cell_grid.dart';
import 'package:cimbar_scanner/core/encode/frame_builder.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/services/payload_decoder.dart';

String repoPath(String rel) => '../$rel';

/// The payload a golden was built from, taken from its source frames — so
/// repair frames can be checked without depending on zlib's exact output.
EncodedPayload payloadOf(GoldenSidecar g) => EncodedPayload(
      fileId: g.fileId,
      encrypted: g.passphrase != null,
      compressed: g.compressed,
      framedLength: g.framedDataLength,
      bodies: [for (final f in g.frames.where((f) => !f.repair)) f.data.sublist(CimbarSpec.headerLen)],
    );

void main() {
  final goldens = Directory(repoPath('test-data/goldens')).listSync().whereType<File>()
      .where((f) => f.path.endsWith('.json')).map((f) => GoldenSidecar.load(f.path)).toList();

  for (final g in goldens) {
    test('${g.name}: frames, raw bytes and cells equal the sidecar', () {
      final p = payloadOf(g);
      // The five pre-v2.1 goldens carry source frames only (gen_goldens.js gates
      // repair frames on `coded`); the coded ones carry the full GIF composition.
      final frames = g.frameCount == g.total
          ? [for (var s = 0; s < p.total; s++) FrameBuilder.sourceFrame(p, s)]
          : FrameBuilder.gifFrames(p);
      expect(frames.length, g.frames.length);
      for (var i = 0; i < frames.length; i++) {
        expect(frames[i], g.frames[i].data, reason: 'frame $i data');
        expect(CellGrid.raw(frames[i]), g.frames[i].raw, reason: 'frame $i raw');
        expect(CellGrid.cells(frames[i]), g.frames[i].cells, reason: 'frame $i cells');
      }
    });
  }

  test('repair-only frames reassemble a 9-frame text file', () {
    final text = Uint8List.fromList(List.generate(17000, (i) => 0x41 + (i * 31 % 26)));
    final p = PayloadEncoder.encode(name: 'n.txt', bytes: text, allowCompression: false);
    expect(p.total, greaterThan(1));
    final asm = RatelessAssembler();
    var r = 0;
    while (!asm.isComplete) {
      final rf = FrameBuilder.nextRepair(p, r);
      asm.add(rf.data);
      r = rf.nextR;
    }
    final f = decodeFramedPayload(asm.framedData(), '');
    expect(f.fileBytes, text);
  });

  test('a one-frame file has no repair frames in its GIF', () {
    final p = PayloadEncoder.encode(name: 'a.txt', bytes: Uint8List.fromList([65]));
    expect(FrameBuilder.gifFrames(p).length, 1);
  });

  test('repair frame generation at N=345 and N=4096 stays fast', () {
    for (final n in [345, 4096]) {
      final p = EncodedPayload(fileId: 0x1234, encrypted: false, compressed: false, framedLength: n * 2104,
          bodies: List.generate(n, (i) => Uint8List(CimbarSpec.fileBytesPerFrame)..fillRange(0, 2104, i & 0xFF)));
      final sw = Stopwatch()..start();
      for (var r = 0; r < 3; r++) {
        FrameBuilder.nextRepair(p, r);
      }
      final ms = sw.elapsedMilliseconds / 3;
      // ignore: avoid_print
      print('repair frame at N=$n: ${ms.toStringAsFixed(1)} ms');
      expect(ms, lessThan(250), reason: 'N=$n'); // ~21 ms JIT on the dev machine; generous for CI
    }
  });
}
