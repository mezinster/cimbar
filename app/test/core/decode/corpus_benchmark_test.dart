import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/decode/decode_report.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';

String repoPath(String rel) => '../$rel';

void main() {
  final corpus = Directory('test/fixtures/corpus');
  final cases = corpus
      .listSync()
      .whereType<Directory>()
      .where((d) => File('${d.path}/meta.json').existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final rows = <String>['case | status | symbolAcc | colorAcc | rsOk/blocks | hammingMean | ms'];

  for (final dir in cases) {
    final name = dir.path.split('/').last;
    test('corpus $name', () {
      final meta = jsonDecode(File('${dir.path}/meta.json').readAsStringSync()) as Map<String, dynamic>;
      final capturePath = '${dir.path}/${meta['capture'] as String}';
      final image = img.decodeImage(File(capturePath).readAsBytesSync());
      expect(image, isNotNull, reason: 'cannot decode $capturePath');
      final sw = Stopwatch()..start();
      final r = FrameDecoder().decode(RgbBuffer.fromImage(image!));
      final ms = sw.elapsedMilliseconds;

      var symAcc = '-', colAcc = '-';
      TruthComparison? cmp;
      final goldenName = meta['golden'] as String?;
      if (goldenName != null && r.cells != null) {
        final golden = GoldenSidecar.load(repoPath('test-data/goldens/$goldenName.json'));
        cmp = DecodeReport.compare(r.cells!, golden.frames[meta['frame'] as int].cells);
        symAcc = cmp.symbolAccuracy.toStringAsFixed(3);
        colAcc = cmp.colorAccuracy.toStringAsFixed(3);
      }
      rows.add('$name | ${r.status.name} | $symAcc | $colAcc | ${r.diag.rsOk}/${r.diag.rsBlocks} | ${r.diag.hammingMean.toStringAsFixed(1)} | $ms');

      final expectBlock = meta['expect'] as Map<String, dynamic>;
      final okStatuses = (expectBlock['status'] as List).cast<String>();
      expect(okStatuses, contains(r.status.name), reason: '$name: status ${r.status.name} not in $okStatuses (${r.diag.toMap()})');
      if (goldenName != null && r.status == DecodeStatus.ok && cmp != null) {
        expect(cmp.symbolAccuracy, greaterThanOrEqualTo((expectBlock['symbolAccuracy'] as num).toDouble()));
        expect(cmp.colorAccuracy, greaterThanOrEqualTo((expectBlock['colorAccuracy'] as num).toDouble()));
        expect(r.diag.rsOk, greaterThanOrEqualTo(expectBlock['rsOkBlocks'] as int));
      }
    });
  }

  tearDownAll(() {
    Directory('build').createSync(recursive: true);
    File('build/corpus_report.txt').writeAsStringSync('${rows.join('\n')}\n');
  });
}
