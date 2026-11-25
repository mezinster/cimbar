import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/photo/data/platform_jpeg_session.dart';
import 'photo_decoder.dart';

enum ShareKind { image, gif, other }

const _heifBrands = {'heic', 'heix', 'hevc', 'heim', 'heis', 'mif1', 'msf1'};

String _ascii(Uint8List b, int from, int to) =>
    String.fromCharCodes(b.sublist(from, to));

/// Classifies a shared file by its magic bytes.
ShareKind sniffKind(Uint8List head) {
  if (head.length >= 3 && head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF) {
    return ShareKind.image;
  }
  if (head.length >= 4 && head[0] == 0x89 && head[1] == 0x50 && head[2] == 0x4E && head[3] == 0x47) {
    return ShareKind.image;
  }
  if (head.length >= 4 && _ascii(head, 0, 4) == 'GIF8') return ShareKind.gif;
  if (head.length >= 12 && _ascii(head, 0, 4) == 'RIFF' && _ascii(head, 8, 12) == 'WEBP') {
    return ShareKind.image;
  }
  if (head.length >= 12 && _ascii(head, 4, 8) == 'ftyp' && _heifBrands.contains(_ascii(head, 8, 12))) {
    return ShareKind.image;
  }
  return ShareKind.other;
}

typedef PixelDecoder = Future<DecodedPixels> Function(String path, {int maxPixels});

final pixelDecoderProvider = Provider<PixelDecoder>((_) => decodePixels);

/// Tries to read a CimBar barcode out of the photo at [path], decrypting with
/// [passphrase] if it has one.
Future<PhotoDecodeResult> detectSharedPhoto(String path, PixelDecoder decode, {String passphrase = ''}) async {
  final DecodedPixels px;
  try {
    px = await decode(path, maxPixels: 12000000);
  } on PhotoDecodeException {
    return const PhotoDecodeResult(error: 'Cannot decode image', errorCode: 'unreadable_image');
  } on PhotoMemoryException {
    return const PhotoDecodeResult(error: 'Not enough memory to decode image', errorCode: 'unreadable_image');
  }
  return decodePhotoPixels(px, passphrase);
}

/// True when the decode found a CimBar barcode (even one we can't finish).
bool isBarcodeOutcome(PhotoDecodeResult r) =>
    r.errorCode != 'not_located' && r.errorCode != 'unsupported_grid' && r.errorCode != 'unreadable_image';
