import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/format/file_container.dart';

void main() {
  Uint8List payload(String name, List<int> bytes) {
    final n = utf8.encode(name);
    final out = Uint8List(4 + n.length + bytes.length);
    out[3] = n.length;
    out.setRange(4, 4 + n.length, n);
    out.setRange(4 + n.length, out.length, bytes);
    return out;
  }

  test('parsePayload', () {
    final p = FileContainer.parsePayload(payload('hello.txt', [1, 2, 3]));
    expect(p.fileName, 'hello.txt');
    expect(p.fileBytes, Uint8List.fromList([1, 2, 3]));
  });

  test('parsePayload rejects bad name length', () {
    expect(() => FileContainer.parsePayload(Uint8List.fromList([0, 0, 9, 9, 1])), throwsFormatException);
  });

  test('stripLengthPrefix strips zero padding and validates', () {
    final body = payload('a.bin', [7, 8]);
    final framed = Uint8List(4 + body.length + 50);
    framed[3] = body.length;
    framed.setRange(4, 4 + body.length, body);
    expect(FileContainer.stripLengthPrefix(framed), body);
    expect(() => FileContainer.stripLengthPrefix(Uint8List.fromList([0, 0, 0, 99, 1])), throwsFormatException);
    expect(() => FileContainer.stripLengthPrefix(Uint8List.fromList([0, 0, 0, 0, 1])), throwsFormatException);
  });

  test('isEncrypted checks the CB 42 magic', () {
    expect(FileContainer.isEncrypted(Uint8List.fromList([0xCB, 0x42, 1, 0, 9])), isTrue);
    expect(FileContainer.isEncrypted(Uint8List.fromList([0, 0, 0, 5])), isFalse);
    expect(FileContainer.isEncrypted(Uint8List(1)), isFalse);
  });
}
