import 'dart:convert' show utf8;
import 'dart:io' show ZLibCodec;
import 'dart:math' as math;
import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import '../format/file_container.dart';
import '../services/crypto_service.dart';

/// A file ready for framing: the framed data split into N source bodies.
class EncodedPayload {
  final int fileId;
  final bool encrypted;
  final bool compressed;
  final int framedLength;
  final List<Uint8List> bodies; // each CimbarSpec.fileBytesPerFrame bytes, zero padded
  EncodedPayload({required this.fileId, required this.encrypted, required this.compressed,
      required this.framedLength, required this.bodies});
  int get total => bodies.length;
}

/// Encode side of the container (port of startEncode in web-app/index.html and
/// compress.js maybeDeflate): container → deflate if it saves ≥ 5% → optional
/// AES-GCM → length prefix → split into source bodies.
class PayloadEncoder {
  PayloadEncoder._();

  static bool shouldCompress(int original, int deflated) =>
      original > 0 && deflated <= (original * (1 - CimbarSpec.compressionMinSaving)).floor();

  static EncodedPayload encode({
    required String name,
    required Uint8List bytes,
    String passphrase = '',
    int? fileId,
    bool allowCompression = true,
    Uint8List? salt,
    Uint8List? iv,
    int maxContainerBytes = CimbarSpec.maxInflatedBytes,
  }) {
    // Receivers refuse to inflate past CimbarSpec.maxInflatedBytes, and an
    // uncompressed container that size could not be parsed by them either:
    // refuse before doing any work. (The parameter lets tests lower the cap.)
    final containerLen = 4 + utf8.encode(name).length + bytes.length;
    if (containerLen > maxContainerBytes) {
      throw ArgumentError('file container is $containerLen bytes (max $maxContainerBytes)');
    }
    final container = FileContainer.buildPayload(name, bytes);
    var body = container;
    var compressed = false;
    if (allowCompression && container.isNotEmpty) {
      final d = Uint8List.fromList(ZLibCodec().encode(container));
      if (shouldCompress(container.length, d.length)) {
        body = d;
        compressed = true;
      }
    }
    final encrypted = passphrase.isNotEmpty;
    if (encrypted) body = CryptoService.encrypt(body, passphrase, salt: salt, iv: iv);
    final framed = FileContainer.withLengthPrefix(body);

    const per = CimbarSpec.fileBytesPerFrame;
    final total = math.max(1, (framed.length + per - 1) ~/ per);
    if (total > 65535) throw ArgumentError('needs $total frames (max 65535)');
    final bodies = List<Uint8List>.generate(total, (seq) {
      final b = Uint8List(per);
      final start = seq * per;
      final end = math.min(framed.length, start + per);
      if (end > start) b.setRange(0, end - start, framed, start);
      return b;
    });
    return EncodedPayload(
      fileId: fileId ?? math.Random.secure().nextInt(0x10000),
      encrypted: encrypted,
      compressed: compressed,
      framedLength: framed.length,
      bodies: bodies,
    );
  }
}
