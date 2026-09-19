// The About screen credits sz3's libcimbar and CFC as this app's predecessors,
// links to both, and says their barcodes are not compatible with this app.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cimbar_scanner/core/providers/shared_preferences_provider.dart';
import 'package:cimbar_scanner/features/settings/settings_screen.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('About credits libcimbar and CFC with links', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('successor to libcimbar and CFC by sz3'), findsOneWidget);
    expect(find.textContaining('cannot read barcodes made by libcimbar or CFC'), findsOneWidget);
    expect(find.text('libcimbar: github.com/sz3/libcimbar'), findsOneWidget);
    expect(find.text('CFC: github.com/sz3/cfc'), findsOneWidget);
    expect(libcimbarUrl, 'https://github.com/sz3/libcimbar');
    expect(cfcUrl, 'https://github.com/sz3/cfc');
  });
}
