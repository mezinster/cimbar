import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../decode/diagnostics.dart';
import '../decode/frame_decoder.dart';
import '../decode/rgb_buffer.dart';
import '../decode/yuv_frame.dart';

export '../decode/yuv_frame.dart' show RoiHint;

/// One camera frame to decode.
class FrameJob {
  final YuvFrame frame;
  final bool useDrift;
  final RoiHint? hint;
  final bool capture;
  const FrameJob({required this.frame, this.useDrift = true, this.hint, this.capture = false});
}

/// Everything the UI and assembler need from one decoded frame.
class FrameOutcome {
  final DecodeStatus status;
  final Uint8List? data;
  final int blocksFailed;
  final int? fileId;
  final int? seq;
  final int? total;
  final bool? encrypted;
  final Float64List? corners;
  final double module;
  final List<int>? roi;
  final Map<String, String> diag;
  final int totalMs;
  final int width;
  final int height;
  final Uint8List? capturePng;

  const FrameOutcome({
    required this.status,
    required this.data,
    required this.blocksFailed,
    this.fileId,
    this.seq,
    this.total,
    this.encrypted,
    required this.corners,
    required this.module,
    required this.roi,
    required this.diag,
    required this.totalMs,
    required this.width,
    required this.height,
    this.capturePng,
  });

  bool get located => corners != null;
}

/// Runs [FrameDecoder.decodeYuv420] in one long-lived background isolate.
/// One job at a time: callers drop frames while [busy].
class DecodeIsolate {
  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  Completer<FrameOutcome>? _pending;

  DecodeIsolate._(this._isolate, this._toWorker, this._fromWorker) {
    _fromWorker.listen((msg) {
      final p = _pending;
      _pending = null;
      if (p == null) return;
      if (msg is FrameOutcome) {
        p.complete(msg);
      } else {
        p.completeError(StateError('decode isolate error: $msg'));
      }
    });
  }

  static Future<DecodeIsolate> spawn() async {
    final handshake = ReceivePort();
    final isolate = await Isolate.spawn(_worker, handshake.sendPort);
    final toWorker = await handshake.first as SendPort;
    handshake.close();
    final fromWorker = ReceivePort();
    toWorker.send(fromWorker.sendPort);
    return DecodeIsolate._(isolate, toWorker, fromWorker);
  }

  bool get busy => _pending != null;

  Future<FrameOutcome> decode(FrameJob job) {
    if (_pending != null) throw StateError('DecodeIsolate is busy');
    final c = Completer<FrameOutcome>();
    _pending = c;
    _toWorker.send(job);
    return c.future;
  }

  void dispose() {
    _fromWorker.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  static void _worker(SendPort handshake) {
    final inbox = ReceivePort();
    handshake.send(inbox.sendPort);
    SendPort? out;
    final decoder = FrameDecoder();
    inbox.listen((msg) {
      if (msg is SendPort) {
        out = msg;
        return;
      }
      if (msg is FrameJob) {
        try {
          out!.send(runJob(decoder, msg));
        } catch (e) {
          out!.send('$e');
        }
      }
    });
  }

  /// Decode one job (also used directly by tests and the photo path).
  static FrameOutcome runJob(FrameDecoder decoder, FrameJob job) {
    final sw = Stopwatch()..start();
    final r = decoder.decodeYuv420(job.frame, useDrift: job.useDrift, hint: job.hint);
    Uint8List? png;
    if (job.capture) {
      final rgb = RgbBuffer.fromYuv420(job.frame);
      final im = img.Image(width: rgb.width, height: rgb.height);
      var i = 0;
      for (var y = 0; y < rgb.height; y++) {
        for (var x = 0; x < rgb.width; x++) {
          im.setPixelRgb(x, y, rgb.rgb[i], rgb.rgb[i + 1], rgb.rgb[i + 2]);
          i += 3;
        }
      }
      png = img.encodePng(im);
    }
    final h = r.header;
    return FrameOutcome(
      status: r.status,
      data: r.data,
      blocksFailed: r.diag.rsFailed,
      fileId: h?.fileId,
      seq: h?.seq,
      total: h?.total,
      encrypted: h?.encrypted,
      corners: r.diag.corners,
      module: r.diag.module,
      roi: r.diag.roi,
      diag: r.diag.toMap(),
      totalMs: sw.elapsedMilliseconds,
      width: job.frame.width,
      height: job.frame.height,
      capturePng: png,
    );
  }
}
