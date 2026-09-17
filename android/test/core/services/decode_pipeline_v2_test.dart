import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/models/decode_result.dart';
import 'package:cimbar_scanner/core/services/decode_pipeline.dart';

String repoPath(String rel) => '../$rel';

Future<(DecodeProgress?, DecodePipeline)> run(String golden, String passphrase) async {
  final jsonPath = repoPath('test-data/goldens/$golden.json');
  final gif = File(GoldenSidecar.gifPathFor(jsonPath)).readAsBytesSync();
  final pipeline = DecodePipeline();
  DecodeProgress? last;
  await for (final p in pipeline.decodeGif(gif, passphrase)) {
    last = p;
  }
  return (last, pipeline);
}

void main() {
  for (final name in ['hello', 'lorem_12k', 'edge_one_frame', 'edge_two_frames']) {
    test('golden $name decodes through the GIF pipeline', () async {
      final golden = GoldenSidecar.load(repoPath('test-data/goldens/$name.json'));
      final (last, pipeline) = await run(name, '');
      expect(last?.state, DecodeState.done, reason: last?.message);
      expect(pipeline.lastResult!.filename, golden.fileName);
      expect(pipeline.lastResult!.data, golden.fileBytes);
    });
  }

  test('encrypted golden decrypts with its passphrase', () async {
    final golden = GoldenSidecar.load(repoPath('test-data/goldens/lorem_12k_enc.json'));
    final (last, pipeline) = await run('lorem_12k_enc', golden.passphrase!);
    expect(last?.state, DecodeState.done, reason: last?.message);
    expect(pipeline.lastResult!.data, golden.fileBytes);
  });

  test('encrypted golden with wrong passphrase reports an error', () async {
    final (last, _) = await run('lorem_12k_enc', 'nope');
    expect(last?.state, DecodeState.error);
    expect(last?.message, contains('Decryption failed'));
  });

  test('encrypted golden with empty passphrase asks for one', () async {
    final (last, _) = await run('lorem_12k_enc', '');
    expect(last?.state, DecodeState.error);
    expect(last?.message, contains('passphrase'));
  });

  test('a v1 GIF is rejected with a message naming v2', () async {
    final pipeline = DecodePipeline();
    DecodeProgress? last;
    await for (final p in pipeline.decodeGif(File('test/fixtures/test_hello.gif').readAsBytesSync(), '')) {
      last = p;
    }
    expect(last?.state, DecodeState.error);
    expect(last?.message, contains('608'));
  });
}
