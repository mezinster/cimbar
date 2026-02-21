/// Bounding box of a detected barcode region in source image coordinates.
class BarcodeRect {
  final int x;
  final int y;
  final int width;
  final int height;

  const BarcodeRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BarcodeRect &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => Object.hash(x, y, width, height);
}
