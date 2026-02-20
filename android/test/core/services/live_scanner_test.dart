import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/constants/cimbar_constants.dart';
import 'package:cimbar_scanner/core/services/live_scanner.dart';
import 'package:cimbar_scanner/core/utils/byte_utils.dart';

const _frameSize = 256;

final _dpf = CimbarConstants.dataBytesPerFrame(_frameSize);

/// Build multi-frame data chunks from a payload.
/// Returns list of frame data chunks (what decodeRSFrame would produce).
List<Uint8List> _buildFrameData(Uint8List payload) {
  final lengthPrefix = writeUint32BE(payload.length);
  final framedData = concatBytes([lengthPrefix, payload]);
  final numFrames = (framedData.length + _dpf - 1) ~/ _dpf;

  final frames = <Uint8List>[];
  for (var f = 0; f < numFrames; f++) {
    final start = f * _dpf;
    final end = min((f + 1) * _dpf, framedData.length);
    final chunk = Uint8List(_dpf);
    chunk.setRange(0, end - start, framedData, start);
    frames.add(chunk);
  }
  return frames;
}

void main() {
  group('LiveScanner', () {
    test('single-frame scan: one frame -> isComplete, correct assembly', () {
      const payloadLen = 100;
      final payload = Uint8List(payloadLen);
      for (var i = 0; i < payloadLen; i++) {
        payload[i] = (i * 11 + 3) & 0xFF;
      }

      final frames = _buildFrameData(payload);
      expect(frames.length, equals(1));

      final scanner = LiveScanner();
      final progress = scanner.processDecodedData(frames[0], _frameSize);

      expect(progress.uniqueFrames, equals(1));
      expect(progress.totalFrames, equals(1));
      expect(progress.isComplete, isTrue);

      final result = scanner.assemble();
      expect(result, isNotNull);
      expect(result!.frameCount, equals(1));

      final recoveredLen = readUint32BE(result.data);
      expect(recoveredLen, equals(payloadLen));

      final recovered = result.data.sublist(4, 4 + payloadLen);
      for (var i = 0; i < payloadLen; i++) {
        expect(recovered[i], equals(payload[i]), reason: 'byte $i mismatch');
      }
    });

    test('multi-frame scan (5 frames): progressive capture + correct assembly', () {
      final payloadLen = 4 * _dpf + 50;
      final payload = Uint8List(payloadLen);
      for (var i = 0; i < payloadLen; i++) {
        payload[i] = (i * 7 + 13) & 0xFF;
      }

      final frames = _buildFrameData(payload);
      expect(frames.length, equals(5));

      final scanner = LiveScanner();

      for (var i = 0; i < frames.length; i++) {
        final progress = scanner.processDecodedData(frames[i], _frameSize);
        expect(progress.uniqueFrames, equals(i + 1));
      }

      expect(scanner.uniqueFrameCount, equals(5));
      expect(scanner.totalFrames, equals(5));

      final result = scanner.assemble();
      expect(result, isNotNull);
      expect(result!.frameCount, equals(5));

      final recoveredLen = readUint32BE(result.data);
      expect(recoveredLen, equals(payloadLen));

      final recovered = result.data.sublist(4, 4 + payloadLen);
      var mismatches = 0;
      for (var i = 0; i < payloadLen; i++) {
        if (recovered[i] != payload[i]) mismatches++;
      }
      expect(mismatches, equals(0));
    });

    test('duplicate handling: same frame twice -> uniqueFrames stays at 1', () {
      const payloadLen = 100;
      final payload = Uint8List(payloadLen);
      for (var i = 0; i < payloadLen; i++) {
        payload[i] = (i * 5) & 0xFF;
      }

      final frames = _buildFrameData(payload);
      final scanner = LiveScanner();

      final p1 = scanner.processDecodedData(frames[0], _frameSize);
      expect(p1.uniqueFrames, equals(1));

      final p2 = scanner.processDecodedData(frames[0], _frameSize);
      expect(p2.uniqueFrames, equals(1)); // still 1
    });

    test('out-of-order with adjacency: feed [2,3,4,0,1] -> correct assembly', () {
      final payloadLen = 4 * _dpf + 50;
      final payload = Uint8List(payloadLen);
      for (var i = 0; i < payloadLen; i++) {
        payload[i] = (i * 3 + 77) & 0xFF;
      }

      final frames = _buildFrameData(payload);
      expect(frames.length, equals(5));

      final scanner = LiveScanner();

      // Feed in order [2,3,4,0,1] — simulating capture across cycles
      // This creates adjacencies: 2->3, 3->4, 4->0, 0->1
      final feedOrder = [2, 3, 4, 0, 1];
      for (final idx in feedOrder) {
        scanner.processDecodedData(frames[idx], _frameSize);
      }

      // We have adjacencies: 2->3, 3->4, 4->0, 0->1
      // Chain from 0: 0->1, but 1->? is unknown
      // Need 1->2 to complete the chain
      // Feed frame 1 again followed by frame 2
      scanner.processDecodedData(frames[1], _frameSize);
      scanner.processDecodedData(frames[2], _frameSize);
      // Now adjacency 1->2 is recorded

      expect(scanner.uniqueFrameCount, equals(5));
      expect(scanner.totalFrames, equals(5));

      final result = scanner.assemble();
      expect(result, isNotNull);

      final recoveredLen = readUint32BE(result!.data);
      expect(recoveredLen, equals(payloadLen));

      final recovered = result.data.sublist(4, 4 + payloadLen);
      var mismatches = 0;
      for (var i = 0; i < payloadLen; i++) {
        if (recovered[i] != payload[i]) mismatches++;
      }
      expect(mismatches, equals(0));
    });

    test('frame 0 detection: correct frame identified', () {
      final payloadLen = 2 * _dpf + 10;
      final payload = Uint8List(payloadLen);
      for (var i = 0; i < payloadLen; i++) {
        payload[i] = (i * 13) & 0xFF;
      }

      final frames = _buildFrameData(payload);
      expect(frames.length, equals(3));

      final scanner = LiveScanner();

      // Feed frame 1 first — should NOT detect as frame 0
      scanner.processDecodedData(frames[1], _frameSize);
      expect(scanner.totalFrames, equals(0));

      // Feed frame 0 — should detect as frame 0
      scanner.processDecodedData(frames[0], _frameSize);
      expect(scanner.totalFrames, equals(3));
    });

    test('dark image (no barcode): processFrame returns null', () {
      final dark = img.Image(width: 256, height: 256);
      img.fill(dark, color: img.ColorRgba8(5, 5, 5, 255));

      final scanner = LiveScanner();
      final progress = scanner.processFrame(dark);

      expect(progress, isNull);
      expect(scanner.uniqueFrameCount, equals(0));
    });

    test('reset() clears all state', () {
      const payloadLen = 100;
      final payload = Uint8List(payloadLen);
      for (var i = 0; i < payloadLen; i++) {
        payload[i] = i & 0xFF;
      }

      final frames = _buildFrameData(payload);
      final scanner = LiveScanner();

      scanner.processDecodedData(frames[0], _frameSize);
      expect(scanner.uniqueFrameCount, equals(1));
      expect(scanner.totalFrames, equals(1));

      scanner.reset();

      expect(scanner.uniqueFrameCount, equals(0));
      expect(scanner.totalFrames, equals(0));
      expect(scanner.detectedFrameSize, isNull);
    });
  });
}
