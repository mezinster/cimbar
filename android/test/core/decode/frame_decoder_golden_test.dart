import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rateless_assembler.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/format/rateless.dart';
import 'package:cimbar_scanner/core/services/gif_parser.dart';
import 'package:cimbar_scanner/core/services/payload_decoder.dart';

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

  /// Assemble, decode the payload and check it against the sidecar's file.
  void verifyAssembled(RatelessAssembler asm, GoldenSidecar side, String label) {
    expect(asm.isComplete, isTrue, reason: '$label: rank ${asm.rank}/${asm.total}');
    final f = decodeFramedPayload(asm.framedData(), side.passphrase ?? '', compressed: side.compressed);
    expect(f.fileName, side.fileName, reason: '$label: file name');
    expect(f.fileBytes, side.fileBytes, reason: '$label: file bytes');
  }

  for (final jsonPath in sidecars) {
    test('golden ${jsonPath.split('/').last}: exact decode matches sidecar', () {
      final golden = GoldenSidecar.load(jsonPath);
      final frames = GifParser.parseFrames(File(GoldenSidecar.gifPathFor(jsonPath)).readAsBytesSync());
      expect(frames.length, golden.frameCount);
      expect(golden.sourceFrames + golden.repairFrames, golden.frameCount);
      final decoder = FrameDecoder();
      final asm = RatelessAssembler();
      final decoded = <Uint8List>[];
      for (var i = 0; i < frames.length; i++) {
        final side = golden.frames[i];
        final r = decoder.decodeExact(RgbBuffer.fromImage(frames[i]));
        expect(r.status, DecodeStatus.ok, reason: 'frame $i: ${r.diag.toMap()}');
        expect(r.diag.hammingMax, 0, reason: 'frame $i');
        expect(r.cells, side.cells, reason: 'frame $i cells');
        expect(r.raw, side.raw, reason: 'frame $i raw');
        expect(r.data, side.data, reason: 'frame $i data');
        expect(r.header!.seq, side.header.seq, reason: 'frame $i seq');
        expect(r.header!.fileId, golden.fileId);
        expect(r.header!.total, golden.total);
        expect(r.header!.encrypted, golden.passphrase != null);
        expect(r.header!.repair, side.header.repair, reason: 'frame $i repair flag');
        expect(r.header!.compressed, side.header.compressed, reason: 'frame $i compressed flag');
        expect(r.header!.compressed, golden.compressed, reason: 'frame $i compressed flag');
        expect(r.header!.repair, side.repair, reason: 'frame $i sidecar repair');
        expect(r.diag.rsOk, 12);
        if (side.repair) {
          expect(side.r, side.header.seq, reason: 'frame $i repair id');
          final n = golden.total < 12 ? golden.total : 12;
          expect(side.coef12, Rateless.coefficients(golden.fileId, side.r!, golden.total).sublist(0, n),
              reason: 'frame $i coefficients');
        } else {
          expect(side.coef12, isNull, reason: 'frame $i is a source frame');
        }
        decoded.add(r.data!);
        final add = asm.add(r.data!);
        // Source frames always add information and must be accepted; a repair
        // frame received after the assembler is already full rank is
        // legitimately redundant ('dependent') rather than accepted.
        expect(add.accepted || add.reason == 'dependent', isTrue,
            reason: 'frame $i (repair=${side.repair}) accepted: ${add.accepted}, reason: ${add.reason}');
        if (!side.repair) expect(add.accepted, isTrue, reason: 'frame $i (source) must be accepted: ${add.reason}');
      }
      verifyAssembled(asm, golden, 'all frames');

      if (golden.repairFrames > 0) {
        // (a) source frames only.
        final asmSource = RatelessAssembler();
        for (var i = 0; i < golden.sourceFrames; i++) {
          asmSource.add(decoded[i]);
        }
        verifyAssembled(asmSource, golden, 'source-only');

        // (b) drop every k-th frame (1-indexed), k = frameCount ~/ repairFrames.
        final k = decoded.length ~/ golden.repairFrames;
        final asmDropped = RatelessAssembler();
        var dropped = 0;
        for (var i = 0; i < decoded.length; i++) {
          if ((i + 1) % k == 0) {
            dropped++;
            continue;
          }
          asmDropped.add(decoded[i]);
        }
        expect(dropped, greaterThan(0));
        expect(dropped, lessThanOrEqualTo(golden.repairFrames));
        expect(dropped, greaterThanOrEqualTo(1));
        // At least one dropped frame must be a source frame, or repair rows are untested.
        expect(k, lessThanOrEqualTo(golden.sourceFrames), reason: 'a source frame must be among the dropped');
        verifyAssembled(asmDropped, golden, 'dropped every ${k}th');
      }
    });
  }

  test('the coded goldens are present and carry repair frames', () {
    final coded = sidecars.where((p) => p.contains('lorem_coded')).map(GoldenSidecar.load).toList();
    expect(coded.length, 2, reason: 'lorem_coded and lorem_coded_enc');
    for (final side in coded) {
      expect(side.compressed, isTrue);
      expect(side.repairFrames, greaterThan(0));
      expect(side.frameCount, side.sourceFrames + side.repairFrames);
      expect(side.total, side.sourceFrames);
    }
  });

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
