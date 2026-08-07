import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home screen reports the current 3.4.0 version', () {
    final home = File('lib/pages/home_page.dart').readAsStringSync();

    expect(home, contains('Версия 3.4.0'));
    expect(home, isNot(contains('Версия 3.1.0')));
  });

  test('v3.4.0 flashlight uses one native controller and real state', () {
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();
    final voiceService = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();
    final automation =
        File('lib/services/automation_service.dart').readAsStringSync();
    final commands = File('lib/pages/commands_page.dart').readAsStringSync();

    expect(activity, contains('"flash_status"'));
    expect(activity, contains('FlashlightController.setEnabled'));
    expect(voiceService, contains('FlashlightController.setEnabled'));
    expect(automation, contains('Future<bool?> flashlightState()'));
    expect(commands, contains('nativeState ?? _flashlightOn'));
  });

  test('wake word uses a full calibrated phrase and recognition is one-shot', () {
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();
    final keywordScript =
        File('scripts/prepare_sherpa_kws.sh').readAsStringSync();

    expect(service, contains('keywordsScore = 1.5f'));
    expect(service, contains('keywordsThreshold = 0.25f'));
    expect(service, contains('maxActivePaths = 8'));
    expect(service, contains('WAKE_MIN_RMS'));
    expect(service, contains('wake_health frames='));
    expect(service, isNot(contains('queueRecognizedPhrase')));
    expect(service, isNot(contains('Iron опитва микрофона отново')));
    expect(keywordScript, contains('7.0, 0.01'));
    expect(keywordScript, isNot(contains('("IRON_')));
    expect(keywordScript, isNot(contains('LEX_NO_H')));
  });

  test('YouTube song commands carry a query to the YouTube app', () {
    final parser = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/LocalVoiceCommandParser.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();

    expect(parser, contains('action = "youtube_search"'));
    expect(service, contains('MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH'));
    expect(service, contains('MediaStore.EXTRA_MEDIA_FOCUS'));
    expect(service, contains('MediaStore.EXTRA_MEDIA_TITLE'));
    expect(service, contains('SearchManager.QUERY'));
    expect(service, contains('Intent(Intent.ACTION_VIEW, resultsUri)'));
    expect(service, contains('results?search_query='));
    expect(service, isNot(contains('Intent(Intent.ACTION_SEARCH)')));
  });
}
