import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers/shared_preferences_provider.dart';
import 'features/photo/data/photo_temp.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final launchTime = DateTime.now();
  unawaited(clearPhotoTemp(olderThan: launchTime));
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const CimBarApp(),
    ),
  );
}
