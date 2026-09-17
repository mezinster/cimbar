import 'dart:typed_data';

import '../services/reed_solomon.dart';
import 'cimbar_spec.dart';

class RsFrameResult {
  final Uint8List data;
  final int blocksOk;
  final int blocksFailed;
  const RsFrameResult(this.data, this.blocksOk, this.blocksFailed);
}

/// RS block partition and byte-stride interleaving for one frame.
///
/// Interleave rule (spec §4.3, "stride-skip-short"): for j from 0 to the
/// largest block size - 1, for i from 0 to N - 1, append byte j of block i if
/// block i has a byte j. With sizes [255 x 11, 75] the position is j*12+i for
/// j < 75 and 900 + (j-75)*11 + i afterwards.
class RsFraming {
  RsFraming._();

  static Uint8List encodeFrame(Uint8List data, ReedSolomon rs) {
    if (data.length > CimbarSpec.dataBytesPerFrame) {
      throw ArgumentError('frame data ${data.length} > ${CimbarSpec.dataBytesPerFrame} bytes');
    }
    final sizes = CimbarSpec.rsBlockSizes();
    final blocks = <Uint8List>[];
    var off = 0;
    for (final bt in sizes) {
      final bd = bt - CimbarSpec.rsEccBytes;
      final chunk = Uint8List(bd);
      final take = (data.length - off).clamp(0, bd);
      if (take > 0) chunk.setRange(0, take, data, off);
      off += take;
      blocks.add(rs.encode(chunk));
    }
    return _interleave(blocks, CimbarSpec.rawBytesPerFrame);
  }

  static Uint8List _interleave(List<Uint8List> blocks, int rawLen) {
    final out = Uint8List(rawLen);
    var maxLen = 0;
    for (final b in blocks) {
      if (b.length > maxLen) maxLen = b.length;
    }
    var pos = 0;
    for (var j = 0; j < maxLen; j++) {
      for (var i = 0; i < blocks.length; i++) {
        if (j < blocks[i].length) out[pos++] = blocks[i][j];
      }
    }
    return out;
  }

  static RsFrameResult decodeFrame(Uint8List raw, ReedSolomon rs) {
    final sizes = CimbarSpec.rsBlockSizes();
    final n = sizes.length;
    final blocks = [for (final s in sizes) Uint8List(s)];
    var maxLen = 0;
    for (final s in sizes) {
      if (s > maxLen) maxLen = s;
    }
    var pos = 0;
    for (var j = 0; j < maxLen; j++) {
      for (var i = 0; i < n; i++) {
        if (j < sizes[i]) {
          blocks[i][j] = pos < raw.length ? raw[pos] : 0;
          pos++;
        }
      }
    }
    final data = Uint8List(CimbarSpec.dataBytesPerFrame);
    var off = 0;
    var ok = 0;
    var failed = 0;
    for (var i = 0; i < n; i++) {
      final bd = sizes[i] - CimbarSpec.rsEccBytes;
      try {
        final dec = rs.decode(blocks[i]);
        data.setRange(off, off + bd, dec);
        ok++;
      } catch (_) {
        failed++;
      }
      off += bd;
    }
    return RsFrameResult(data, ok, failed);
  }
}
