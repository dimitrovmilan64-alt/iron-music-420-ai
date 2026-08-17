import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('build 74 exposes a living system orb without replacing Iron chat', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final orb = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronOrbService.kt',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();
    final automation =
        File('lib/services/automation_service.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(manifest, contains('android.permission.SYSTEM_ALERT_WINDOW'));
    expect(manifest, contains('android:name=".IronOrbService"'));
    expect(orb, contains('TYPE_APPLICATION_OVERLAY'));
    expect(orb, contains('chooseNewTarget'));
    expect(orb, contains('moveRunnable'));
    expect(orb, contains('iron_orb_conversation'));
    expect(orb, contains('setOnClickListener { openConversation() }'));

    expect(activity, contains('Settings.ACTION_MANAGE_OVERLAY_PERMISSION'));
    expect(activity, contains('restoreIronOrbIfEnabled()'));
    expect(activity, contains('consumeIronOrbConversationRequest'));
    expect(automation, contains('Future<bool> isIronOrbActive()'));
    expect(automation, contains('setIronOrbState'));
    expect(main, contains('_startOrbConversation'));
    expect(main, contains('startNativeSpeechRecognition'));
    expect(main, contains('queueChatVoiceRequest'));
    expect(chat, contains('Покажи живата сфера върху всички приложения'));
    expect(chat, contains("'thinking'"));
    expect(chat, contains("'speaking'"));
    expect(pubspec, contains('version: 3.4.0+74'));
  });
}
