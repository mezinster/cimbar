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
