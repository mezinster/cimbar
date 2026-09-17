// Renders golden GIF frames into synthetic camera-like scenes with known
// geometry so locator/decoder tests have exact ground truth.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:cimbar_scanner/core/decode/golden_sidecar.dart';
import 'package:cimbar_scanner/core/decode/homography.dart';
import 'package:cimbar_scanner/core/decode/rgb_buffer.dart';
import 'package:cimbar_scanner/core/decode/yuv_frame.dart';
import 'package:cimbar_scanner/core/format/cimbar_spec.dart';
import 'package:cimbar_scanner/core/services/gif_parser.dart';

RgbBuffer loadGoldenFrame(String name, int frameIndex) {
  final gif = File(GoldenSidecar.gifPathFor('../test-data/goldens/$name.json')).readAsBytesSync();
  return RgbBuffer.fromImage(GifParser.parseFrames(gif)[frameIndex]);
}

RgbBuffer loadPhoto(String path) => RgbBuffer.fromImage(img.decodeImage(File(path).readAsBytesSync())!);

class SceneSpec {
  double scale = 1;
  double rotationDeg = 0;
  /// Keystone: top edge shrunk by (1-k), bottom edge widened by (1+k) before rotation.
  double keystone = 0;
  double centerX = 0;
  double centerY = 0;
  double blurSigma = 0; // destination pixels
  double brightness = 1;
  double noiseSigma = 0;
  /// Barrel distortion applied in scene space: p' = c + (p - c) * (1 + k r^2), r = |p-c| / (304*scale).
  double barrelK = 0;
  int seed = 1;
}

class Scene {
  final RgbBuffer image;
  final List<(double, double)> finderCenters; // TL, TR, BL, BR in scene px
  final Homography frameToScene;
  const Scene(this.image, this.finderCenters, this.frameToScene);
}

const List<(double, double)> frameCorners = [(0.0, 0.0), (608.0, 0.0), (0.0, 608.0), (608.0, 608.0)];

/// Destination corners (TL, TR, BL, BR) of the 608x608 frame under [spec].
List<(double, double)> sceneQuad(SceneSpec spec) {
  final half = CimbarSpec.framePx / 2 * spec.scale;
  final k = spec.keystone;
  final local = [(-half * (1 - k), -half), (half * (1 - k), -half), (-half * (1 + k), half), (half * (1 + k), half)];
  final th = spec.rotationDeg * math.pi / 180;
  final c = math.cos(th), s = math.sin(th);
  return [
    for (final (x, y) in local) (spec.centerX + x * c - y * s, spec.centerY + x * s + y * c),
  ];
}

Scene renderScene(RgbBuffer frame, int outW, int outH, SceneSpec spec, {RgbBuffer? background}) {
  final quad = sceneQuad(spec);
  final frameToScene = Homography.solve(frameCorners, quad)!;
  final sceneToFrame = Homography.solve(quad, frameCorners)!;
  final out = Uint8List(outW * outH * 3);
  final tmp = Float32List(3);
  final radius = CimbarSpec.framePx / 2 * spec.scale;
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      var px = x + 0.5, py = y + 0.5;
      if (spec.barrelK != 0) {
        final dx = px - spec.centerX, dy = py - spec.centerY;
        final r2 = (dx * dx + dy * dy) / (radius * radius);
        final f = 1 + spec.barrelK * r2;
        px = spec.centerX + dx * f;
        py = spec.centerY + dy * f;
      }
      final (u, v) = sceneToFrame.map(px, py);
      final o = (y * outW + x) * 3;
      if (u >= 0 && u < CimbarSpec.framePx && v >= 0 && v < CimbarSpec.framePx) {
        frame.bilinear(u, v, tmp, 0);
        out[o] = tmp[0].round().clamp(0, 255);
        out[o + 1] = tmp[1].round().clamp(0, 255);
        out[o + 2] = tmp[2].round().clamp(0, 255);
      } else if (background != null) {
        final bx = x.clamp(0, background.width - 1), by = y.clamp(0, background.height - 1);
        out[o] = background.r(bx, by);
        out[o + 1] = background.g(bx, by);
        out[o + 2] = background.b(bx, by);
      }
    }
  }
  var image = RgbBuffer(outW, outH, out);
  if (spec.blurSigma > 0) image = gaussianBlur(image, spec.blurSigma);
  if (spec.brightness != 1 || spec.noiseSigma > 0) image = brightnessNoise(image, spec.brightness, spec.noiseSigma, spec.seed);
  final centers = [
    for (final (fx, fy) in [(47.5, 47.5), (560.5, 47.5), (47.5, 560.5), (560.5, 560.5)]) frameToScene.map(fx, fy),
  ];
  return Scene(image, centers, frameToScene);
}

RgbBuffer gaussianBlur(RgbBuffer src, double sigma) {
  final radius = (3 * sigma).ceil();
  final kernel = Float64List(2 * radius + 1);
  var sum = 0.0;
  for (var i = -radius; i <= radius; i++) {
    kernel[i + radius] = math.exp(-(i * i) / (2 * sigma * sigma));
    sum += kernel[i + radius];
  }
  for (var i = 0; i < kernel.length; i++) {
    kernel[i] /= sum;
  }
  final w = src.width, h = src.height;
  final tmp = Float32List(w * h * 3);
  final s = src.rgb;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 3; c++) {
        var acc = 0.0;
        for (var i = -radius; i <= radius; i++) {
          final xx = (x + i).clamp(0, w - 1);
          acc += s[(y * w + xx) * 3 + c] * kernel[i + radius];
        }
        tmp[(y * w + x) * 3 + c] = acc;
      }
    }
  }
  final out = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 3; c++) {
        var acc = 0.0;
        for (var i = -radius; i <= radius; i++) {
          final yy = (y + i).clamp(0, h - 1);
          acc += tmp[(yy * w + x) * 3 + c] * kernel[i + radius];
        }
        out[(y * w + x) * 3 + c] = acc.round().clamp(0, 255);
      }
    }
  }
  return RgbBuffer(w, h, out);
}

RgbBuffer brightnessNoise(RgbBuffer src, double brightness, double noiseSigma, int seed) {
  final rnd = math.Random(seed);
  final out = Uint8List(src.rgb.length);
  for (var i = 0; i < out.length; i++) {
    var v = src.rgb[i] * brightness;
    if (noiseSigma > 0) {
      final u1 = math.max(1e-12, rnd.nextDouble()), u2 = rnd.nextDouble();
      v += noiseSigma * math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
    }
    out[i] = v.round().clamp(0, 255);
  }
  return RgbBuffer(src.width, src.height, out);
}

/// Forward BT.601 conversion to YUV_420_888 planes (chroma = 2x2 average).
/// [semiPlanar] interleaves U/V (uvPixelStride 2) as CameraX exposes NV21-like
/// buffers; [yPad] adds row padding so yRowStride > width.
YuvFrame rgbToYuv420(RgbBuffer src, {bool semiPlanar = false, int yPad = 0}) {
  final w = src.width, h = src.height, stride = w + yPad;
  final y = Uint8List(stride * h);
  final cw = (w + 1) ~/ 2, ch = (h + 1) ~/ 2;
  final uvStride = semiPlanar ? cw * 2 : cw;
  final u = Uint8List(uvStride * ch), v = Uint8List(uvStride * ch);
  for (var yy = 0; yy < h; yy++) {
    for (var x = 0; x < w; x++) {
      final i = (yy * w + x) * 3;
      final r = src.rgb[i], g = src.rgb[i + 1], b = src.rgb[i + 2];
      y[yy * stride + x] = ((77 * r + 150 * g + 29 * b) >> 8).clamp(0, 255);
    }
  }
  for (var cy = 0; cy < ch; cy++) {
    for (var cx = 0; cx < cw; cx++) {
      var rs = 0, gs = 0, bs = 0, n = 0;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final px = cx * 2 + dx, py = cy * 2 + dy;
          if (px >= w || py >= h) continue;
          final i = (py * w + px) * 3;
          rs += src.rgb[i];
          gs += src.rgb[i + 1];
          bs += src.rgb[i + 2];
          n++;
        }
      }
      final r = rs / n, g = gs / n, b = bs / n;
      final uu = (128 - 0.168736 * r - 0.331264 * g + 0.5 * b).round().clamp(0, 255);
      final vv = (128 + 0.5 * r - 0.418688 * g - 0.081312 * b).round().clamp(0, 255);
      final idx = cy * uvStride + cx * (semiPlanar ? 2 : 1);
      u[idx] = uu;
      v[idx] = vv;
    }
  }
  return YuvFrame(
    yPlane: y,
    uPlane: u,
    vPlane: v,
    width: w,
    height: h,
    yRowStride: stride,
    uvRowStride: uvStride,
    uvPixelStride: semiPlanar ? 2 : 1,
  );
}
