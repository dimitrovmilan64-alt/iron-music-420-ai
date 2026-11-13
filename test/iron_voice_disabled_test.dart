import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Hey Iron stays disabled until SERVICE_ENABLED is turned back on', () {
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();
    final flags = File('lib/services/iron_voice_flags.dart').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(service, contains('const val SERVICE_ENABLED = false'));
    expect(flags, contains('const bool ironVoiceServiceEnabled = false'));
    expect(flags, contains('„Hey Iron“ е временно изключен'));
    expect(chat, contains('ironVoiceServiceEnabled'));
    expect(chat, contains('ironVoiceDisabledMessage'));
    expect(activity, contains('isIronVoiceServiceAvailable()'));
    expect(activity, contains('rejectIronVoiceIfUnavailable(result)'));
    expect(
      activity,
      contains('getBoolean(IronVoiceService.KEY_VOICE_ENABLED, false)'),
    );
    expect(activity, contains('IRON_VOICE_DISABLED'));
    expect(activity, contains('„Hey Iron“ е временно изключен'));
    expect(chat, contains('„Hey Iron“ е временно изключен'));
    expect(chat, contains('_ironActive = false'));
    expect(
      manifest,
      contains(
        'IronVoiceService temporarily disabled to prevent system freeze on launch',
      ),
    );
    expect(
      manifest.contains('<service') &&
          manifest.contains('android:name=".IronVoiceService"') &&
          !manifest.contains(
            '<!-- IronVoiceService temporarily disabled to prevent system freeze on launch -->',
          ),
      isFalse,
    );
  });
}
