import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ironmusic420ai/pages/settings_page.dart';
import 'package:ironmusic420ai/services/local_store.dart';
import 'package:ironmusic420ai/theme/iron_theme.dart';
import 'package:ironmusic420ai/widgets/voice_settings_panel.dart';

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

  Future<void> revealVoiceSection(WidgetTester tester) async {
    final pageScroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Скорост'),
      400,
      scrollable: pageScroll,
    );
    for (var i = 0;
        i < 16 && find.textContaining('Sulafat').evaluate().isEmpty;
        i++) {
      await tester.drag(pageScroll, const Offset(0, -280));
      await tester.pump();
    }
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
    await revealVoiceSection(tester);

    expect(find.text('Скорост'), findsOneWidget);
    expect(find.text('Височина'), findsOneWidget);
    expect(find.textContaining('Sulafat'), findsWidgets);
    expect(find.textContaining('Kore'), findsWidgets);
    expect(find.text('Чуй пробен глас'), findsWidgets);

    final voiceScroll = find.descendant(
      of: find.byType(VoiceSettingsPanel),
      matching: find.byType(Scrollable),
    );
    expect(voiceScroll, findsOneWidget);
    final pageScroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      voiceScroll,
      250,
      scrollable: pageScroll,
    );
    await tester.scrollUntilVisible(
      find.textContaining('Autumn'),
      200,
      scrollable: voiceScroll,
    );
    expect(find.textContaining('Autumn'), findsWidgets);
    expect(find.textContaining('само EN'), findsWidgets);
    expect(
      find.textContaining('естествен глас на Gemini на български'),
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
      find.textContaining('Добави Gemini ключ за естествен глас'),
      findsWidgets,
    );
  });
}
