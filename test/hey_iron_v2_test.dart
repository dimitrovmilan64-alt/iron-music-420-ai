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
}
