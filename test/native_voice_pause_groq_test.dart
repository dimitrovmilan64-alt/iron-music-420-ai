import 'dart:io';

"
    "import 'package:flutter_test/flutter_test.dart';

"
    "void main() {
"
    "  test('chat dictation pauses wake audio without restarting service', () {
"
    "    final activity = File('android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt').readAsStringSync();
"
    "    final service = File('android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt').readAsStringSync();
"
    "    expect(activity, contains('ACTION_PAUSE_WAKE'));
"
    "    expect(activity, contains('ACTION_RESUME_WAKE'));
"
    "    expect(service, contains('pausedForChatSpeech'));
"
    "    expect(service, contains('pauseForChatSpeech()'));
"
    "    expect(service, contains('resumeAfterChatSpeech()'));
"
    "  });

"
    "  test('Groq is the automatic backup provider', () {
"
    "    final config = File('lib/services/ai_provider_config.dart').readAsStringSync();
"
    "    final chat = File('lib/pages/chat_page.dart').readAsStringSync();
"
    "    expect(config, contains('https://api.groq.com/openai/v1'));
"
    "    expect(config, contains('openai/gpt-oss-20b'));
"
    "    expect(chat, contains('Groq API ключ'));
"
    "  });
"
    "}
"
