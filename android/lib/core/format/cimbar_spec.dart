/// CimBar v2 format constants.
///
/// Mirrors `spec/cimbar-v2.json` (the constants file shared with the web app).
/// `test/core/format/cimbar_spec_test.dart` asserts every value against the JSON,
/// so a change on either side fails the suite. Layout rules that are not
/// constants (bit order, cell order, RS partition, interleave) live in the design
/// spec `docs/superpowers/specs/2026-09-17-cimbar-v2-format-design.md` and in
/// `bit_packing.dart` / `rs_framing.dart`.
class CimbarSpec {
  CimbarSpec._();

  static const int version = 2;

  // Grid
  static const int gridCells = 64;
  static const int cellPx = 8;
  static const int gapPx = 1;
  static const int pitchPx = 9;
  static const int gridPx = 576;
  static const int quietPx = 16;
  static const int framePx = 608;

  // Finders
  static const int finderCells = 7;
  static const int cornerCells = 8;
  static const int finderOuterPx = 63;
  static const int finderRingInsetPx = 9;
  static const int finderCorePx = 27;
  static const int finderCoreInsetPx = 18;
  static const int finderDotPx = 9;
  static const int finderDotInsetPx = 27;
  static const Map<String, List<double>> finderCenters = {
    'tl': [3.5, 3.5],
    'tr': [60.5, 3.5],
    'bl': [3.5, 60.5],
    'br': [60.5, 60.5],
  };
  static const List<String> finderDotOn = ['tr', 'bl', 'br'];

  // Colors
  static const List<List<int>> palette = [
    [0, 255, 0],
    [0, 255, 255],
    [255, 255, 0],
    [255, 85, 255],
  ];

  // Tiles (16 x 8x8, row-major, MSB = top-left) — from spec/cimbar-v2.json, seed 1
  static const List<String> tiles = [
    '3c3cf0f0fcfc0303',
    '00000f0ff3f3f3f3',
    'fcfc33330f0fc0c0',
    'cfcf30303f3f0f0f',
    'cfcf03030000fcfc',
    'cccc0f0f03030f0f',
    'c0c0f3f33c3cf0f0',
    '0303c0c0ccccfcfc',
    '3f3fffffc0c00000',
    '3f3fcccc3333c0c0',
    '30303f3fcfcf0303',
    '0000c0c03f3f3f3f',
    '0f0fc3c3cfcf0303',
    '3c3c3030c0c0ffff',
    '3333f3f33030cfcf',
    '03033c3cfcfccfcf',
  ];

  // Bits
  static const int symbolBits = 4;
  static const int colorBits = 2;
  static const int bitsPerCell = symbolBits + colorBits;

  // Reed-Solomon
  static const int rsBlockTotal = 255;
  static const int rsEccBytes = 64;
  static const String rsInterleave = 'stride-skip-short';

  // Header
  static const int headerLen = 8;

  /// Header flag masks. `spec/cimbar-v2.json` stores bit indices
  /// (encrypted 0, repair 1, compressed 2); these are the masks.
  static const int flagEncrypted = 1;
  static const int flagRepair = 2;
  static const int flagCompressed = 4;

  /// Bits a v2.1 decoder must reject: nothing is defined above bit 2 yet.
  static const int flagReserved = 0xF8;

  // v2.1 coding layer (spec §5): splitmix32-style coefficient generator.
  static const int codingIncrement = 0x9E3779B9;
  static const int codingMixMul1 = 0x85EBCA6B;
  static const int codingMixMul2 = 0xC2B2AE35;

  /// Above this source-frame count a file is uncoded: repair frames are
  /// rejected so a crafted `total` can never force O(n^2) elimination.
  static const int codingMaxFrames = 4096;

  /// Repair frames the GIF encoder ships per source frame.
  static const double gifRepairRatio = 0.25;

  /// Repair frame count for an n-frame file (matches cimbar.js gifRepairCount).
  static int gifRepairCount(int n) => n <= 1 ? 0 : (n * gifRepairRatio).ceil();

  // Capacity
  static const int usableCells = 3840;
  static const int rawBytesPerFrame = 2880;
  static const int dataBytesPerFrame = 2112;
  static const int fileBytesPerFrame = 2104;

  // GIF
  static const int defaultDelayMs = 200;
  static const List<int> delayOptionsMs = [100, 200, 400];

  static bool isReservedCell(int col, int row) {
    final horiz = col < cornerCells || col >= gridCells - cornerCells;
    final vert = row < cornerCells || row >= gridCells - cornerCells;
    return horiz && vert;
  }

  static List<CellPos>? _positions;

  /// Usable cells in row-major order (finder corners skipped). Length 3840.
  static List<CellPos> get usableCellPositions {
    final cached = _positions;
    if (cached != null) return cached;
    final p = <CellPos>[];
    for (var row = 0; row < gridCells; row++) {
      for (var col = 0; col < gridCells; col++) {
        if (!isReservedCell(col, row)) p.add(CellPos(col, row));
      }
    }
    _positions = List.unmodifiable(p);
    return _positions!;
  }

  static int cellOriginX(int col) => quietPx + col * pitchPx;
  static int cellOriginY(int row) => quietPx + row * pitchPx;

  /// RS block sizes for one frame: eleven 255-byte blocks then one 75-byte block.
  static List<int> rsBlockSizes() {
    final sizes = <int>[];
    var total = 0;
    while (total < rawBytesPerFrame) {
      final left = rawBytesPerFrame - total;
      if (left <= rsEccBytes) break;
      final bt = left < rsBlockTotal ? left : rsBlockTotal;
      sizes.add(bt);
      total += bt;
    }
    return sizes;
  }
}

class CellPos {
  final int col;
  final int row;
  const CellPos(this.col, this.row);

  @override
  bool operator ==(Object other) => other is CellPos && other.col == col && other.row == row;

  @override
  int get hashCode => col * 64 + row;

  @override
  String toString() => 'CellPos($col, $row)';
}
