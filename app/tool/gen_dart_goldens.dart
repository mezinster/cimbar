// Writes test-data/goldens/dart_text.{gif,json}: a text message encoded by
// the Dart encoder, in the coded sidecar schema of web-app/tools/gen_goldens.js,
// so the web suite proves a phone-made GIF decodes in JS.
// Usage: cd app && dart run tool/gen_dart_goldens.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cimbar_scanner/core/encode/cell_grid.dart';
import 'package:cimbar_scanner/core/encode/frame_builder.dart';
import 'package:cimbar_scanner/core/encode/gif_writer.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/format/frame_header.dart';
import 'package:cimbar_scanner/core/format/rateless.dart';

const words = ['CimBar', 'текст', 'повідомлення', 'მესიჯი', 'metin', 'frame', 'код', '😀', 'Ünïcödé', 'line'];

String hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // Deterministic LCG text: compressible (repeated vocabulary) yet large enough
  // that the deflated container spans several frames.
  var s = 12345;
  final sb = StringBuffer();
  for (var line = 0; line < 2000; line++) {
    for (var w = 0; w < 8; w++) {
      s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
      sb.write(words[s % words.length]);
      sb.write(w == 7 ? '\n' : ' ');
    }
  }
  final text = Uint8List.fromList(utf8.encode(sb.toString()));
  const name = 'message-20261001-120000.txt';
  final p = PayloadEncoder.encode(name: name, bytes: text, fileId: 0x2001);
  if (!p.compressed || p.total < 2) throw StateError('want compressed, N >= 2; got ${p.compressed}, ${p.total}');

  final frames = FrameBuilder.gifFrames(p);
  final side = <String, Object?>{
    'name': 'dart_text', 'fileName': name, 'fileBytesBase64': base64.encode(text),
    'passphrase': null, 'fileId': p.fileId, 'total': p.total, 'delayMs': CimbarSpec.defaultDelayMs,
    'framedDataLength': p.framedLength, 'compressed': p.compressed, 'sourceFrames': p.total,
    'repairFrames': frames.length - p.total, 'frameCount': frames.length,
    'frames': [
      for (final data in frames)
        () {
          final h = FrameHeader.decode(data).header!;
          final raw = CellGrid.raw(data);
          return {
            'seq': h.seq, 'repair': h.repair, 'r': h.repair ? h.seq : null,
            'header': {'version': h.version, 'encrypted': h.encrypted, 'repair': h.repair,
                       'compressed': h.compressed, 'fileId': h.fileId, 'seq': h.seq, 'total': h.total},
            'dataHex': hex(data), 'rawHex': hex(raw), 'cells': CellGrid.cells(data).toList(),
            'coef12': h.repair ? Rateless.coefficients(h.fileId, h.seq, h.total).sublist(0, h.total < 12 ? h.total : 12).toList() : null,
          };
        }(),
    ],
  };
  const dir = '../test-data/goldens';
  File('$dir/dart_text.gif').writeAsBytesSync(buildGif(p, CimbarSpec.defaultDelayMs));
  File('$dir/dart_text.json').writeAsStringSync(jsonEncode(side));
  stdout.writeln('dart_text: ${p.total} source + ${frames.length - p.total} repair frames, ${text.length} text bytes');
}
