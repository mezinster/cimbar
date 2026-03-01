/// Constants matching web-app/cimbar.js for interoperability.
class CimbarConstants {
  CimbarConstants._();

  static const int cellSize = 8;
  static const int eccBytes = 64;
  static const int blockTotal = 255;
  static const int blockData = blockTotal - eccBytes; // 191

  /// 8 perceptually distinct colors, matching web-app/cimbar.js and gif-encoder.js.
  static const List<List<int>> colors = [
    [  0, 200, 200],  // 0 - Cyan
    [220,  40,  40],  // 1 - Red
    [ 30, 100, 220],  // 2 - Blue
    [255, 130,  20],  // 3 - Orange
    [200,  40, 200],  // 4 - Magenta
    [ 40, 200,  60],  // 5 - Green
    [230, 220,  40],  // 6 - Yellow
    [100,  20, 200],  // 7 - Indigo
  ];

  /// Supported frame sizes in pixels.
  static const List<int> frameSizes = [128, 192, 256, 384];

  /// CimBar wire format magic bytes.
  static const List<int> magic = [0xCB, 0x42, 0x01, 0x00];

  /// PBKDF2 iterations for key derivation.
  static const int pbkdf2Iterations = 150000;

  /// Usable (non-finder) cells for a given frame size.
  static int usableCells(int frameSize) {
    final cols = frameSize ~/ cellSize;
    final rows = frameSize ~/ cellSize;
    return cols * rows - 36; // four 3x3 finder blocks
  }

  /// Raw byte capacity of a frame (before RS overhead).
  static int rawBytesPerFrame(int frameSize) {
    return (usableCells(frameSize) * 7) ~/ 8;
  }

  /// Effective data bytes per frame (after RS overhead).
  static int dataBytesPerFrame(int frameSize) {
    final raw = rawBytesPerFrame(frameSize);
    final fullBlocks = raw ~/ blockTotal;
    final remainder = raw % blockTotal;
    final partialData = remainder > eccBytes ? remainder - eccBytes : 0;
    return fullBlocks * blockData + partialData;
  }
}
