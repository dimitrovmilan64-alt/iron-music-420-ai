import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironmusic420ai/services/hey_iron_controller.dart';

void main() {
  test('Hey Iron v2 bundles a small keyword model and uses a safe engine', () {
    final engine = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/HeyIronEngine.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/HeyIronForegroundService.kt',
    ).readAsStringSync();
    final old = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();
    final script = File('scripts/prepare_sherpa_kws.sh').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final flags = File('lib/services/iron_voice_flags.dart').readAsStringSync();
    final controller =
        File('lib/services/hey_iron_controller.dart').readAsStringSync();
    final watchdog =
        File('lib/services/hey_iron_watchdog.dart').readAsStringSync();
    final bridge = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/HeyIronBridge.kt',
    ).readAsStringSync();

    expect(old, contains('const val SERVICE_ENABLED = false'));
    expect(flags, contains('const bool ironVoiceServiceEnabled = false'));
    expect(engine, contains('numThreads = 1'));
    expect(engine, contains('Thread.sleep(backoffMs)'));
    expect(service, contains('START_NOT_STICKY'));
    expect(service, contains('a kill cannot restart-storm'));
    expect(manifest, contains('HeyIronForegroundService'));
    expect(manifest, contains('android:stopWithTask="true"'));
    expect(manifest, contains('EnableImpeller'));
    expect(manifest, contains('android:value="false"'));
    expect(script, contains('small Hey Iron keyword model'));
    expect(script, contains('assets/hey_iron'));
    expect(script, contains('check_hey_iron_native.py'));
    expect(engine, contains('installBundledModel'));
    expect(bridge, contains('prepareModel'));
    expect(gradle, contains('keepSherpaNative'));
    expect(controller, contains('backgroundExperimental'));
    expect(controller, contains('prepareModel'));
    expect(controller, contains('Подготвям вградения офлайн модел'));
    expect(controller, isNot(contains('Трябва да се изтегли офлайн модел')));
    final settings = File('lib/pages/settings_page.dart').readAsStringSync();
    expect(settings, contains('Моделът е вграден в приложението'));
    expect(settings, isNot(contains('се изтегля офлайн модел')));
    expect(settings, isNot(contains('31.4')));
    final proguard = File('android/app/proguard-rules.pro').readAsStringSync();
    expect(proguard, contains('-keep class com.k2fsa.sherpa.onnx.** { *; }'));
    expect(proguard,
        contains('-keepclassmembers class com.k2fsa.sherpa.onnx.** { *; }'));
    final workflow =
        File('.github/workflows/android-build.yml').readAsStringSync();
    expect(workflow, contains('check_hey_iron_jni_fields.py'));
    expect(watchdog, contains('maxFailures = 3'));
    final keywords = File('assets/hey_iron/keywords.txt').readAsStringSync();
    expect(keywords, contains('HEY_IRON'));
    expect(keywords, contains('HEY_IRON_BG'));
    expect(bridge, contains('fun resolvedArchiveFile'));
    expect(bridge, contains('canonicalFile'));
    expect(bridge, contains('parts.any { it == ".." }'));
    expect(bridge, contains('normalized.startsWith("/")'));
    expect(bridge, contains('throw SecurityException'));
    expect(bridge, isNot(contains('val name = File(entry.name).name')));
  });

  test('error status names Hey Iron instead of a bare Грешка', () {
    final controller = HeyIronController();
    controller.phase = HeyIronPhase.error;
    controller.message = 'Слушането спря да отговаря (подозрение за забиване).';
    expect(controller.statusLabel, isNot('Грешка'));
    expect(controller.statusLabel, startsWith('Хей Айрън:'));
    expect(controller.statusLabel, contains('Слушането спря'));
  });

  test('bundled keyword files and 16KB checker are present', () {
    expect(File('scripts/check_hey_iron_native.py').existsSync(), isTrue);
    expect(File('scripts/check_hey_iron_jni_fields.py').existsSync(), isTrue);
    expect(File('android/app/proguard-rules.pro').existsSync(), isTrue);
    expect(
      File('scripts/vendor/sherpa-onnx-1.13.4-jni/keyword-spotter.cc')
          .existsSync(),
      isTrue,
    );
    expect(File('assets/hey_iron/keywords.txt').existsSync(), isTrue);
    final checker = File('scripts/check_hey_iron_native.py').readAsStringSync();
    expect(checker, contains('0x4000'));
    expect(checker, contains('keywords.txt'));
    final androidKeywords =
        File('android/app/src/main/assets/hey_iron/keywords.txt');
    if (androidKeywords.existsSync()) {
      expect(androidKeywords.readAsStringSync(), contains('HEY_IRON_BG'));
    }
  });

  test('JNI field checker lists maxActivePaths from pinned sherpa sources',
      () async {
    final result = await Process.run('python3', <String>[
      'scripts/check_hey_iron_jni_fields.py',
      '--print-expected',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('KeywordSpotterConfig;.maxActivePaths I'));
    expect(result.stdout, contains('FeatureConfig;.sampleRate I'));
    expect(result.stdout, contains('OnlineModelConfig;.transducer'));
  });

  test('listening starts on first frame and the mic has a single owner', () {
    final engine = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/HeyIronEngine.kt',
    ).readAsStringSync();
    final bridge = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/HeyIronBridge.kt',
    ).readAsStringSync();
    final controller =
        File('lib/services/hey_iron_controller.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final settings = File('lib/pages/settings_page.dart').readAsStringSync();
    final keywords = File('assets/hey_iron/keywords.txt').readAsStringSync();

    expect(main, contains('handleAppResumed()'));
    expect(main, contains('addPostFrameCallback'));
    expect(bridge, contains('stopBackgroundService()'));
    expect(bridge, contains('"stopEngine"'));
    expect(bridge, contains('"testMic"'));
    expect(bridge, contains('ensureMicPermission'));
    expect(engine, contains('CountDownLatch'));
    expect(engine, contains('fun testMic'));
    expect(engine, contains('fun isListening'));
    expect(engine, contains('keywordsThreshold = 0.10f'));
    expect(engine, contains('overwriteKeywords = true'));
    expect(controller, contains("invokeMethod('stopEngine')"));
    expect(controller, contains('testMicrophone'));
    expect(controller, contains('lastDetectionLabel'));
    expect(settings, contains('Тест на микрофона'));
    expect(settings, contains('hey.lastDetectionLabel'));
    expect(keywords, contains('#0.10'));
    expect(keywords, contains('HEY_IRON_1_1'));
  });

  test('recorded hey iron wav is detected by the bundled keyword spotter',
      () async {
    expect(File('test/fixtures/hey_iron.wav').existsSync(), isTrue);
    expect(File('scripts/test_hey_iron_spotter.py').existsSync(), isTrue);
    final result = await Process.run('python3', <String>[
      'scripts/test_hey_iron_spotter.py',
      '--wav',
      'test/fixtures/hey_iron.wav',
      '--allow-skip',
    ]);
    final output = '${result.stdout}\n${result.stderr}';
    if (output.contains('SKIP:')) {
      return;
    }
    expect(result.exitCode, 0, reason: output);
    expect(output, contains('OK: detected'));
  });
}
