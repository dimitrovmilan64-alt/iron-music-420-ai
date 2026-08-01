import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat dictation pauses wake audio without restarting service', () {
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();

    final prepareStart = activity.indexOf(
      'private fun prepareChatSpeechRecognition()',
    );
    final launchStart = activity.indexOf(
      'private fun launchChatSpeechRecognizer()',
    );
    expect(prepareStart, greaterThanOrEqualTo(0));
    expect(launchStart, greaterThan(prepareStart));
    final prepareBlock = activity.substring(prepareStart, launchStart);

    final finishStart = activity.indexOf('private fun finishChatSpeech(');
    final syncStart = activity.indexOf('private fun syncGeminiApiKey(');
    expect(finishStart, greaterThanOrEqualTo(0));
    expect(syncStart, greaterThan(finishStart));
    final finishBlock = activity.substring(finishStart, syncStart);

    expect(prepareBlock, contains('ACTION_PAUSE_WAKE'));
    expect(prepareBlock, isNot(contains('ACTION_STOP')));
    expect(prepareBlock, isNot(contains('stopService(')));
    expect(finishBlock, contains('ACTION_RESUME_WAKE'));
    expect(finishBlock, isNot(contains('ACTION_START')));
    expect(service, contains('pausedForChatSpeech'));
    expect(service, contains('pauseForChatSpeech()'));
    expect(service, contains('resumeAfterChatSpeech()'));
  });

  test('Groq is the automatic backup provider', () {
    final config = File(
      'lib/services/ai_provider_config.dart',
    ).readAsStringSync();
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();

    expect(config, contains('https://api.groq.com/openai/v1'));
    expect(config, contains('openai/gpt-oss-20b'));
    expect(chat, contains('Groq API ключ'));
    expect(chat, contains('Адресът и моделът се настройват автоматично'));
  });
}
