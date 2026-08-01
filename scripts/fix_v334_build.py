from pathlib import Path

chat_path = Path('lib/pages/chat_page.dart')
chat = chat_path.read_text(encoding='utf-8')
old = '                  const Container(\n'
new = '                  Container(\n'
if old not in chat:
    raise SystemExit('Expected Groq Container declaration not found')
chat_path.write_text(chat.replace(old, new, 1), encoding='utf-8')

test_path = Path('test/native_voice_pause_groq_test.dart')
test_path.write_text("""import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat dictation pauses wake audio without restarting service', () {
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();

    expect(activity, contains('ACTION_PAUSE_WAKE'));
    expect(activity, contains('ACTION_RESUME_WAKE'));
    expect(activity, isNot(contains('stopService(')));
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
""", encoding='utf-8')
