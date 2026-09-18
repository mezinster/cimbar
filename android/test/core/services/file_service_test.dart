import 'package:flutter_test/flutter_test.dart';

import 'package:cimbar_scanner/core/services/file_service.dart';

void main() {
  group('mimeTypeFor', () {
    test('resolves common extensions from the file name', () {
      expect(FileService.mimeTypeFor('/data/user/0/app/files/report.pdf'), 'application/pdf');
      expect(FileService.mimeTypeFor('photo.PNG'), 'image/png');
      expect(FileService.mimeTypeFor('notes.txt'), 'text/plain');
      expect(FileService.mimeTypeFor('archive.zip'), 'application/zip');
    });

    test('falls back to application/octet-stream for unknown or missing extensions', () {
      expect(FileService.mimeTypeFor('backup.nfar'), 'application/octet-stream');
      expect(FileService.mimeTypeFor('README'), 'application/octet-stream');
      expect(FileService.mimeTypeFor('decoded.bin'), 'application/octet-stream');
    });
  });

  group('safeBasename', () {
    test('strips directories from both separator styles', () {
      expect(FileService.safeBasename('../../etc/passwd'), 'passwd');
      expect(FileService.safeBasename(r'C:\Users\me\file.txt'), 'file.txt');
    });

    test('falls back to decoded.bin when nothing usable remains', () {
      expect(FileService.safeBasename(''), 'decoded.bin');
      expect(FileService.safeBasename('..'), 'decoded.bin');
      expect(FileService.safeBasename('dir/'), 'decoded.bin');
    });
  });
}
