import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('build 76 keeps the exact leaf artwork and complete 360 degree orbits', () {
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
    expect(orb, isNot(contains('chooseNewTarget')));
    expect(orb, isNot(contains('java.util.Random')));
    expect(orb, contains('MotionEvent.ACTION_MOVE'));
    expect(orb, contains('moveOrb(deltaX, deltaY)'));
    expect(orb, contains('saveOrbPosition()'));
    expect(orb, contains('serratedLeaflet'));
    expect(orb, contains('drawExactLeaf'));
    expect(orb, contains('drawGlassSphere'));
    expect(orb, contains('flutter_assets/assets/images/hud_core_exact.png'));
    expect(orb, contains('drawFullOrbitLines'));
    expect(orb, contains('canvas.drawOval'));
    expect(orb, contains('0.86f + index * 0.018f'));
    expect(orb, contains('animateRunnable'));
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
    expect(pubspec, contains('version: 3.4.0+77'));
  });
}
