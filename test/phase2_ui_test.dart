import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ironmusic420ai/main.dart';
import 'package:ironmusic420ai/models/chat_message.dart';
import 'package:ironmusic420ai/models/song_project.dart';
import 'package:ironmusic420ai/pages/onboarding_page.dart';
import 'package:ironmusic420ai/services/local_store.dart';

Future<ByteData> _fileBytes(String path) async {
  final bytes = File(path).readAsBytesSync();
  return ByteData.view(Uint8List.fromList(bytes).buffer);
}

Future<void> _loadInter() async {
  final inter = await rootBundle.load('assets/fonts/InterVariable.ttf');
  await (FontLoader('Inter')..addFont(Future.value(inter))).load();

  const iconPath =
      '/home/box/sdk/flutter-3.47.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  if (File(iconPath).existsSync()) {
    final icons = await _fileBytes(iconPath);
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
  }
}

Future<void> _prepareStore({required bool onboardingComplete}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (onboardingComplete) 'onboarding_complete_v2': true,
  });
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
}

Future<void> _saveShot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('iron-shot')),
    );
    final image = await boundary.toImage(pixelRatio: 2.6);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('/workspace/iron-shots');
    dir.createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboarding has three screens and can be finished', (tester) async {
    await _loadInter();
    await _prepareStore(onboardingComplete: false);
    final store = LocalStore();
    await store.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Inter', useMaterial3: true, brightness: Brightness.dark),
        home: OnboardingPage(store: store),
      ),
    );
    await tester.pump();
    expect(find.text('Това е Iron'), findsOneWidget);
    expect(find.text('Пропусни'), findsOneWidget);
    await tester.tap(find.text('Напред'));
    await tester.pumpAndSettle();
    expect(find.text('Говори или пиши'), findsOneWidget);
    await tester.tap(find.text('Напред'));
    await tester.pumpAndSettle();
    expect(find.text('Студио и ключ'), findsOneWidget);
    await tester.tap(find.text('Започни'));
    await tester.pumpAndSettle();
    expect(store.onboardingComplete, isTrue);
  });

  testWidgets('modern shell uses NavigationBar and conversation-first chat',
      (tester) async {
    await _loadInter();
    await _prepareStore(onboardingComplete: true);
    final store = LocalStore();
    await store.initialize();
    await store.setApiKey('AIza-test');
    await store.replaceChatHistory([
      ChatMessage(
        text: 'Аз съм Айрън. Говори или пиши тук — това е единният ни разговор.',
        isUser: false,
        isLocalNotice: true,
        createdAt: DateTime(2026, 11, 13, 20),
      ),
      ChatMessage(
        text: 'Напиши припев за нощта в града.',
        isUser: true,
        createdAt: DateTime(2026, 11, 13, 20, 1),
      ),
      ChatMessage(
        text: '[Припев]\nНеонови улици, сърцето не спи.',
        isUser: false,
        createdAt: DateTime(2026, 11, 13, 20, 2),
      ),
    ]);

    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(IronMusic420App(store: store));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Хей Айрън'), findsWidgets);
    expect(find.text('Готов за разговор'), findsOneWidget);
    expect(find.text('Напиши или говори с Iron...'), findsOneWidget);

    await tester.tap(find.text('Студио'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Рап студио'), findsOneWidget);

    await tester.tap(find.text('Песни'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Песни'), findsWidgets);
    expect(find.byTooltip('Филтър по стил'), findsOneWidget);

    await tester.tap(find.text('Настройки'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Запази AI доставчиците'), findsOneWidget);
  });

  testWidgets('write phone screenshots with the Inter font', (tester) async {
    await _loadInter();
    await _prepareStore(onboardingComplete: false);
    var store = LocalStore();
    await store.initialize();

    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pumpShot(Widget app) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('iron-shot'),
          child: app,
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpShot(IronMusic420App(store: store));
    expect(find.text('Това е Iron'), findsOneWidget);
    await _saveShot(tester, 'onboarding-1-welcome');
    await tester.tap(find.text('Напред'));
    await tester.pumpAndSettle();
    await _saveShot(tester, 'onboarding-2-voice');
    await tester.tap(find.text('Напред'));
    await tester.pumpAndSettle();
    await _saveShot(tester, 'onboarding-3-studio');

    await _prepareStore(onboardingComplete: true);
    store = LocalStore();
    await store.initialize();
    await store.setApiKey('AIza-test');
    await store.replaceChatHistory([
      ChatMessage(
        text: 'Аз съм Айрън. Говори или пиши тук — това е единният ни разговор.',
        isUser: false,
        isLocalNotice: true,
        createdAt: DateTime(2026, 11, 13, 20),
      ),
      ChatMessage(
        text: 'Напиши припев за нощта в града.',
        isUser: true,
        createdAt: DateTime(2026, 11, 13, 20, 1),
      ),
      ChatMessage(
        text: '[Припев]\nНеонови улици, сърцето не спи, а римата държи ритъма жив.',
        isUser: false,
        createdAt: DateTime(2026, 11, 13, 20, 2),
      ),
    ]);
    await store.upsertSong(
      SongProject.create(
        title: 'Неонови улици',
        lyrics: '[Припев]\nНеонови улици, сърцето не спи.',
        musicPrompt: 'Dark Bulgarian trap, 140 BPM',
        theme: 'Нощ в града',
        style: 'Hard trap',
        mood: 'Тъмно и агресивно',
        rhymeScheme: 'AABB',
        bpm: 140,
      ),
    );

    await pumpShot(IronMusic420App(store: store));
    await _saveShot(tester, 'after-chat');

    await tester.tap(find.text('Студио'));
    await tester.pumpAndSettle();
    await _saveShot(tester, 'after-studio');

    await tester.tap(find.text('Песни'));
    await tester.pumpAndSettle();
    await _saveShot(tester, 'after-songs');

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    await _saveShot(tester, 'after-settings');

    await tester.scrollUntilVisible(
      find.text('Инструменти'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await _saveShot(tester, 'after-tools');
  });
}
