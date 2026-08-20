import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wake free conversation is delivered to the existing chat', () {
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();
    final automation =
        File('lib/services/automation_service.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final store = File('lib/services/local_store.dart').readAsStringSync();
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();

    expect(service, contains('putExtra("iron_chat_prompt", cleanPrompt)'));
    expect(activity, contains('"consumeChatVoiceRequest"'));
    expect(activity, contains('getStringExtra("iron_chat_prompt")'));
    expect(automation, contains('consumeChatVoiceRequest()'));
    expect(main, contains('widget.store.queueChatVoiceRequest(chatPrompt)'));
    expect(store, contains('takePendingChatVoiceRequest()'));
    expect(chat, contains('_consumePendingChatVoiceRequest()'));
    expect(chat, contains('await _sendMessage()'));
  });

  test('Hey Iron controls live in the chat and duplicate AI code is gone', () {
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();
    final commands = File('lib/pages/commands_page.dart').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();

    expect(chat, contains('_toggleIronMode()'));
    expect(chat, contains("'ХЕЙ АЙРЪН АКТИВЕН'"));
    expect(commands, isNot(contains('АКТИВИРАЙ IRON')));
    expect(commands, isNot(contains('ОТВОРИ AI РАЗГОВОРА')));
    expect(activity, isNot(contains('syncAiProviderSettings')));
    expect(
      File(
        'android/app/src/main/kotlin/com/example/ironmusic420ai/GeminiVoiceRouter.kt',
      ).existsSync(),
      isFalse,
    );
  });

  test('duplicate native prompts cannot flood the unified chat queue', () {
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();
    final store = File('lib/services/local_store.dart').readAsStringSync();

    expect(service, contains('VoicePromptGuard.Decision.BARE_WAKE_PHRASE'));
    expect(service, contains('VoicePromptGuard.Decision.DUPLICATE'));
    expect(service, contains('command_ignored reason=bare_wake_phrase'));
    expect(service, contains('command_ignored reason=duplicate_chat_prompt'));
    expect(store, contains('alreadyPending'));
  });
}
