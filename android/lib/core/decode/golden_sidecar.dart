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
  const GoldenFrame(this.seq, this.header, this.data, this.raw, this.cells);
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
          fileId: h['fileId'] as int,
          seq: h['seq'] as int,
          total: h['total'] as int,
        ),
        hexToBytes(f['dataHex'] as String),
        hexToBytes(f['rawHex'] as String),
        Uint8List.fromList((f['cells'] as List).cast<int>()),
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
