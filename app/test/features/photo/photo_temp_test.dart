import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/features/photo/data/photo_temp.dart';

void main() {
  late Directory base;
  setUp(() => base = Directory.systemTemp.createTempSync('photo_temp_test'));
  tearDown(() => base.deleteSync(recursive: true));

  File touch(String rel, DateTime modified) {
    final f = File('${base.path}/$rel')..createSync(recursive: true);
    f.setLastModifiedSync(modified);
    return f;
  }

  test('deletes entries older than launch in both temp folders', () async {
    final launch = DateTime.now();
    final old = launch.subtract(const Duration(hours: 1));
    final fresh = launch.add(const Duration(seconds: 5));
    final oldOpt = touch('photo_optimiser/a.jpg', old);
    final oldShare = touch('share_in/b.heic', old);
    final freshShare = touch('share_in/c.heic', fresh);
    final unrelated = touch('other/d.bin', old);

    await clearPhotoTemp(olderThan: launch, base: base);

    expect(oldOpt.existsSync(), isFalse);
    expect(oldShare.existsSync(), isFalse);
    expect(freshShare.existsSync(), isTrue,
        reason: 'a share copied after launch must survive');
    expect(unrelated.existsSync(), isTrue);
  });

  /// Sets folder [rel]'s modified time (adding or deleting an entry bumps
  /// it). dart:io can't set a directory's time; POSIX `touch -t` can.
  void age(String rel, DateTime modified) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = modified.toLocal();
    final stamp = '${m.year}${two(m.month)}${two(m.day)}${two(m.hour)}${two(m.minute)}.${two(m.second)}';
    final r = Process.runSync('touch', ['-t', stamp, '${base.path}/$rel']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }

  test('nested folders: stale files go, emptied folders go, fresh stay',
      () async {
    final launch = DateTime.now();
    final dayAgo = launch.subtract(const Duration(days: 1));
    touch('share_in/old/x.jpg', dayAgo);
    age('share_in/old', dayAgo);
    final fresh =
        touch('share_in/new/y.jpg', launch.add(const Duration(seconds: 5)));

    await clearPhotoTemp(olderThan: launch, base: base);

    expect(Directory('${base.path}/share_in/old').existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
  });

  test('a folder made since launch is left alone, even while still empty',
      () async {
    // A cold-start share being staged: its folder exists, its file not yet.
    final launch = DateTime.now().subtract(const Duration(minutes: 1));
    final staging = Directory('${base.path}/share_in/123')
      ..createSync(recursive: true);

    await clearPhotoTemp(olderThan: launch, base: base);

    expect(staging.existsSync(), isTrue);
  });

  test('missing folders are not an error', () async {
    await clearPhotoTemp(olderThan: DateTime.now(), base: base);
  });
}
