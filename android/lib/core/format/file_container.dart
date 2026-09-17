import 'dart:convert';
import 'dart:typed_data';

class ParsedFile {
  final String fileName;
  final Uint8List fileBytes;
  const ParsedFile(this.fileName, this.fileBytes);
}

/// The file container shared with the web app (unchanged from v1):
/// framedData = [u32 len][framedPayload]; payload = [u32 nameLen][name][file];
/// framedPayload is the payload or its AES-GCM wire blob starting with CB 42.
class FileContainer {
  FileContainer._();

  static const int maxNameLen = 512;

  static int _u32(Uint8List b, int off) =>
      (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

  static Uint8List stripLengthPrefix(Uint8List framed) {
    if (framed.length < 4) throw const FormatException('missing length prefix');
    final len = _u32(framed, 0);
    if (len < 1 || len > framed.length - 4) {
      throw FormatException('payload length $len is invalid');
    }
    return framed.sublist(4, 4 + len);
  }

  static bool isEncrypted(Uint8List payload) =>
      payload.length >= 2 && payload[0] == 0xCB && payload[1] == 0x42;

  static ParsedFile parsePayload(Uint8List bytes) {
    if (bytes.length < 4) throw const FormatException('payload too short');
    final nameLen = _u32(bytes, 0);
    if (nameLen > maxNameLen || 4 + nameLen > bytes.length) {
      throw FormatException('filename length $nameLen is invalid');
    }
    final name = utf8.decode(bytes.sublist(4, 4 + nameLen));
    return ParsedFile(name, bytes.sublist(4 + nameLen));
  }
}
