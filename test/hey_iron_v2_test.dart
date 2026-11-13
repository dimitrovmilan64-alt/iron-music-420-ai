import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Hey Iron v2 stays out of the APK bundle and uses a safe engine', () {
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
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final flags = File('lib/services/iron_voice_flags.dart').readAsStringSync();
    final controller = File('lib/services/hey_iron_controller.dart').readAsStringSync();
    final watchdog = File('lib/services/hey_iron_watchdog.dart').readAsStringSync();

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
    expect(script, contains('skipping keyword model download'));
    expect(script, contains('Never bundle them in the APK'));
    expect(gradle, contains('keepSherpaNative'));
    expect(controller, contains('backgroundExperimental'));
    expect(controller, contains('downloadModel'));
    expect(watchdog, contains('maxFailures = 3'));
    expect(File('assets/hey_iron/keywords.txt').readAsStringSync(), contains('HEY_IRON_BG'));
  });
}
