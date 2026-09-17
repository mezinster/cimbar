import 'dart:typed_data';

import '../format/frame_header.dart';

enum DecodeStatus { ok, notLocated, unsupportedGrid, rsFailed, badHeader }

/// Per-frame decode diagnostics, printed as `key=value` pairs by DecodeReport.
class Diagnostics {
  int hammingMax = 0;
  double hammingMean = 0;
  double colorMarginMin = double.infinity;
  final List<int> hammingHist = [0, 0, 0, 0]; // <8, <16, <24, >=24
  int rsBlocks = 0;
  int rsOk = 0;
  int rsFailed = 0;
  String headerReason = '';
  String note = '';
  int sampleMs = 0;
  int rsMs = 0;

  void addHamming(int h) {
    if (h > hammingMax) hammingMax = h;
    hammingHist[h < 8 ? 0 : (h < 16 ? 1 : (h < 24 ? 2 : 3))]++;
  }

  Map<String, String> toMap() => {
        'hammingMax': '$hammingMax',
        'hammingMean': hammingMean.toStringAsFixed(2),
        'hammingHist': hammingHist.join('/'),
        'colorMarginMin': colorMarginMin == double.infinity ? '-' : colorMarginMin.toStringAsFixed(3),
        'rsBlocks': '$rsBlocks',
        'rsOk': '$rsOk',
        'rsFailed': '$rsFailed',
        if (headerReason.isNotEmpty) 'headerReason': headerReason,
        if (note.isNotEmpty) 'note': note,
        'sampleMs': '$sampleMs',
        'rsMs': '$rsMs',
      };
}

class FrameResult {
  final DecodeStatus status;
  final Uint8List? cells;
  final Uint8List? raw;
  final Uint8List? data;
  final FrameHeader? header;
  final Diagnostics diag;

  const FrameResult({
    required this.status,
    required this.diag,
    this.cells,
    this.raw,
    this.data,
    this.header,
  });

  bool get isOk => status == DecodeStatus.ok;
}
