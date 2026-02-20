import 'dart:typed_data';

/// Progress update emitted during decode pipeline stages.
class DecodeProgress {
  final DecodeState state;
  final double progress; // 0.0 to 1.0
  final String? message;

  const DecodeProgress({
    required this.state,
    this.progress = 0.0,
    this.message,
  });
}

enum DecodeState {
  parsingGif,
  decodingFrames,
  reedSolomonDecode,
  decrypting,
  done,
  error,
}

/// Final result of a successful decode.
class DecodeResult {
  final String filename;
  final Uint8List data;

  const DecodeResult({required this.filename, required this.data});
}
