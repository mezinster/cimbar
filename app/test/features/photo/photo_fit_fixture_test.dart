import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/encode/frame_budget.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/features/photo/domain/optimised_file_name.dart';
import 'package:cimbar_scanner/features/photo/domain/photo_fit.dart';

import '../../support/fake_jpeg_session.dart';

String repoPath(String rel) => '../$rel';

int _linear(int side, int q) => side * side * q ~/ 1000;
int _steep(int side, int q) => side * side * q * q * q ~/ 100000;

/// Shared Dart<->JS contract: web-app/tests/test_photo_fit.js asserts the same file.
void main() {
  final fixture = jsonDecode(File(repoPath('test-data/photo-fit.json')).readAsStringSync())
      as Map<String, dynamic>;

  test('bytesPerFrame', () {
    expect(CimbarSpec.fileBytesPerFrame, fixture['bytesPerFrame']);
  });

  for (final c in (fixture['budget'] as List).cast<Map<String, dynamic>>()) {
    test('budget: ${c['frames']} frames, name length ${(c['name'] as String).length}', () {
      expect(photoByteBudget(c['frames'] as int, c['name'] as String), c['budget']);
    });
  }

  for (final c in (fixture['frames'] as List).cast<Map<String, dynamic>>()) {
    test('frames: ${c['dataBytes']} B, encrypted ${c['encrypted']}', () {
      expect(
        framesForFile(c['name'] as String, c['dataBytes'] as int, encrypted: c['encrypted'] as bool),
        c['frames'],
      );
    });
  }

  for (final c in (fixture['fit'] as List).cast<Map<String, dynamic>>()) {
    test('fit: ${c['width']}x${c['height']} budget ${c['budget']} (${c['model']})', () async {
      final size = c['model'] == 'steep' ? _steep : _linear;
      final s = FakeJpegSession(c['width'] as int, c['height'] as int, size: size);
      final r = await fitToBudget(s, c['budget'] as int);
      expect(r.maxSide, c['maxSide']);
      expect(r.quality, c['quality']);
      expect(r.fits, c['fits']);
      expect(r.bytes, isA<Uint8List>());
    });
  }

  for (final c in (fixture['names'] as List).cast<Map<String, dynamic>>()) {
    test('name: "${c['original']}"', () {
      expect(optimisedFileName(c['original'] as String, DateTime.parse(c['now'] as String)), c['out']);
    });
  }
}
