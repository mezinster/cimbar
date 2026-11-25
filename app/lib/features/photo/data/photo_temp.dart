import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Folder (under the temp directory) holding optimised JPEGs awaiting archive.
const photoOptimiserDirName = 'photo_optimiser';

/// Folder (under the temp directory) holding files shared into the app.
const shareInDirName = 'share_in';

/// The temp directory, overridable in tests.
final photoTempDirProvider =
    Provider<Future<Directory> Function()>((_) => getTemporaryDirectory);

/// Deletes leftovers of earlier runs from the optimiser and share-in folders.
///
/// Only entries last modified before [olderThan] (the app's launch time) go:
/// a share copied in during the first seconds after a cold start must survive.
/// [base] defaults to the temp directory.
Future<void> clearPhotoTemp({
  required DateTime olderThan,
  Directory? base,
}) async {
  try {
    final root = base ?? await getTemporaryDirectory();
    for (final name in const [photoOptimiserDirName, shareInDirName]) {
      final dir = Directory('${root.path}/$name');
      if (await dir.exists()) await _clearStale(dir, olderThan);
    }
  } catch (_) {
    // Housekeeping only; a failure must not affect the app.
  }
}

/// Deletes what in [dir] was last modified before [olderThan]. A folder
/// modified since launch is skipped whole, contents included: a cold-start
/// share being staged creates its folder before copying the file in, and that
/// still-empty folder must not be swept away underneath it.
Future<void> _clearStale(Directory dir, DateTime olderThan) async {
  await for (final entity in dir.list(followLinks: false)) {
    if (!(await entity.stat()).modified.isBefore(olderThan)) continue;
    if (entity is Directory) {
      await _clearStale(entity, olderThan);
      if (await entity.list().isEmpty) await entity.delete();
    } else {
      await entity.delete();
    }
  }
}
