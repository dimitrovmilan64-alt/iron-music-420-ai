import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ironmusic420ai/pages/chat_page.dart';
import 'package:ironmusic420ai/services/local_store.dart';

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

    final apiButton = find.byTooltip('Gemini API ключ');
    expect(apiButton, findsOneWidget);
    await tester.ensureVisible(apiButton);
    await tester.tap(apiButton);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Gemini API ключ'), findsOneWidget);
    expect(find.text('Запази ключа'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
