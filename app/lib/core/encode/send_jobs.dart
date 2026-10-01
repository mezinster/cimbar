import 'dart:isolate';
import 'dart:typed_data';

import '../format/cimbar_spec.dart';
import 'gif_writer.dart';
import 'payload_encoder.dart';

const int maxSendFrames = CimbarSpec.codingMaxFrames;
const int maxGifFrames = 500;

class SendRequest {
  final String name;
  final Uint8List bytes;
  final String passphrase;
  const SendRequest(this.name, this.bytes, this.passphrase);
}

/// Isolate entry point (top-level: an Isolate.run closure must not capture a
/// Riverpod notifier — see decode_isolate.dart).
EncodedPayload encodeRequest(SendRequest r) =>
    PayloadEncoder.encode(name: r.name, bytes: r.bytes, passphrase: r.passphrase);

/// Runs [encodeRequest] in a background isolate. Top-level so the closure
/// captures only [r], never a notifier (Dart SDK #52661).
Future<EncodedPayload> encodeInIsolate(SendRequest r) => Isolate.run(() => encodeRequest(r));

/// Builds the GIF in a background isolate; captures only [p] and [delayMs].
Future<Uint8List> buildGifInIsolate(EncodedPayload p, int delayMs) => Isolate.run(() => buildGif(p, delayMs));
