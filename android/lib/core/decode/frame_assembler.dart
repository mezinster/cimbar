import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import '../format/frame_header.dart';
import 'rateless_assembler.dart' show AddResult;

// AddResult now lives in rateless_assembler.dart (the v2.1 assembler that
// replaces this one); re-exported so existing importers keep compiling.
export 'rateless_assembler.dart' show AddResult;

/// Sequence-slot frame assembly (spec §4.4) with the §4.2 acceptance rules.
/// Reasons match web-app/cimbar.js FrameAssembler: 'rs', header reasons,
/// 'total', 'duplicate'; '' when accepted.
class FrameAssembler {
  int? fileId;
  int total = 0;
  bool encrypted = false;
  int filled = 0;
  List<Uint8List?> _slots = const [];

  void reset() {
    fileId = null;
    total = 0;
    encrypted = false;
    filled = 0;
    _slots = const [];
  }

  /// data: dataBytesPerFrame bytes after RS decode; blocksFailed: from RsFraming.
  AddResult add(Uint8List data, {int blocksFailed = 0}) {
    if (blocksFailed > 0) return const AddResult(false, 'rs', null);
    final hd = FrameHeader.decode(data);
    if (!hd.valid) return AddResult(false, hd.reason, hd.header);
    final h = hd.header!;
    if (fileId != null && h.fileId != fileId) reset();
    if (fileId != null && h.total != total) return AddResult(false, 'total', h);
    if (fileId == null) {
      fileId = h.fileId;
      total = h.total;
      encrypted = h.encrypted;
      _slots = List<Uint8List?>.filled(h.total, null);
    }
    if (_slots[h.seq] != null) return AddResult(false, 'duplicate', h);
    _slots[h.seq] = data.sublist(CimbarSpec.headerLen); // copy: caller may reuse its buffer
    filled++;
    return AddResult(true, '', h);
  }

  bool get isComplete => total > 0 && filled == total;

  List<int> missingSeqs() => [
        for (var i = 0; i < total; i++)
          if (_slots[i] == null) i,
      ];

  /// Concatenated frame bodies (still carrying the u32 length prefix + padding).
  Uint8List framedData() {
    if (!isComplete) throw StateError('Incomplete: $filled/$total frames');
    const per = CimbarSpec.fileBytesPerFrame;
    final out = Uint8List(per * total);
    for (var i = 0; i < total; i++) {
      out.setRange(i * per, (i + 1) * per, _slots[i]!);
    }
    return out;
  }
}
