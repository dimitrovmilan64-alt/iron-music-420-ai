import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('wake word is strict and command recognition is one-shot', () {
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();
    final keywordScript =
        File('scripts/prepare_sherpa_kws.sh').readAsStringSync();

    expect(service, contains('keywordsScore = 1.5f'));
    expect(service, contains('keywordsThreshold = 0.25f'));
    expect(service, contains('WAKE_MIN_RMS'));
    expect(service, isNot(contains('queueRecognizedPhrase')));
    expect(service, isNot(contains('Iron опитва микрофона отново')));
    expect(keywordScript, isNot(contains('("IRON_')));
  });

  test('YouTube song commands carry a query to the YouTube app', () {
    final parser = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/LocalVoiceCommandParser.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();

    expect(parser, contains('action = "youtube_search"'));
    expect(service, contains('Intent(Intent.ACTION_SEARCH)'));
    expect(service, contains('SearchManager.QUERY'));
    expect(service, contains('results?search_query='));
  });
}
