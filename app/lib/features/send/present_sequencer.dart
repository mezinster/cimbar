import 'dart:typed_data';

import '../../core/encode/frame_builder.dart';
import '../../core/encode/payload_encoder.dart';
import '../../core/format/cimbar_spec.dart';

class PresentStep {
  final Uint8List data;
  final bool repair;

  /// The source frame's seq, or the repair frame's id r.
  final int index;
  const PresentStep(this.data, this.repair, this.index);
}

/// Present-mode order (v2.1 spec, as the web app's present mode): the N
/// source frames once, then repair frames r = 0, 1, 2, … without end. With no
/// repair frames available (N == 1, or N above the coding cap) the source pass loops.
class PresentSequencer {
  PresentSequencer(this.payload);

  final EncodedPayload payload;
  int _source = 0;
  int _r = 0;
  bool _sourcesDone = false;

  bool get _coded => payload.total > 1 && payload.total <= CimbarSpec.codingMaxFrames;

  PresentStep next() {
    if (!_sourcesDone) {
      final s = _source++;
      if (_source == payload.total) {
        if (_coded) {
          _sourcesDone = true;
        } else {
          _source = 0;
        }
      }
      return PresentStep(FrameBuilder.sourceFrame(payload, s), false, s);
    }
    final rf = FrameBuilder.nextRepair(payload, _r);
    _r = rf.nextR;
    return PresentStep(rf.data, true, rf.r);
  }
}
