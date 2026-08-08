import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local commands stay native and free conversation enters one chat', () {
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();
    final localIndex = service.indexOf('LocalVoiceCommandParser.parse');
    final chatIndex = service.indexOf('openIronChatPrompt(originalCommand)');

    expect(localIndex, greaterThanOrEqualTo(0));
    expect(chatIndex, greaterThan(localIndex));
    expect(service, contains('executeLocalVoiceCommand'));
    expect(service, contains('openIronStudioRequest'));
    expect(service, isNot(contains('GeminiVoiceRouter')));
    expect(service, isNot(contains('executeCommand(')));
  });

  test('parser includes bilingual phone and music commands', () {
    final parser = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/LocalVoiceCommandParser.kt',
    ).readAsStringSync();

    for (final phrase in [
      'отвори чата',
      'open chat',
      'музикален режим',
      'music mode',
      'направи рап текст',
      'дай рими',
      'направи припев',
    ]) {
      expect(parser, contains(phrase));
    }
    expect(parser, contains('hasAny("фенер"'));
    expect(parser, contains('hasAny("включи"'));
    expect(parser, contains('"turn on"'));
  });

  test('native Studio request reaches the existing Rap Studio generator', () {
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();
    final automation =
        File('lib/services/automation_service.dart').readAsStringSync();
    final store = File('lib/services/local_store.dart').readAsStringSync();
    final studio = File('lib/pages/rap_studio_page.dart').readAsStringSync();

    expect(activity, contains('consumeStudioVoiceRequest'));
    expect(automation, contains('consumeStudioVoiceRequest'));
    expect(store, contains('queueStudioVoiceRequest'));
    expect(studio, contains('_applyPendingStudioVoiceRequest'));
    expect(studio, contains('_generateWithAi()'));
  });

  test('offline wake list contains only calibrated full Hey Iron phrases', () {
    final script = File('scripts/prepare_sherpa_kws.sh').readAsStringSync();
    expect(script, contains('HEY_IRON_LEX'));
    expect(script, contains('HEY_IRON_BG'));
    expect(script, contains('6.5, 0.03'));
    expect(script, isNot(contains('HEY_AARON')));
    expect(script, isNot(contains('NO_H')));
  });
}
