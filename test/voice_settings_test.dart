import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ironmusic420ai/pages/settings_page.dart';
import 'package:ironmusic420ai/services/local_store.dart';
import 'package:ironmusic420ai/theme/iron_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LocalStore> storeWithKeys({
    required bool gemini,
    required bool groq,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final store = LocalStore();
    await store.initialize();
    if (gemini) {
      await store.setApiKey('test-gemini-key');
    }
    if (groq) {
      await store.setBackupProvider(
        apiKey: 'test-groq-key',
        baseUrl: '',
        model: '',
      );
    }
    return store;
  }

  testWidgets('settings show sliders and cloud voices when keys are saved',
      (tester) async {
    final store = await storeWithKeys(gemini: true, groq: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: ironTheme(),
        home: Scaffold(body: SettingsPage(store: store)),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Скорост'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Скорост'), findsOneWidget);
    expect(find.text('Височина'), findsOneWidget);
    expect(find.textContaining('Kore'), findsWidgets);
    await tester.scrollUntilVisible(
      find.textContaining('Autumn'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('Autumn'), findsWidgets);
    expect(find.textContaining('само EN'), findsWidgets);
    expect(
      find.text(
          'Gemini гласовете работят и на български. Groq е само за английски.'),
      findsOneWidget,
    );
  });

  testWidgets('cloud voices stay hidden until a key is present',
      (tester) async {
    final store = await storeWithKeys(gemini: false, groq: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: ironTheme(),
        home: Scaffold(body: SettingsPage(store: store)),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Скорост'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Скорост'), findsOneWidget);
    expect(find.textContaining('Kore'), findsNothing);
    expect(find.textContaining('Autumn'), findsNothing);
    expect(
      find.textContaining(
          'Добави Gemini ключ за облачни гласове на български.'),
      findsOneWidget,
    );
  });
}
