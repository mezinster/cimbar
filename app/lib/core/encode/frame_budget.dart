import 'dart:convert' show utf8;
import 'dart:math' as math;

import '../format/cimbar_spec.dart';

/// AES-GCM envelope: magic 4 + salt 16 + IV 12 + tag 16.
const int encryptionOverheadBytes = 48;

/// Bytes the encoder frames for a file of [dataBytes] with a [nameBytes]-byte
/// UTF-8 name, before compression: length prefix (4) + name-length field (4)
/// + name + data + the AES-GCM envelope when [encrypted].
int framedBytes({required int nameBytes, required int dataBytes, required bool encrypted}) =>
    4 + 4 + nameBytes + dataBytes + (encrypted ? encryptionOverheadBytes : 0);

/// Source frame count for [framed] bytes, as `PayloadEncoder`'s `total`.
int framesForFramed(int framed) =>
    math.max(1, (framed + CimbarSpec.fileBytesPerFrame - 1) ~/ CimbarSpec.fileBytesPerFrame);

/// Largest incompressible file size that still fits [frames] frames when
/// encrypted (the worst case). May be zero or negative for a long name.
int photoByteBudget(int frames, String fileName) =>
    frames * CimbarSpec.fileBytesPerFrame -
    framedBytes(nameBytes: utf8.encode(fileName).length, dataBytes: 0, encrypted: true);

/// Frames needed for [dataBytes] of uncompressed data under [fileName].
int framesForFile(String fileName, int dataBytes, {required bool encrypted}) => framesForFramed(
    framedBytes(nameBytes: utf8.encode(fileName).length, dataBytes: dataBytes, encrypted: encrypted));
