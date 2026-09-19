import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const _seed = Color(0xFF2E7D32); // forest green

  static final light = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: _seed,
    brightness: Brightness.light,
  );

  static final dark = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: _seed,
    brightness: Brightness.dark,
  );
}
