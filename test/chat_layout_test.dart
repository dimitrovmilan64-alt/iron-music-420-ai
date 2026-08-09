import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ironmusic420ai/pages/chat_page.dart';
import 'package:ironmusic420ai/services/local_store.dart';
import 'package:ironmusic420ai/ui/common_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chat and API sheet do not overflow on a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = LocalStore();
    await store.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(body: ChatPage(store: store)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.byType(CannabisCore), findsOneWidget);
    expect(find.text('IRON'), findsOneWidget);
    expect(find.text('MUSIC 420 AI'), findsOneWidget);
    expect(find.text('Чат'), findsOneWidget);
    expect(find.text('ДОКОСНИ ЯДРОТО'), findsOneWidget);
    expect(find.text('CHAT'), findsNothing);
    expect(find.text('COMMANDS'), findsNothing);
    expect(find.text('MUSIC MODE'), findsNothing);
    expect(find.text('KEYBOARD'), findsNothing);

    await tester.ensureVisible(find.text('Чат'));
    await tester.tap(find.text('Чат'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('CHAT WITH IRON'), findsOneWidget);

    final apiButton = find.byTooltip('AI доставчици');
    expect(apiButton, findsWidgets);
    await tester.ensureVisible(apiButton.last);
    await tester.tap(apiButton.last);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('AI доставчици'), findsOneWidget);
    expect(find.text('Запази AI доставчиците'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('living core paints every interaction state', (tester) async {
    for (final state in IronCoreState.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: Center(
              child: CannabisCore(
                progress: 0.62,
                size: 192,
                state: state,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Core state: $state');
    }
  });
}
