import 'dart:typed_data';

/// Concatenate multiple byte lists into a single Uint8List.
Uint8List concatBytes(List<Uint8List> arrays) {
  final total = arrays.fold<int>(0, (sum, a) => sum + a.length);
  final result = Uint8List(total);
  var offset = 0;
  for (final a in arrays) {
    result.setRange(offset, offset + a.length, a);
    offset += a.length;
  }
  return result;
}

/// Read a 4-byte big-endian unsigned integer from [data] at [offset].
int readUint32BE(Uint8List data, [int offset = 0]) {
  return (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];
}

/// Write a 4-byte big-endian unsigned integer.
Uint8List writeUint32BE(int value) {
  return Uint8List.fromList([
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ]);
}

/// Convert bytes to hex string for debugging.
String bytesToHex(Uint8List data) {
  return data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
