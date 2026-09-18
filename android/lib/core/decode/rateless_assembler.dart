import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import '../format/frame_header.dart';
import '../format/rateless.dart';
import '../services/galois_field.dart';

class AddResult {
  final bool accepted;
  final String reason;
  final FrameHeader? header;
  const AddResult(this.accepted, this.reason, this.header);
}

/// One stored row: `coef == null` is the unmaterialised unit vector e_pivot —
/// an uncoded source frame that has never needed arithmetic.
class _Row {
  final Uint8List? coef;
  final Uint8List body;
  _Row(this.coef, this.body);
}

/// Recovers the N source bodies from any N linearly independent rows (source
/// and/or repair frames) by incremental Gaussian elimination over GF(256)
/// (spec §7). Dart port of web-app/rateless.js `RatelessAssembler`.
///
/// Memory: a source frame whose pivot column is still free is stored as the
/// implicit unit vector e_seq with no O(n) coefficient array; only a row that
/// needs real arithmetic (a repair frame, or a source frame whose column a
/// repair pivot already occupies) is materialised to a dense `Uint8List(n)`.
/// That keeps an all-source file (`total` up to 65535) at O(n) memory. A
/// `total` above [CimbarSpec.codingMaxFrames] additionally rejects repair
/// frames outright (reason `uncoded`), so a crafted large `total` can never
/// force dense elimination at all.
///
/// Counters count mutually exclusive per-frame outcomes: [sourceCount] and
/// [repairCount] count ACCEPTED rows of that kind only (a row rejected as
/// duplicate, dependent or uncoded is not counted there).
///
/// Reasons match web-app/rateless.js: 'rs', the header reasons, 'total',
/// 'flags', 'uncoded', 'duplicate', 'dependent'; '' when accepted.
class RatelessAssembler {
  int? fileId;
  int total = 0;
  bool encrypted = false;
  bool compressed = false;
  int rank = 0;
  int sourceCount = 0;
  int repairCount = 0;
  int duplicateCount = 0;
  int dependentCount = 0;

  List<_Row?> _pivots = const [];
  final Set<int> _seenSource = {};
  final Set<int> _seenRepair = {};
  List<Uint8List>? _bodies;

  void reset() {
    fileId = null;
    total = 0;
    encrypted = false;
    compressed = false;
    rank = 0;
    sourceCount = 0;
    repairCount = 0;
    duplicateCount = 0;
    dependentCount = 0;
    _pivots = const [];
    _seenSource.clear();
    _seenRepair.clear();
    _bodies = null;
  }

  /// Stored pivots holding a materialised (dense) coefficient array — for
  /// tests and diagnostics only.
  int get denseRows {
    var n = 0;
    for (final p in _pivots) {
      if (p != null && p.coef != null) n++;
    }
    return n;
  }

  /// data: dataBytesPerFrame bytes after RS decode; blocksFailed: from RsFraming.
  AddResult add(Uint8List data, {int blocksFailed = 0}) {
    if (blocksFailed > 0) return const AddResult(false, 'rs', null);
    final hd = FrameHeader.decode(data);
    if (!hd.valid) return AddResult(false, hd.reason, hd.header);
    final h = hd.header!;
    if (fileId != null && h.fileId != fileId) reset();
    if (fileId != null && h.total != total) return AddResult(false, 'total', h);
    if (fileId != null && (h.encrypted != encrypted || h.compressed != compressed)) {
      return AddResult(false, 'flags', h);
    }
    if (fileId == null) {
      fileId = h.fileId;
      total = h.total;
      encrypted = h.encrypted;
      compressed = h.compressed;
      _pivots = List<_Row?>.filled(h.total, null);
    }
    final n = total;
    // Decoder-side guard: an uncoded (all-source) file can claim any total up
    // to 65535 at no coding cost; a repair frame on such a file would force
    // O(n) dense arrays per row for a file the encoder never coded.
    if (h.repair && n > CimbarSpec.codingMaxFrames) return AddResult(false, 'uncoded', h);
    final seen = h.repair ? _seenRepair : _seenSource;
    if (!seen.add(h.seq)) {
      duplicateCount++;
      return AddResult(false, 'duplicate', h);
    }
    final body = data.sublist(CimbarSpec.headerLen,
        CimbarSpec.headerLen + CimbarSpec.fileBytesPerFrame); // copy: caller may reuse its buffer

    if (!h.repair && _pivots[h.seq] == null) {
      // Fast path: source frame, free column — the unit vector e_seq, with no
      // coefficient array ever allocated.
      _pivots[h.seq] = _Row(null, body);
      rank++;
      sourceCount++;
      _bodies = null;
      return AddResult(true, '', h);
    }

    if (rank >= n) {
      dependentCount++;
      return AddResult(false, 'dependent', h);
    }
    final Uint8List coef;
    if (h.repair) {
      coef = Rateless.coefficients(h.fileId, h.seq, n);
    } else {
      coef = Uint8List(n);
      coef[h.seq] = 1;
    }
    final row = _Row(coef, body);
    // forward elimination against existing pivots
    for (var c = 0; c < n; c++) {
      final v = coef[c];
      final p = _pivots[c];
      if (v == 0 || p == null) continue;
      _subtractScaled(row, p, v, c);
    }
    var p = -1;
    for (var c = 0; c < n; c++) {
      if (coef[c] != 0) {
        p = c;
        break;
      }
    }
    if (p < 0) {
      dependentCount++;
      return AddResult(false, 'dependent', h);
    }
    _scaleRow(row, GaloisField.gfInv(coef[p]), p);
    _pivots[p] = row;
    rank++;
    if (h.repair) {
      repairCount++;
    } else {
      sourceCount++;
    }
    _bodies = null;
    return AddResult(true, '', h);
  }

  bool get isComplete => total > 0 && rank == total;

  /// Back-substitute (once) and return the N bodies concatenated (still
  /// carrying the u32 length prefix + padding).
  Uint8List framedData() {
    if (!isComplete) throw StateError('Incomplete: rank $rank/$total');
    var bodies = _bodies;
    if (bodies == null) {
      for (var c = total - 1; c >= 0; c--) {
        final pr = _pivots[c]!;
        final pc = pr.coef;
        if (pc == null) continue; // already the unit vector e_c — nothing to reduce
        for (var k = c + 1; k < total; k++) {
          final v = pc[k];
          if (v != 0) _subtractScaled(pr, _pivots[k]!, v, k);
        }
      }
      bodies = [for (var i = 0; i < total; i++) _pivots[i]!.body];
      _bodies = bodies;
    }
    const per = CimbarSpec.fileBytesPerFrame;
    final out = Uint8List(per * total);
    for (var i = 0; i < total; i++) {
      out.setRange(i * per, (i + 1) * per, bodies[i]);
    }
    return out;
  }

  /// row -= c * pivot, over coefficients from column [from] and the whole body.
  /// [row] is always a materialised (dense) row. `pivot.coef == null` means the
  /// pivot is the unit vector e_from, so the subtraction only zeroes
  /// `row.coef[from]` — no dense pivot array is read or allocated.
  static void _subtractScaled(_Row row, _Row pivot, int c, int from) {
    final rb = row.body, pb = pivot.body;
    final rc = row.coef!;
    final pc = pivot.coef;
    if (pc == null) {
      rc[from] = 0;
      if (c == 1) {
        for (var i = 0; i < rb.length; i++) {
          rb[i] ^= pb[i];
        }
      } else {
        for (var i = 0; i < rb.length; i++) {
          if (pb[i] != 0) rb[i] ^= GaloisField.gfMul(c, pb[i]);
        }
      }
      return;
    }
    if (c == 1) {
      for (var k = from; k < rc.length; k++) {
        rc[k] ^= pc[k];
      }
      for (var i = 0; i < rb.length; i++) {
        rb[i] ^= pb[i];
      }
    } else {
      for (var k = from; k < rc.length; k++) {
        if (pc[k] != 0) rc[k] ^= GaloisField.gfMul(c, pc[k]);
      }
      for (var i = 0; i < rb.length; i++) {
        if (pb[i] != 0) rb[i] ^= GaloisField.gfMul(c, pb[i]);
      }
    }
  }

  static void _scaleRow(_Row row, int inv, int from) {
    if (inv == 1) return;
    final rc = row.coef!;
    for (var k = from; k < rc.length; k++) {
      if (rc[k] != 0) rc[k] = GaloisField.gfMul(inv, rc[k]);
    }
    final rb = row.body;
    for (var i = 0; i < rb.length; i++) {
      if (rb[i] != 0) rb[i] = GaloisField.gfMul(inv, rb[i]);
    }
  }
}
