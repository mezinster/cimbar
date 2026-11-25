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
}
