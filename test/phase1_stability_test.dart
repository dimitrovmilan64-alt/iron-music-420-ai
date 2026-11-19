
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ironmusic420ai/main.dart';
import 'package:ironmusic420ai/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CI skips sherpa models while the wake-word service is disabled', () {
    final script = File('scripts/prepare_sherpa_kws.sh').readAsStringSync();
    final workflow = File('.github/workflows/android-build.yml').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final codeql = File('.github/workflows/codeql.yml').readAsStringSync();

    expect(script, contains('SERVICE_ENABLED = true'));
    expect(script, contains('skipping keyword model download'));
    expect(workflow, contains('Hey Iron is disabled'));
    expect(gradle, contains('libsherpa-onnx*.so'));
    expect(codeql, contains("flutter-version: '3.47.9'"));
    expect(codeql, isNot(contains("flutter-version: '3.27.0'")));
  });

  test('Impeller stays disabled', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      manifest,
      contains('io.flutter.embedding.android.EnableImpeller'),
    );
    expect(
      manifest,
      contains('android:value="false"'),
    );
  });

  test('plaintext API keys migrate once into secure storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'gemini_api_key': 'AIza-legacy',
      'backup_api_key': 'gsk-legacy',
    });
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    final store = LocalStore();
    await store.initialize();

    expect(store.apiKey, 'AIza-legacy');
    expect(store.backupApiKey, 'gsk-legacy');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('gemini_api_key'), isFalse);
    expect(prefs.containsKey('backup_api_key'), isFalse);

    await store.setApiKey('AIza-new');
    expect(prefs.containsKey('gemini_api_key'), isFalse);
    expect(store.apiKey, 'AIza-new');
  });

  testWidgets('settings tab is reachable and nav highlight stays in sync',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_complete_v2': true,
    });
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final store = LocalStore();
    await store.initialize();

    await tester.pumpWidget(IronMusic420App(store: store));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    expect(find.text('Хей Айрън'), findsWidgets);
    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Добави AI ключ, за да започнеш'), findsOneWidget);

    await tester.tap(find.text('Настройки'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('AI доставчици'), findsWidgets);
    expect(find.text('Запази AI доставчиците'), findsOneWidget);
  });
}
