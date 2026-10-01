import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/encode/payload_encoder.dart';
import '../../core/encode/gif_writer.dart' show buildGif;
import '../../core/encode/send_jobs.dart';
import '../../core/format/cimbar_spec.dart';
import '../../core/format/text_message.dart';
import '../../core/services/file_service.dart';

enum SendMode { text, file }

class SendState {
  final SendMode mode;
  final String text;
  final String? fileName;
  final Uint8List? fileBytes;
  final int delayMs;
  final bool busy;
  final String? error;

  const SendState({this.mode = SendMode.text, this.text = '', this.fileName, this.fileBytes,
      this.delayMs = CimbarSpec.defaultDelayMs, this.busy = false, this.error});

  SendState copyWith({SendMode? mode, String? text, String? fileName, Uint8List? fileBytes,
      int? delayMs, bool? busy, String? error, bool clearError = false}) => SendState(
        mode: mode ?? this.mode, text: text ?? this.text, fileName: fileName ?? this.fileName,
        fileBytes: fileBytes ?? this.fileBytes, delayMs: delayMs ?? this.delayMs, busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error));

  bool get hasInput => mode == SendMode.text ? text.isNotEmpty : fileBytes != null;
}

/// Upper bound on source frames before compression (name of a text message is 27 bytes).
int estimateFrames(SendState s, {required bool encrypted}) {
  final nameLen = s.mode == SendMode.text ? 27 : (s.fileName?.length ?? 0) * 4;
  final bytes = s.mode == SendMode.text ? utf8Length(s.text) : (s.fileBytes?.length ?? 0);
  final framed = 4 + 4 + nameLen + bytes + (encrypted ? 48 : 0);
  return (framed + CimbarSpec.fileBytesPerFrame - 1) ~/ CimbarSpec.fileBytesPerFrame;
}

int utf8Length(String s) => const Utf8Codec().encoder.convert(s).length;

final sendControllerProvider = StateNotifierProvider<SendController, SendState>((ref) => SendController());

class SendController extends StateNotifier<SendState> {
  SendController({EncodedPayload Function(SendRequest)? encoder,
      Future<void> Function(String name, Uint8List gif)? shareGifBytes, DateTime Function()? now})
      : _encoder = encoder,
        _shareGifBytes = shareGifBytes ?? _shareViaSheet,
        _now = now ?? DateTime.now,
        super(const SendState());

  final EncodedPayload Function(SendRequest)? _encoder;
  final Future<void> Function(String, Uint8List) _shareGifBytes;
  final DateTime Function() _now;

  void setMode(SendMode m) => state = state.copyWith(mode: m, clearError: true);
  void setText(String t) => state = state.copyWith(text: t, clearError: true);
  void setFile(String name, Uint8List bytes) => state = state.copyWith(fileName: name, fileBytes: bytes, clearError: true);
  void setDelay(int ms) => state = state.copyWith(delayMs: ms);

  SendRequest? _request(String passphrase) {
    if (!state.hasInput) return null;
    return state.mode == SendMode.text
        ? SendRequest(TextMessage.fileName(_now()), Uint8List.fromList(const Utf8Codec().encode(state.text)), passphrase)
        : SendRequest(state.fileName!, state.fileBytes!, passphrase);
  }

  Future<EncodedPayload?> encode(String passphrase, {required int cap}) async {
    final req = _request(passphrase);
    if (req == null) {
      state = state.copyWith(error: 'empty');
      return null;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      final enc = _encoder;
      final p = enc != null ? enc(req) : await encodeInIsolate(req);
      if (p.total > cap) {
        state = state.copyWith(busy: false, error: 'tooLarge:${p.total}:$cap');
        return null;
      }
      state = state.copyWith(busy: false);
      return p;
    } catch (e) {
      state = state.copyWith(busy: false, error: 'failed:$e');
      return null;
    }
  }

  Future<void> shareGif(String passphrase) async {
    final p = await encode(passphrase, cap: maxGifFrames);
    if (p == null) return;
    state = state.copyWith(busy: true);
    try {
      final delay = state.delayMs;
      final gif = _encoder != null ? buildGif(p, delay) : await buildGifInIsolate(p, delay);
      final base = state.mode == SendMode.text ? TextMessage.fileName(_now()) : state.fileName!;
      final stem = base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
      await _shareGifBytes('$stem.gif', gif);
      state = state.copyWith(busy: false);
    } catch (e) {
      state = state.copyWith(busy: false, error: 'failed:$e');
    }
  }

  static Future<void> _shareViaSheet(String name, Uint8List gif) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${FileService.safeBasename(name)}');
    await f.writeAsBytes(gif);
    await FileService.shareFile(f.path);
  }
}
