import 'dart:convert';
import 'dart:typed_data';

/// The text-message convention (spec 2026-10-01 §3), shared with
/// `isTextMessage`/`decodeTextMessage`/`textMessageName` in web-app/cimbar.js
/// and pinned by test-data/text-message.json: an ordinary container whose
/// name ends in .txt and whose bytes are strict UTF-8 of at most [maxBytes].
class TextMessage {
  TextMessage._();

  static const int maxBytes = 1048576;

  /// The text (one leading BOM dropped), or null when this is not a text message.
  static String? decode(String name, Uint8List bytes) {
    if (!name.toLowerCase().endsWith('.txt') || bytes.length > maxBytes) return null;
    try {
      // Dart's strict decoder rejects overlong forms, surrogates and
      // truncated tails exactly like TextDecoder(fatal: true), and drops one
      // leading BOM (like TextDecoder's default ignoreBOM=false).
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  static bool isTextMessage(String name, Uint8List bytes) => decode(name, bytes) != null;

  static String fileName(DateTime now) {
    String p(int n) => n.toString().padLeft(2, '0');
    return 'message-${now.year}${p(now.month)}${p(now.day)}-'
        '${p(now.hour)}${p(now.minute)}${p(now.second)}.txt';
  }
}
