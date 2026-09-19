// Offline CimBar v2 decoder. Pure Dart: `dart run tool/decode_image.dart …` from app/.
//
// Usage:
//   dart run tool/decode_image.dart <image.png|jpg|gif> [--frame N] [--golden name.json]
//                                   [--heatmap out.png] [--mode exact|camera] [--no-drift]
// Prints `frame=N stage=… key=value` lines. Exit 0 iff the frame decodes (status ok).
import 'dart:io';

import 'package:image/image.dart' as img;

import 'package:cimbar_scanner/core/decode/decode_report.dart';
import 'package:cimbar_scanner/core/decode/diagnostics.dart';
import 'package:cimbar_scanner/core/decode/frame_decoder.dart';
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/services/gif_parser.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: decode_image.dart <image> [--frame N] [--golden x.json] [--heatmap out.png] [--mode exact|camera] [--no-drift]');
    exit(2);
  }
  final path = args[0];
  var frameIndex = 0;
  String? goldenPath;
  String? heatmapPath;
  String? mode;
  var useDrift = true;
  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--frame':
        if (i + 1 >= args.length) {
          stderr.writeln('missing value for ${args[i]}');
          exit(2);
        }
        final parsed = int.tryParse(args[++i]);
        if (parsed == null) {
          stderr.writeln('invalid value for --frame');
          exit(2);
        }
        frameIndex = parsed;
      case '--golden':
        if (i + 1 >= args.length) {
          stderr.writeln('missing value for ${args[i]}');
          exit(2);
        }
        goldenPath = args[++i];
      case '--heatmap':
        if (i + 1 >= args.length) {
          stderr.writeln('missing value for ${args[i]}');
          exit(2);
        }
        heatmapPath = args[++i];
      case '--mode':
        if (i + 1 >= args.length) {
          stderr.writeln('missing value for ${args[i]}');
          exit(2);
        }
        mode = args[++i];
      case '--no-drift':
        useDrift = false;
      default:
        stderr.writeln('unknown argument ${args[i]}');
        exit(2);
    }
  }
  final bytes = File(path).readAsBytesSync();
  final isGif = path.toLowerCase().endsWith('.gif');
  mode ??= isGif ? 'exact' : 'camera';
  if (mode != 'exact' && mode != 'camera') {
    stderr.writeln('--mode must be exact or camera');
    exit(2);
  }

  final img.Image image;
  var frameCount = 1;
  if (isGif) {
    final frames = GifParser.parseFrames(bytes);
    frameCount = frames.length;
    if (frameIndex >= frames.length) {
      stderr.writeln('frame $frameIndex out of range (${frames.length} frames)');
      exit(2);
    }
    image = frames[frameIndex];
  } else {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      stderr.writeln('cannot decode image $path');
      exit(2);
    }
    image = decoded;
  }
  stdout.writeln('frame=$frameIndex stage=input path=$path width=${image.width} height=${image.height} frames=$frameCount mode=$mode');

  final buffer = RgbBuffer.fromImage(image);
  final decoder = FrameDecoder();
  final result = mode == 'exact' ? decoder.decodeExact(buffer) : decoder.decode(buffer, useDrift: useDrift);

  GoldenFrame? truth;
  if (goldenPath != null) {
    final golden = GoldenSidecar.load(goldenPath);
    if (frameIndex < golden.frames.length) truth = golden.frames[frameIndex];
  }
  for (final line in DecodeReport.lines(result, frameIndex: frameIndex, truth: truth)) {
    stdout.writeln(line);
  }
  if (heatmapPath != null && truth != null && result.cells != null) {
    File(heatmapPath).writeAsBytesSync(img.encodePng(DecodeReport.heatmap(result.cells!, truth.cells)));
    stdout.writeln('frame=$frameIndex stage=heatmap path=$heatmapPath');
  }
  exit(result.status == DecodeStatus.ok ? 0 : 1);
}
