import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:share_handler/share_handler.dart';

import 'package:cimbar_scanner/core/services/incoming_share.dart';

SharedAttachment att(String path) => SharedAttachment(path: path, type: SharedAttachmentType.file);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('share_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File make(String name, int size) => File('${tmp.path}/$name')..writeAsBytesSync(List.filled(size, 7));

  test('an attachment wins over content and count is the attachment count', () async {
    final a = make('a.bin', 10);
    final b = make('b.bin', 10);
    final r = await readShare(SharedMedia(content: 'hi', attachments: [att(a.path), att(b.path)]));
    expect(r.count, 2);
    final item = r.item as SharedFileItem;
    expect(item.name, 'a.bin');
    expect(item.path, a.path);
    expect(item.length, 10);
  });

  test('file:// paths are read', () async {
    final a = make('a.bin', 3);
    final r = await readShare(SharedMedia(attachments: [att(Uri.file(a.path).toString())]));
    expect((r.item as SharedFileItem).path, a.path);
  });

  test('a leading too-large attachment does not hide a later usable one', () async {
    final big = make('big.bin', 2048);
    final b = make('b.bin', 5);
    for (final first in [att('cimbar-too-large:999999999'), att(big.path)]) {
      final r = await readShare(SharedMedia(attachments: [first, att(b.path)]), cap: 1024);
      expect((r.item as SharedFileItem).name, 'b.bin', reason: first.path);
      expect(r.count, 2);
    }
  });

  test('too large is reported only when nothing is usable, ahead of unreadable', () async {
    final big = make('big.bin', 2048);
    final r = await readShare(SharedMedia(attachments: [att('/nonexistent/x'), att(big.path)]), cap: 1024);
    expect((r.item as ShareTooLarge).length, 2048);
  });

  test('paths lists every real attachment path, markers and unparsable URIs excluded', () async {
    final a = make('a.bin', 3);
    final big = make('big.bin', 2048);
    final r = await readShare(
        SharedMedia(attachments: [
          att('cimbar-too-large:-1'),
          att(Uri.file(a.path).toString()),
          att(big.path),
          att('/nonexistent/x'),
          att('file://example.com/some/path.gif'),
          att(''),
        ]),
        cap: 1024);
    expect((r.item as SharedFileItem).path, a.path);
    expect(r.paths, [a.path, big.path, '/nonexistent/x']);
    expect((await readShare(SharedMedia(content: 'hi'))).paths, isEmpty);
  });

  test('first unreadable then readable gives the readable one', () async {
    final b = make('b.bin', 5);
    final r = await readShare(SharedMedia(attachments: [att('/nonexistent/x'), att(b.path)]));
    expect((r.item as SharedFileItem).name, 'b.bin');
  });

  test('only unreadable attachments give ShareUnreadable', () async {
    for (final p in ['/nonexistent/x', '', 'file://example.com/some/path.gif']) {
      final r = await readShare(SharedMedia(attachments: [att(p)]));
      expect(r.item, isA<ShareUnreadable>(), reason: p);
    }
  });

  test('the plugin too-large marker gives ShareTooLarge with its size', () async {
    final r = await readShare(SharedMedia(attachments: [att('cimbar-too-large:999999999')]));
    expect((r.item as ShareTooLarge).length, 999999999);
    final u = await readShare(SharedMedia(attachments: [att('cimbar-too-large:-1')]));
    expect((u.item as ShareTooLarge).length, isNull);
  });

  test('a file above the cap is too large without reading it', () async {
    final a = make('big.bin', 2048);
    final r = await readShare(SharedMedia(attachments: [att(a.path)]), cap: 1024);
    expect((r.item as ShareTooLarge).length, 2048);
  });

  test('text only gives SharedText; empty gives null', () async {
    final t = await readShare(SharedMedia(content: 'hello'));
    expect((t.item as SharedText).text, 'hello');
    expect(t.count, 0);
    expect((await readShare(SharedMedia(content: ''))).item, isNull);
    expect((await readShare(SharedMedia())).item, isNull);
  });

  test('stageSharedFile copies and deletes an original under cacheDir', () async {
    final cache = Directory('${tmp.path}/cache')..createSync();
    final base = Directory('${tmp.path}/base')..createSync();
    final orig = File('${cache.path}/p.png')..writeAsBytesSync([1, 2, 3]);
    final staged = await stageSharedFile(SharedFileItem(name: 'p.png', path: orig.path, length: 3),
        tempBase: base, cacheDir: cache.path);
    expect(staged, startsWith('${base.path}/share_in/'));
    expect(File(staged).readAsBytesSync(), [1, 2, 3]);
    expect(orig.existsSync(), isFalse);
  });

  test("stageSharedFile stamps the staged copy with now, whatever the original's age", () async {
    // iOS File.copy keeps the source's modified time; launch cleanup must
    // never take a fresh staged copy for a leftover.
    final base = Directory('${tmp.path}/base')..createSync();
    final orig = make('old.heic', 3)..setLastModifiedSync(DateTime(2020));
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    final staged = await stageSharedFile(SharedFileItem(name: 'old.heic', path: orig.path, length: 3),
        tempBase: base, cacheDir: '${tmp.path}/cache');
    expect(File(staged).lastModifiedSync().isBefore(before), isFalse);
  });

  test('stageSharedFile keeps an original outside cacheDir and sanitises the name', () async {
    final cache = Directory('${tmp.path}/cache')..createSync();
    final base = Directory('${tmp.path}/base')..createSync();
    final orig = make('o.png', 3);
    final staged = await stageSharedFile(SharedFileItem(name: '../../evil.png', path: orig.path, length: 3),
        tempBase: base, cacheDir: cache.path);
    expect(staged.split('/').last, 'evil.png');
    expect(staged, startsWith('${base.path}/share_in/'));
    expect(orig.existsSync(), isTrue);
  });

  group('deletePluginCopy', () {
    late Directory cache;
    setUp(() => cache = Directory('${tmp.path}/cache')..createSync());

    test('deletes a direct child of cacheDir, with or without a trailing separator', () async {
      final a = File('${cache.path}/a.pdf')..writeAsBytesSync([1]);
      final b = File('${cache.path}/b.pdf')..writeAsBytesSync([1]);
      await deletePluginCopy(a.path, cacheDir: cache.path, ios: false);
      await deletePluginCopy(b.path, cacheDir: '${cache.path}/', ios: false);
      expect(a.existsSync(), isFalse);
      expect(b.existsSync(), isFalse);
    });

    test('keeps a file nested below cacheDir (the plugin only writes direct children)', () async {
      // A crafted file:// share naming CimBar's own staged photo.
      final nested = File('${cache.path}/share_in/123/x.jpg')..createSync(recursive: true);
      final viaDotDot = File('${cache.path}/sub/y.pdf')..createSync(recursive: true);
      await deletePluginCopy(nested.path, cacheDir: cache.path, ios: false);
      await deletePluginCopy('${cache.path}/sub/../sub/y.pdf', cacheDir: cache.path, ios: false);
      await deletePluginCopy(nested.path, cacheDir: cache.path, ios: true);
      expect(nested.existsSync(), isTrue);
      expect(viaDotDot.existsSync(), isTrue);
    });

    test('keeps a file outside cacheDir, in a sibling with the same prefix, or reached by ..', () async {
      final outside = make('outside.pdf', 1);
      final sibling = File('${tmp.path}/cache_other/x.pdf')..createSync(recursive: true);
      final dotdot = make('escaped.pdf', 1);
      await deletePluginCopy(outside.path, cacheDir: cache.path);
      await deletePluginCopy(sibling.path, cacheDir: cache.path);
      await deletePluginCopy('${cache.path}/../escaped.pdf', cacheDir: cache.path);
      expect(outside.existsSync(), isTrue);
      expect(sibling.existsSync(), isTrue);
      expect(dotdot.existsSync(), isTrue);
    });

    test('deletes an iOS App Group copy on iOS only', () async {
      final f = File('${tmp.path}/Shared/AppGroup/1234/x.gif')..createSync(recursive: true);
      await deletePluginCopy(f.path, cacheDir: cache.path, ios: false);
      expect(f.existsSync(), isTrue, reason: 'no App Group on Android');
      await deletePluginCopy(f.path, cacheDir: cache.path, ios: true);
      expect(f.existsSync(), isFalse);
    });

    test('a missing file is not an error', () async {
      await deletePluginCopy('${cache.path}/gone', cacheDir: cache.path);
    });
  });

  test('stageSharedFile keeps an original in a sibling of cacheDir with the same prefix', () async {
    final cache = Directory('${tmp.path}/cache')..createSync();
    final base = Directory('${tmp.path}/base')..createSync();
    final orig = File('${tmp.path}/cache_other/p.png')..createSync(recursive: true);
    await stageSharedFile(SharedFileItem(name: 'p.png', path: orig.path, length: 0), tempBase: base, cacheDir: cache.path);
    expect(orig.existsSync(), isTrue);
  });
}
