import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/encode/cell_grid.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/encode/frame_raster.dart';
import 'package:cimbar_scanner/core/encode/gif_writer.dart';
import 'package:cimbar_scanner/core/services/gif_parser.dart';

String repoPath(String rel) => '../$rel';

/// The payload a golden was made from, rebuilt from its source bodies
/// (as frame_builder_test.dart's payloadOf does).
EncodedPayload payloadOf(GoldenSidecar g) => EncodedPayload(
      fileId: g.fileId,
      encrypted: g.passphrase != null,
      compressed: g.compressed,
      framedLength: g.framedDataLength,
      bodies: [for (final f in g.frames.where((f) => !f.repair)) f.data.sublist(CimbarSpec.headerLen)],
    );

void main() {
  final jsons = Directory(repoPath('test-data/goldens')).listSync().whereType<File>()
      .where((f) => f.path.endsWith('.json')).map((f) => f.path).toList()..sort();

  for (final path in jsons) {
    final g = GoldenSidecar.load(path);
    final gifPath = path.replaceAll('.json', '.gif');

    test('${g.name}: raster equals the golden GIF pixels', () {
      final frames = GifParser.parseFrames(File(gifPath).readAsBytesSync());
      for (var i = 0; i < g.frames.length; i++) {
        final rgb = FrameRaster.toRgb(FrameRaster.render(CellGrid.cells(g.frames[i].data)));
        expect(rgb, RgbBuffer.fromImage(frames[i]).rgb, reason: 'frame $i pixels');
      }
    });

    test('${g.name}: GifWriter output is byte-identical to the golden .gif', () {
      final indexFrames = [for (final f in g.frames) FrameRaster.render(CellGrid.cells(f.data))];
      expect(GifWriter.encode(indexFrames, delayCs: g.delayMs ~/ 10), File(gifPath).readAsBytesSync());
    });

    test('${g.name}: encodeStream over a lazy iterable is byte-identical to the golden .gif', () {
      Iterable<Uint8List> lazy() sync* {
        for (final f in g.frames) {
          yield FrameRaster.render(CellGrid.cells(f.data));
        }
      }
      expect(GifWriter.encodeStream(lazy(), delayCs: g.delayMs ~/ 10), File(gifPath).readAsBytesSync());
    });

    // Coded goldens carry the full GIF composition (N source + repair), which
    // is exactly what buildGif streams.
    if (g.frameCount > g.total) {
      test('${g.name}: buildGif from the source bodies equals the golden .gif', () {
        expect(buildGif(payloadOf(g), g.delayMs), File(gifPath).readAsBytesSync());
      });
    }
  }

  test('a rendered frame decodes exactly back to its cells', () {
    final g = GoldenSidecar.load(repoPath('test-data/goldens/hello.json'));
    final idx = FrameRaster.render(CellGrid.cells(g.frames[0].data));
    final r = FrameDecoder().decodeExact(RgbBuffer(608, 608, FrameRaster.toRgb(idx)));
    expect(r.cells, g.frames[0].cells);
  });
}
