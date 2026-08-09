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
    expect(chat, contains('_buildHudDashboard()'));
    expect(chat, contains('_buildChatMode()'));
    expect(chat, contains("'IRON'"));
    expect(chat, contains('_bottomHudAction'));
    expect(chat, contains('_voiceWavePanel'));
    expect(chat, contains("title: 'CHAT'"));
    expect(chat, contains("title: 'COMMANDS'"));
    expect(chat, contains("title: 'MUSIC MODE'"));
    expect(chat, contains("title: 'KEYBOARD'"));
    expect(chat, contains("'HEY IRON'"));
    expect(chat, contains('IronCoreState.speaking'));
    expect(chat, contains("'MUSIC 420 AI'"));
    expect(chat, isNot(contains('GridView.count')));
    expect(chat, isNot(contains("title: 'FLASHLIGHT'")));
    expect(chat, isNot(contains('Активен • глас и чат на едно място')));
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

  test('living core has depth and distinct interaction states', () {
    final widgets = File('lib/ui/common_widgets.dart').readAsStringSync();

    expect(widgets, contains('enum IronCoreState'));
    expect(widgets, contains('class _IronCoreSpherePainter'));
    expect(widgets, contains('class _IronCoreMachineRingPainter'));
    expect(widgets, contains('class _IronCoreGlassPainter'));
    expect(widgets, contains('class _IronCorePedestalPainter'));
    expect(widgets, contains('class _IronCoreLeafPainter'));
    expect(widgets, contains('Matrix4.identity()'));
    expect(widgets, contains('rotateY(leafTurn)'));
    expect(widgets, contains('Size.square(size * 0.62)'));
    expect(widgets, contains('class _LivingLeafVeinPainter'));
    expect(widgets, contains('leafPulse'));
    expect(widgets, contains('_leafSilhouette'));
    expect(widgets, contains('canvas.clipPath(leafMask)'));
    expect(widgets, contains('PathOperation.union'));
    expect(widgets, contains('castShadowPaint'));
    expect(widgets, contains('innerDepthPaint'));
    expect(widgets, isNot(contains('class _CannabisLeafPainter')));
    expect(widgets, isNot(contains('_drawTinyLeaf')));
    expect(widgets, contains('IronCoreState.listening'));
    expect(widgets, contains('IronCoreState.thinking'));
    expect(widgets, contains('IronCoreState.speaking'));

    final chat = File('lib/pages/chat_page.dart').readAsStringSync();
    expect(chat, contains("'РАЗГОВОР С IRON'"));
    expect(chat, contains('Назад към ядрото'));
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
