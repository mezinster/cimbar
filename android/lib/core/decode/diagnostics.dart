import 'dart:typed_data';

import '../format/frame_header.dart';

enum DecodeStatus { ok, notLocated, unsupportedGrid, rsFailed, badHeader }

/// Per-frame decode diagnostics, printed as `key=value` pairs by DecodeReport.
class Diagnostics {
  // cells
  int hammingMax = 0;
  double hammingMean = 0;
  double colorMarginMin = double.infinity;
  final List<int> hammingHist = [0, 0, 0, 0]; // <8, <16, <24, >=24
  int sampleMs = 0;
  // rs / header
  int rsBlocks = 0;
  int rsOk = 0;
  int rsFailed = 0;
  int rsMs = 0;
  String headerReason = '';
  String note = '';
  // locate (camera path)
  bool locateRan = false;
  int locateMs = 0;
  int candidates = 0;
  int clusters = 0;
  Float64List? corners; // tlx,tly,trx,try,blx,bly,brx,bry
  double module = 0;
  double tlLuma = 0;
  double secondLuma = 0;
  double devNorm = -1;
  String locateFail = '';
  int gridEstimate = 0;
  List<double>? whitePoint;
  // drift
  bool driftUsed = false;
  int driftMs = 0;
  double driftMeanAbs = 0;
  double driftMaxAbs = 0;
  int driftWidened = 0;

  void addHamming(int h) {
    if (h > hammingMax) hammingMax = h;
    hammingHist[h < 8 ? 0 : (h < 16 ? 1 : (h < 24 ? 2 : 3))]++;
  }

  static String _f(double v, [int d = 2]) => v.toStringAsFixed(d);

  Map<String, String> toMap() => {
        'hammingMax': '$hammingMax',
        'hammingMean': _f(hammingMean),
        'hammingHist': hammingHist.join('/'),
        'colorMarginMin': colorMarginMin == double.infinity ? '-' : _f(colorMarginMin, 3),
        'rsBlocks': '$rsBlocks',
        'rsOk': '$rsOk',
        'rsFailed': '$rsFailed',
        if (headerReason.isNotEmpty) 'headerReason': headerReason,
        if (note.isNotEmpty) 'note': note,
        'sampleMs': '$sampleMs',
        'rsMs': '$rsMs',
        if (locateRan) ...{
          'locateMs': '$locateMs',
          'candidates': '$candidates',
          'clusters': '$clusters',
          'module': _f(module),
          'corners': corners == null ? '-' : [for (var i = 0; i < 8; i += 2) '${_f(corners![i], 1)},${_f(corners![i + 1], 1)}'].join(';'),
          'tlLuma': _f(tlLuma, 0),
          'secondLuma': _f(secondLuma, 0),
          'devNorm': _f(devNorm, 3),
          if (locateFail.isNotEmpty) 'locateFail': locateFail,
          'gridEstimate': '$gridEstimate',
          'wb': whitePoint == null ? '-' : whitePoint!.map((v) => _f(v, 0)).join(','),
        },
        if (driftUsed) ...{
          'driftMs': '$driftMs',
          'driftMeanAbs': _f(driftMeanAbs),
          'driftMaxAbs': _f(driftMaxAbs),
          'driftWidened': '$driftWidened',
        },
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
