import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/format/text_message.dart';

String repoPath(String rel) => '../$rel';

Uint8List caseBytes(Map<String, dynamic> c) {
  final hex = c['hex'] as String;
  final one = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < one.length; i++) {
    one[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  final n = (c['repeat'] as int?) ?? 1;
  final out = Uint8List(one.length * n);
  for (var i = 0; i < n; i++) {
    out.setRange(i * one.length, (i + 1) * one.length, one);
  }
  return out;
}

void main() {
  final fixture = jsonDecode(File(repoPath('test-data/text-message.json')).readAsStringSync()) as Map<String, dynamic>;
  for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
    test('fixture: ${c['name']} (${c['note']})', () {
      final bytes = caseBytes(c);
      expect(TextMessage.isTextMessage(c['name'] as String, bytes), c['expected']);
      final s = TextMessage.decode(c['name'] as String, bytes);
      if (c['expected'] as bool) {
        if (c['text'] != null) expect(s, c['text']);
      } else {
        expect(s, isNull);
      }
    });
  }

  test('fileName formats local time, zero-padded', () {
    expect(TextMessage.fileName(DateTime(2026, 1, 2, 3, 4, 5)), 'message-20260102-030405.txt');
  });
}
