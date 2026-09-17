import 'dart:typed_data';

import 'cimbar_spec.dart';

/// The 8-byte frame header at the start of every frame's RS-protected data.
/// `[ver 0x02][flags bit0=encrypted][fileId u16 BE][seq u16 BE][total u16 BE]`
class FrameHeader {
  final int version;
  final bool encrypted;
  final int fileId;
  final int seq;
  final int total;

  const FrameHeader({
    required this.version,
    required this.encrypted,
    required this.fileId,
    required this.seq,
    required this.total,
  });

  Uint8List encode() {
    final b = Uint8List(CimbarSpec.headerLen);
    b[0] = version;
    b[1] = encrypted ? 1 : 0;
    b[2] = (fileId >> 8) & 0xFF;
    b[3] = fileId & 0xFF;
    b[4] = (seq >> 8) & 0xFF;
    b[5] = seq & 0xFF;
    b[6] = (total >> 8) & 0xFF;
    b[7] = total & 0xFF;
    return b;
  }

  /// Decode and validate. Reasons match web-app/format.js decodeHeader:
  /// 'short', 'version', 'flags', 'total', 'seq'; '' when valid.
  static HeaderDecode decode(Uint8List bytes) {
    if (bytes.length < CimbarSpec.headerLen) return const HeaderDecode(null, 'short');
    final version = bytes[0];
    final flags = bytes[1];
    final h = FrameHeader(
      version: version,
      encrypted: (flags & 1) == 1,
      fileId: (bytes[2] << 8) | bytes[3],
      seq: (bytes[4] << 8) | bytes[5],
      total: (bytes[6] << 8) | bytes[7],
    );
    if (version != CimbarSpec.version) return HeaderDecode(h, 'version');
    if ((flags & 0xFE) != 0) return HeaderDecode(h, 'flags');
    if (h.total < 1) return HeaderDecode(h, 'total');
    if (h.seq >= h.total) return HeaderDecode(h, 'seq');
    return HeaderDecode(h, '');
  }

  @override
  String toString() =>
      'FrameHeader(v$version enc=$encrypted fileId=0x${fileId.toRadixString(16)} seq=$seq total=$total)';
}

class HeaderDecode {
  final FrameHeader? header;
  final String reason;
  const HeaderDecode(this.header, this.reason);
  bool get valid => reason.isEmpty;
}
