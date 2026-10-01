import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cimbar_scanner/core/models/decode_result.dart';
import 'package:cimbar_scanner/features/camera/live_scan_screen.dart';
import 'package:cimbar_scanner/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('a text result stays on a short landscape screen and Cancel is reachable', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var cancelled = false;
    final text = List.generate(200, (i) => 'line $i').join('\n');
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Stack(children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LiveScanResultPanel(
              result: DecodeResult(filename: 'm.txt', data: Uint8List.fromList(text.codeUnits)),
              onCancel: () => cancelled = true,
            ),
          ),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(LiveScanResultPanel)).height, lessThanOrEqualTo(400 * 0.7 + 0.01));

    await tester.dragUntilVisible(
      find.text('Cancel'),
      find.byType(SingleChildScrollView).first,
      const Offset(0, -100),
    );
    await tester.tap(find.text('Cancel'));
    expect(cancelled, isTrue);
  });
}
