/// Standalone script to generate a test CimBar GIF fixture.
///
/// Run: dart test/test_utils/generate_test_gif.dart
/// Output: test/fixtures/test_hello.gif
///
/// Known parameters:
///   Content:    "Hello, CimBar!" (14 bytes)
///   Filename:   hello.txt
///   Passphrase: test123
///   Frame size: 256px
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// We can't use package imports directly in a standalone script without
// pub resolution, so this file is intended to be run as a flutter test:
//   flutter test test/test_utils/generate_test_gif.dart
import 'package:flutter_test/flutter_test.dart';

import 'cimbar_encoder.dart';

void main() {
  test('generate test_hello.gif fixture', () {
    final fileData = Uint8List.fromList(utf8.encode('Hello, CimBar!'));
    const filename = 'hello.txt';
    const passphrase = 'test123';

    final gifBytes = CimbarEncoder.encodeToGif(
      fileData: fileData,
      filename: filename,
      passphrase: passphrase,
      frameSize: 256,
    );

    // Write to fixtures directory
    final dir = Directory('test/fixtures');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('test/fixtures/test_hello.gif');
    file.writeAsBytesSync(gifBytes);

    // Verify
    expect(file.existsSync(), isTrue);
    expect(gifBytes[0], equals(0x47)); // G
    expect(gifBytes[1], equals(0x49)); // I
    expect(gifBytes[2], equals(0x46)); // F

    // ignore: avoid_print
    print('Generated: ${file.path} (${gifBytes.length} bytes)');
    print('Passphrase: $passphrase');
    print('Content: Hello, CimBar!');
    print('Filename: $filename');
  });
}
