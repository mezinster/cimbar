import 'package:flutter_test/flutter_test.dart';
import 'package:cimbar_scanner/features/photo/domain/optimised_file_name.dart';

void main() {
  final now = DateTime(2026, 11, 11, 9, 5, 3);

  test('replaces the extension with .jpg', () {
    expect(optimisedFileName('IMG_1234.HEIC', now), 'IMG_1234.jpg');
    expect(optimisedFileName('a.b.png', now), 'a.b.jpg');
  });

  test('appends .jpg to a name without an extension', () {
    expect(optimisedFileName('noext', now), 'noext.jpg');
  });

  test('no name falls back to a timestamp', () {
    expect(optimisedFileName(null, now), 'photo-20261111-090503.jpg');
    expect(optimisedFileName('', now), 'photo-20261111-090503.jpg');
  });

  test('a UUID stem is treated like no name', () {
    expect(
        optimisedFileName('3F2504E0-4F89-11D3-9A0C-0305E82C3301.png',
            DateTime(2026, 11, 25, 9, 5, 7)),
        'photo-20261125-090507.jpg');
  });
}
