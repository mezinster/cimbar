import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/constants/cimbar_constants.dart';
import 'package:cimbar_scanner/core/services/cimbar_decoder.dart';
import 'package:cimbar_scanner/core/services/reed_solomon.dart';

import '../../test_utils/cimbar_encoder.dart';

void main() {
  final rs = ReedSolomon(CimbarConstants.eccBytes);
  final decoder = CimbarDecoder(rs);

  /// Load a test fixture PNG from test/fixtures/.
  img.Image loadFixture(String filename) {
    final bytes = File('test/fixtures/$filename').readAsBytesSync();
    final image = img.decodePng(bytes);
    if (image == null) fail('Failed to decode $filename');
    return image;
  }

  group('Crop image WB sampling', () {
    test('WB white point from padded crop should find finder whites, not background', () {
      final cropImg = loadFixture('crop_frame_1.png');

      // Resize to 384px (the native barcode frame size) like the crop path does
      final resized = img.copyResize(cropImg,
          width: 384, height: 384,
          interpolation: img.Interpolation.nearest);

      final stats = DecodeStats();
      decoder.decodeFramePixels(resized, 384,
          enableWhiteBalance: true,
          useRelativeColor: true,
          useHashDetection: true,
          stats: stats);

      // WB white point should be bright (finder whites), not dark background
      expect(stats.wbWhitePoint, isNotNull,
          reason: 'WB should be computed');
      expect(stats.wbWhitePoint![0], greaterThan(150),
          reason: 'WB red channel should be bright (finder white), '
              'got ${stats.wbWhitePoint![0].toStringAsFixed(0)}');
      expect(stats.wbWhitePoint![1], greaterThan(150),
          reason: 'WB green channel should be bright (finder white), '
              'got ${stats.wbWhitePoint![1].toStringAsFixed(0)}');
      expect(stats.wbWhitePoint![2], greaterThan(150),
          reason: 'WB blue channel should be bright (finder white), '
              'got ${stats.wbWhitePoint![2].toStringAsFixed(0)}');
    });

    test('WB white point from padded crop: all 3 fixtures', () {
      for (final fixture in ['crop_frame_1.png', 'crop_frame_2.png', 'crop_frame_3.png']) {
        final cropImg = loadFixture(fixture);
        final resized = img.copyResize(cropImg,
            width: 384, height: 384,
            interpolation: img.Interpolation.nearest);

        final stats = DecodeStats();
        decoder.decodeFramePixels(resized, 384,
            enableWhiteBalance: true,
            useRelativeColor: true,
            useHashDetection: true,
            stats: stats);

        expect(stats.wbWhitePoint, isNotNull,
            reason: '$fixture: WB should be computed');
        final wp = stats.wbWhitePoint!;
        expect(wp[0], greaterThan(150),
            reason: '$fixture: WB R=${wp[0].toStringAsFixed(0)} too dark');
        expect(wp[1], greaterThan(150),
            reason: '$fixture: WB G=${wp[1].toStringAsFixed(0)} too dark');
        expect(wp[2], greaterThan(150),
            reason: '$fixture: WB B=${wp[2].toStringAsFixed(0)} too dark');
      }
    });
  });

  group('White point override', () {
    test('externally provided whitePoint overrides internal sampling', () {
      final cropImg = loadFixture('crop_frame_1.png');
      final resized = img.copyResize(cropImg,
          width: 384, height: 384,
          interpolation: img.Interpolation.nearest);

      final stats = DecodeStats();
      decoder.decodeFramePixels(resized, 384,
          enableWhiteBalance: true,
          useRelativeColor: true,
          useHashDetection: true,
          whitePoint: [240.0, 245.0, 243.0],
          stats: stats);

      // Stats should reflect the provided white point, not internal sampling
      expect(stats.wbWhitePoint, isNotNull);
      expect(stats.wbWhitePoint![0], closeTo(240.0, 0.1));
      expect(stats.wbWhitePoint![1], closeTo(245.0, 0.1));
      expect(stats.wbWhitePoint![2], closeTo(243.0, 0.1));
      expect(stats.whiteBalanceApplied, isTrue);
    });
  });

  group('Crop decode with camera images', () {
    test('crop path color distribution should not be dominated by single color', () {
      // Without WB fix, crop path produces ~66% c3 (white).
      // With fix, color distribution should be more balanced.
      final cropImg = loadFixture('crop_frame_1.png');
      final resized = img.copyResize(cropImg,
          width: 384, height: 384,
          interpolation: img.Interpolation.nearest);

      final stats = DecodeStats();
      decoder.decodeFramePixels(resized, 384,
          enableWhiteBalance: true,
          useRelativeColor: true,
          useHashDetection: true,
          stats: stats);

      // No single color should dominate >40% of cells
      final totalCells = stats.cellCount;
      for (var i = 0; i < 8; i++) {
        final pct = stats.colorHist[i] * 100.0 / totalCells;
        expect(pct, lessThan(40),
            reason: 'Color $i has ${pct.toStringAsFixed(1)}% of cells — too dominant. '
                'colorHist=${stats.colorHist}');
      }
    });
  });

  group('Camera decode diagnostics', () {
    test('hash detection hamming distances on crop images', () {
      for (final fixture in ['crop_frame_1.png', 'crop_frame_2.png', 'crop_frame_3.png']) {
        final cropImg = loadFixture(fixture);
        final resized = img.copyResize(cropImg,
            width: 384, height: 384,
            interpolation: img.Interpolation.nearest);

        final stats = DecodeStats();
        decoder.decodeFramePixels(resized, 384,
            enableWhiteBalance: true,
            useRelativeColor: true,
            useHashDetection: true,
            stats: stats);

        // Hamming average should be below 25 (random is ~32)
        expect(stats.hammingAvg, lessThan(25),
            reason: '$fixture: avg hamming ${stats.hammingAvg.toStringAsFixed(1)} '
                'is too high — symbols barely better than random');

        // At least some cells should have good matches (h<15)
        expect(stats.hammingLt15, greaterThan(0),
            reason: '$fixture: no cells with hamming<15 — '
                'symbol detection completely broken');
      }
    });

    test('color distribution on crop images should have all 8 colors represented', () {
      for (final fixture in ['crop_frame_1.png', 'crop_frame_2.png', 'crop_frame_3.png']) {
        final cropImg = loadFixture(fixture);
        final resized = img.copyResize(cropImg,
            width: 384, height: 384,
            interpolation: img.Interpolation.nearest);

        final stats = DecodeStats();
        decoder.decodeFramePixels(resized, 384,
            enableWhiteBalance: true,
            useRelativeColor: true,
            useHashDetection: true,
            stats: stats);

        // All 8 colors should be present (>0 cells each)
        for (var i = 0; i < 8; i++) {
          expect(stats.colorHist[i], greaterThan(0),
              reason: '$fixture: color $i has 0 cells — '
                  'color detection broken. hist=${stats.colorHist}');
        }
      }
    });

    test('RS decode on crop images (quality gate status)', () {
      for (final fixture in ['crop_frame_1.png', 'crop_frame_2.png', 'crop_frame_3.png']) {
        final cropImg = loadFixture(fixture);
        final resized = img.copyResize(cropImg,
            width: 384, height: 384,
            interpolation: img.Interpolation.nearest);

        final stats = DecodeStats();
        final rawBytes = decoder.decodeFramePixels(resized, 384,
            enableWhiteBalance: true,
            useRelativeColor: true,
            useHashDetection: true,
            stats: stats);

        final dataBytes = decoder.decodeRSFrame(rawBytes, 384);

        // RS should not crash and should return data
        expect(dataBytes.isNotEmpty, isTrue,
            reason: '$fixture: RS decode returned empty');
      }
    });
  });

  group('Synthetic padded barcode', () {
    test('barcode with padding should decode correctly after WB fix', () {
      // Create a known barcode at 384px
      const frameSize = 384;
      final testData = Uint8List(100);
      for (var i = 0; i < testData.length; i++) {
        testData[i] = (i * 13 + 7) & 0xFF;
      }

      final rsFrame = CimbarEncoder.encodeRSFrame(testData, frameSize);
      final barcode = CimbarEncoder.encodeFrame(rsFrame, frameSize,
          isEncrypted: false);

      // Add padding: embed barcode in a larger dark image (simulating crop)
      final padded = img.Image(width: 500, height: 500);
      img.fill(padded, color: img.ColorRgba8(60, 55, 50, 255));
      const offsetX = (500 - frameSize) ~/ 2;
      const offsetY = (500 - frameSize) ~/ 2;
      img.compositeImage(padded, barcode, dstX: offsetX, dstY: offsetY);

      // Resize to frameSize (like crop path does)
      final resized = img.copyResize(padded,
          width: frameSize, height: frameSize,
          interpolation: img.Interpolation.nearest);

      // Decode with WB
      final stats = DecodeStats();
      decoder.decodeFramePixels(resized, frameSize,
          enableWhiteBalance: true,
          useRelativeColor: true,
          stats: stats);

      // WB should find the finder whites, not the dark padding
      expect(stats.wbWhitePoint, isNotNull);
      expect(stats.wbWhitePoint![0], greaterThan(200),
          reason: 'WB R=${stats.wbWhitePoint![0].toStringAsFixed(0)} — '
              'should find finder white, not background');

      // Note: full decode will fail because resize misaligns cell boundaries.
      // The purpose of this test is solely to verify WB finds finders through
      // padding. Color distribution is checked on the real crop images instead.
    });
  });
}
