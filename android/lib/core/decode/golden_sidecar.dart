import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../format/frame_header.dart';

/// One frame of ground truth from test-data/goldens/<name>.json.
class GoldenFrame {
  final int seq;
  final FrameHeader header;
  final Uint8List data; // 2112 protected bytes incl. header, pre-RS
  final Uint8List raw; // 2880 bytes after RS encode + interleave
  final Uint8List cells; // 3840 values (symbol << 2) | color
  final bool repair; // v2.1: this frame is a repair row
  final int? r; // v2.1: repair id (== header.seq) on a repair frame
  final List<int>? coef12; // v2.1: first min(12, total) coefficients of that row
  const GoldenFrame(this.seq, this.header, this.data, this.raw, this.cells,
      {this.repair = false, this.r, this.coef12});
}

/// Loader for the golden sidecars (schema: test-data/goldens/README.md).
class GoldenSidecar {
  final String name;
  final String fileName;
  final Uint8List fileBytes;
  final String? passphrase;
  final int fileId;
  final int total;
  final int delayMs;
  final int framedDataLength;

  /// v2.1 fields; a v2 sidecar that predates them decodes with the defaults
  /// below (uncompressed, no repair frames, one GIF frame per source frame).
  final bool compressed;
  final int sourceFrames;
  final int repairFrames;
  final int frameCount;
  final List<GoldenFrame> frames;

  const GoldenSidecar({
    required this.name,
    required this.fileName,
    required this.fileBytes,
    required this.passphrase,
    required this.fileId,
    required this.total,
    required this.delayMs,
    required this.framedDataLength,
    required this.compressed,
    required this.sourceFrames,
    required this.repairFrames,
    required this.frameCount,
    required this.frames,
  });

  static GoldenSidecar load(String jsonPath) {
    final m = jsonDecode(File(jsonPath).readAsStringSync()) as Map<String, dynamic>;
    final frames = (m['frames'] as List).map((e) {
      final f = e as Map<String, dynamic>;
      final h = f['header'] as Map<String, dynamic>;
      return GoldenFrame(
        f['seq'] as int,
        FrameHeader(
          version: h['version'] as int,
          encrypted: h['encrypted'] as bool,
          repair: h['repair'] as bool? ?? false,
          compressed: h['compressed'] as bool? ?? false,
          fileId: h['fileId'] as int,
          seq: h['seq'] as int,
          total: h['total'] as int,
        ),
        hexToBytes(f['dataHex'] as String),
        hexToBytes(f['rawHex'] as String),
        Uint8List.fromList((f['cells'] as List).cast<int>()),
        repair: f['repair'] as bool? ?? false,
        r: f['r'] as int?,
        coef12: (f['coef12'] as List?)?.cast<int>(),
      );
    }).toList(growable: false);
    return GoldenSidecar(
      name: m['name'] as String,
      fileName: m['fileName'] as String,
      fileBytes: base64Decode(m['fileBytesBase64'] as String),
      passphrase: m['passphrase'] as String?,
      fileId: m['fileId'] as int,
      total: m['total'] as int,
      delayMs: m['delayMs'] as int,
      framedDataLength: m['framedDataLength'] as int,
      compressed: m['compressed'] as bool? ?? false,
      sourceFrames: m['sourceFrames'] as int? ?? (m['total'] as int),
      repairFrames: m['repairFrames'] as int? ?? 0,
      frameCount: m['frameCount'] as int? ?? (m['total'] as int),
      frames: frames,
    );
  }

  /// Path of the sibling .gif for this sidecar.
  static String gifPathFor(String jsonPath) => jsonPath.replaceAll(RegExp(r'\.json$'), '.gif');

  static Uint8List hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
