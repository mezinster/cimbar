/// Name for an optimised photo: the original base name with `.jpg`, or
/// `photo-yyyyMMdd-HHmmss.jpg` when the source gave no name or only a UUID
/// (what share-in and some pickers hand over).
final _uuidStem = RegExp(
    r'^[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}$');

String optimisedFileName(String? original, DateTime now) {
  if (original == null || original.isEmpty) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${now.year.toString().padLeft(4, '0')}'
        '${two(now.month)}${two(now.day)}';
    final time = '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return 'photo-$date-$time.jpg';
  }
  final dot = original.lastIndexOf('.');
  final base = dot > 0 ? original.substring(0, dot) : original;
  if (_uuidStem.hasMatch(base)) return optimisedFileName(null, now);
  return '$base.jpg';
}
