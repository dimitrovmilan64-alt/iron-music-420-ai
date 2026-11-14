import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ironmusic420ai/main.dart';
import 'package:ironmusic420ai/pages/chat_page.dart';
import 'package:ironmusic420ai/pages/onboarding_page.dart';
import 'package:ironmusic420ai/pages/rap_studio_page.dart';
import 'package:ironmusic420ai/pages/settings_page.dart';
import 'package:ironmusic420ai/pages/songs_page.dart';
import 'package:ironmusic420ai/services/gemini_service.dart';
import 'package:ironmusic420ai/services/hey_iron_controller.dart';
import 'package:ironmusic420ai/services/local_store.dart';
import 'package:ironmusic420ai/theme/iron_theme.dart';

http.Response _jsonOk(Object body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

MockClient _geminiClient(String text) {
  return MockClient((request) async {
    if (request.method == 'GET') {
      return _jsonOk({
        'models': [
          {
            'name': 'models/gemini-2.5-flash',
            'supportedGenerationMethods': ['generateContent'],
          },
        ],
      });
    }
    return _jsonOk({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': text},
            ],
          },
        },
      ],
    });
  });
}

Future<LocalStore> _store({bool onboardingComplete = true}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (onboardingComplete) 'onboarding_complete_v2': true,
  });
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  final store = LocalStore();
  await store.initialize();
  return store;
}

Widget _app(Widget child) {
  return MaterialApp(
    theme: ironTheme(),
    home: Scaffold(backgroundColor: ironDark, body: child),
  );
}

void _phoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _pageScroll() {
  return find.byWidgetPredicate((widget) {
    return widget is Scrollable &&
        widget.axisDirection == AxisDirection.down &&
        widget.restorationId == null;
  }).first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboarding completes and reaches the main shell', (tester) async {
    final store = await _store(onboardingComplete: false);
    await tester.pumpWidget(IronMusic420App(store: store));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.text('Това е Iron'), findsOneWidget);
    await tester.tap(find.text('Напред'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Напред'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Започни'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
  });

  testWidgets('chat send and receive uses Gemini', (tester) async {
    final store = await _store();
    await store.setApiKey('AIza-test');
    final service = GeminiService(
      client: _geminiClient('Ето припев за града.'),
    );
    addTearDown(service.dispose);

    await tester.pumpWidget(_app(ChatPage(store: store, gemini: service)));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField).first, 'Напиши припев');
    await tester.tap(find.byTooltip('Изпрати'));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Ето припев за града.').evaluate().isNotEmpty) break;
    }

    expect(find.text('Напиши припев'), findsOneWidget);
    expect(find.text('Ето припев за града.'), findsOneWidget);
  });

  testWidgets('studio generation fills style and exclude fields', (tester) async {
    final store = await _store();
    _phoneSurface(tester);
    await store.setApiKey('AIza-test');
    const lyrics = '[Verse 1]\nКуплет тук\n\n[Chorus]\nПрипев тук';
    final service = GeminiService(client: _geminiClient(lyrics));
    addTearDown(service.dispose);

    await tester.pumpWidget(_app(RapStudioPage(store: store, gemini: service)));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.widgetWithText(TextField, 'Пиши тук…'), 'улица и нощ');
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Създай цяла песен'),
      300,
      scrollable: _pageScroll(),
    );
    await tester.tap(find.text('Създай цяла песен'));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('Куплет тук').evaluate().isNotEmpty) break;
    }

    expect(find.textContaining('Куплет тук'), findsWidgets);
    expect(find.text('Копирай текста'), findsOneWidget);
    expect(find.text('Копирай за Suno'), findsOneWidget);
    expect(find.text('Запази'), findsOneWidget);
    expect(find.text('Copy Lyrics'), findsNothing);
    await tester.drag(_pageScroll(), const Offset(0, -900));
    await tester.pump();
    expect(find.text('Стил на музиката'), findsWidgets);

    final styleField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            (widget.decoration?.hintText ?? '').contains('автоматично'),
      ),
    );
    expect(styleField.controller!.text, isNotEmpty);
    expect(styleField.controller!.text, contains('BPM'));

    final excludeField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            (widget.decoration?.hintText ?? '') == 'Нежелани елементи',
      ),
    );
    expect(excludeField.controller!.text, isNotEmpty);
    expect(excludeField.controller!.text, contains('female vocal'));
  });

  testWidgets('copy and save to Моите песни, then songs filter works',
      (tester) async {
    final store = await _store();
    _phoneSurface(tester);
    await store.saveRapState(draft: '[Chorus]\nПрипев за запис', result: '[Chorus]\nПрипев за запис');
    await tester.pumpWidget(_app(RapStudioPage(store: store)));
    await tester.pump(const Duration(milliseconds: 400));

    final scrollState = tester.state<ScrollableState>(_pageScroll());
    scrollState.position.jumpTo(scrollState.position.maxScrollExtent * 0.35);
    await tester.pump();
    await tester.tap(find.text('Формат за Suno'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
        .hideCurrentSnackBar();
    await tester.pump();

    await tester.tap(find.text('Копирай текста'));
    await tester.pump();
    await tester.tap(find.text('Запази'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(store.songProjects, isNotEmpty);
    expect(store.songProjects.first.lyrics, contains('Припев за запис'));
    expect(store.songProjects.first.musicPrompt, isNotEmpty);
    expect(store.songProjects.first.excludePrompt, isNotEmpty);

    await tester.pumpWidget(
      _app(SongsPage(
        store: store,
        onOpenStudio: () {},
      )),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Филтър по стил'), findsOneWidget);
    expect(find.textContaining('Припев за запис'), findsWidgets);
  });

  testWidgets('settings shows keys, voice picker and Hey Iron toggle',
      (tester) async {
    final store = await _store();
    _phoneSurface(tester);
    await tester.pumpWidget(_app(SettingsPage(store: store, heyIron: HeyIronController())));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Запази AI доставчиците'), findsOneWidget);
    expect(find.text('Гласови отговори'), findsOneWidget);
    expect(find.textContaining('Глас'), findsWidgets);
    expect(find.byType(SwitchListTile), findsWidgets);
  });

  testWidgets('header sits below a simulated Android 15 status bar',
      (tester) async {
    final store = await _store();
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(IronMusic420App(store: store));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Iron'), findsOneWidget);
    final title = tester.getRect(find.text('Iron').first);
    expect(title.top, greaterThanOrEqualTo(48));
  });
}
