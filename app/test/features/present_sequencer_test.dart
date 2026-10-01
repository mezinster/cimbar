import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/core/decode/rateless_assembler.dart';
import 'package:cimbar_scanner/core/encode/payload_encoder.dart';
import 'package:cimbar_scanner/core/services/payload_decoder.dart';
import 'package:cimbar_scanner/features/send/present_sequencer.dart';

void main() {
  test('source frames once, then repair frames forever', () {
    final p = PayloadEncoder.encode(name: 'n.txt', bytes: Uint8List(9000), allowCompression: false);
    final seq = PresentSequencer(p);
    final steps = List.generate(p.total + 5, (_) => seq.next());
    expect([for (final s in steps.take(p.total)) s.repair], everyElement(isFalse));
    expect([for (final s in steps.take(p.total)) s.index], List.generate(p.total, (i) => i));
    expect([for (final s in steps.skip(p.total)) s.repair], everyElement(isTrue));
  });

  test('a receiver that missed every source frame still completes from repair frames', () {
    final bytes = Uint8List.fromList(List.generate(9000, (i) => i * 7 & 0xFF));
    final p = PayloadEncoder.encode(name: 'n.bin', bytes: bytes, allowCompression: false);
    final seq = PresentSequencer(p);
    for (var i = 0; i < p.total; i++) {
      seq.next(); // missed
    }
    final asm = RatelessAssembler();
    while (!asm.isComplete) {
      asm.add(seq.next().data);
    }
    expect(decodeFramedPayload(asm.framedData(), '').fileBytes, bytes);
  });

  test('a one-frame file loops its source frame', () {
    final p = PayloadEncoder.encode(name: 'a.txt', bytes: Uint8List.fromList([65]));
    final seq = PresentSequencer(p);
    expect([for (var i = 0; i < 3; i++) seq.next().repair], [false, false, false]);
  });
}
