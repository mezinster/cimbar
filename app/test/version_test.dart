import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// pubspec's version must name the newest release in CHANGELOG.md. The release
/// workflow overrides it at build time, so this is what keeps a local/debug
/// build truthful about which release it descends from.
void main() {
  test('pubspec version matches the newest CHANGELOG release', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1)!;
    final changelog = File('../CHANGELOG.md').readAsStringSync();
    final newest = RegExp(r'^## \[(\d+\.\d+\.\d+)\]', multiLine: true).firstMatch(changelog)!.group(1)!;
    expect(version.split('+').first, newest, reason: 'pubspec.yaml version: $version, CHANGELOG newest release: $newest');
  });
}
