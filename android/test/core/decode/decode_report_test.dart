import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/decode_report.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/services/gif_parser.dart';

import '../../test_utils/synthetic_scene.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final jsonPath = repoPath('test-data/goldens/hello.json');
  final golden = GoldenSidecar.load(jsonPath);
  final frame = GifParser.parseFrames(File(GoldenSidecar.gifPathFor(jsonPath)).readAsBytesSync()).first;

  test('compare counts symbol/color/cell correctness', () {
    final truth = golden.frames[0].cells;
    final cells = Uint8List.fromList(truth);
    cells[0] ^= 0x04; // symbol bit
    cells[1] ^= 0x01; // color bit
    cells[2] ^= 0x05; // both
    final c = DecodeReport.compare(cells, truth);
    expect(c.cells, 3840);
    expect(c.symbolCorrect, 3838);
    expect(c.colorCorrect, 3838);
    expect(c.cellCorrect, 3837);
    expect(c.wrongCellIndices, [0, 1, 2]);
    expect(c.cellAccuracy, closeTo(3837 / 3840, 1e-9));
  });

  test('lines contain the stage keys and truth accuracy', () {
    final r = FrameDecoder().decodeExact(RgbBuffer.fromImage(frame));
    final lines = DecodeReport.lines(r, frameIndex: 0, truth: golden.frames[0]);
    expect(lines.any((l) => l.startsWith('frame=0 stage=cells ') && l.contains('hammingMax=0')), isTrue);
    expect(lines.any((l) => l.startsWith('frame=0 stage=rs ') && l.contains('ok=12')), isTrue);
    expect(lines.any((l) => l.startsWith('frame=0 stage=header ') && l.contains('fileId=0x1001')), isTrue);
    expect(lines.any((l) => l.startsWith('frame=0 stage=result status=ok')), isTrue);
    expect(lines.any((l) => l.startsWith('frame=0 stage=truth ') && l.contains('cellAcc=1.000') && l.contains('wrongCells=0')), isTrue);
  });

  test('heatmap is 608x608 and marks wrong cells', () {
    final truth = golden.frames[0].cells;
    final cells = Uint8List.fromList(truth);
    cells[0] ^= 0x04;
    final hm = DecodeReport.heatmap(cells, truth);
    expect(hm.width, 608);
    final p = hm.getPixel(88 + 4, 16 + 4); // cell (8,0) center
    expect(p.r > 200 && p.g < 80, isTrue, reason: 'wrong symbol is red');
    final q = hm.getPixel(88 + 9 + 4, 16 + 4); // cell (9,0)
    expect(q.r == q.g && q.g == q.b, isTrue, reason: 'correct cell is gray');
  });

  test('camera-path lines include locate/grid/wb stages', () {
    final scene = renderScene(RgbBuffer.fromImage(frame), 800, 800, SceneSpec()..centerX = 400..centerY = 400);
    final r = FrameDecoder().decode(scene.image, useDrift: false);
    final lines = DecodeReport.lines(r, frameIndex: 0);
    expect(lines.any((l) => l.startsWith('frame=0 stage=locate ok=true') && l.contains('corners=')), isTrue, reason: lines.join('\n'));
    // The estimate is a tolerance-gated diagnostic (64 ± 6); the run-length module is ~1% noisy.
    expect(lines.any((l) => RegExp(r'^frame=0 stage=grid estimate=(5[89]|6[0-9]|70)$').hasMatch(l)), isTrue, reason: lines.join('\n'));
    expect(lines.any((l) => l.startsWith('frame=0 stage=wb rgb=')), isTrue);
    expect(lines.any((l) => l.startsWith('frame=0 stage=result status=ok')), isTrue);
  });
}
