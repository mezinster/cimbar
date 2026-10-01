import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import '../format/frame_header.dart';
import '../format/rateless.dart';
import 'payload_encoder.dart';

class RepairFrame {
  final Uint8List data; // 2112 bytes: header + combined body
  final int r; // repair id used
  final int nextR; // repair id to try next
  const RepairFrame(this.data, this.r, this.nextR);
}

/// Source and repair frames (port of splitIntoFrames/repairFrame and the
/// repair-id loop in startEncode, web-app/cimbar.js + index.html).
class FrameBuilder {
  FrameBuilder._();

  static Uint8List _frame(EncodedPayload p, {required bool repair, required int seq, required Uint8List body}) {
    final f = Uint8List(CimbarSpec.dataBytesPerFrame);
    f.setRange(0, CimbarSpec.headerLen, FrameHeader(
      version: CimbarSpec.version, encrypted: p.encrypted, repair: repair,
      compressed: p.compressed, fileId: p.fileId, seq: seq, total: p.total).encode());
    f.setRange(CimbarSpec.headerLen, CimbarSpec.headerLen + body.length, body);
    return f;
  }

  static Uint8List sourceFrame(EncodedPayload p, int seq) =>
      _frame(p, repair: false, seq: seq, body: p.bodies[seq]);

  /// The first usable repair frame at id >= [fromR] (mod 65536): an all-zero
  /// coefficient row carries nothing and is skipped, as the web encoder does.
  static RepairFrame nextRepair(EncodedPayload p, int fromR) {
    var r = fromR & 0xFFFF;
    for (var misses = 0; misses < 64; misses++) {
      final coef = Rateless.coefficients(p.fileId, r, p.total);
      if (coef.any((c) => c != 0)) {
        final body = Rateless.combine(p.bodies, coef);
        return RepairFrame(_frame(p, repair: true, seq: r, body: body), r, (r + 1) & 0xFFFF);
      }
      r = (r + 1) & 0xFFFF;
    }
    throw StateError('no usable repair id');
  }

  /// N source frames, then gifRepairCount(N) repair frames when coding applies.
  static List<Uint8List> gifFrames(EncodedPayload p) => gifFrameStream(p).toList();

  /// [gifFrames], built lazily: each frame is made only when iterated to.
  static Iterable<Uint8List> gifFrameStream(EncodedPayload p) sync* {
    for (var s = 0; s < p.total; s++) {
      yield sourceFrame(p, s);
    }
    if (p.total > 1 && p.total <= CimbarSpec.codingMaxFrames) {
      var r = 0;
      for (var i = 0; i < CimbarSpec.gifRepairCount(p.total); i++) {
        final rf = nextRepair(p, r);
        yield rf.data;
        r = rf.nextR;
      }
    }
  }
}
