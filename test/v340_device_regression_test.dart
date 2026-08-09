import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main navigation exposes the clean Hey Iron core', () {
    final main = File('lib/main.dart').readAsStringSync();
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();

    expect(main, contains("label: 'Хей Айрън'"));
    expect(main, contains('onOpenStudio: () => _openSection(1)'));
    expect(main, contains('onOpenSongs: () => _openSection(2)'));
    expect(main, contains('_currentIndex == 0'));
    expect(chat, contains("'IRON'"));
    expect(chat, contains("_chatPanelOpen ? _buildChatMode() : _buildHudDashboard()"));
    expect(chat, contains('_bottomHudAction'));
    expect(chat, contains("title: 'CHAT'"));
    expect(chat, contains("title: 'COMMANDS'"));
    expect(chat, contains("title: 'KEYBOARD'"));
    expect(chat, contains("'HEY IRON'"));
    expect(chat, contains("'MUSIC 420 AI'"));
    expect(chat, isNot(contains('GridView.count')));
    expect(File('lib/pages/home_page.dart').existsSync(), isFalse);
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

  test('build 54 keeps the reliable guarded full wake phrase', () {
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();
    final keywordScript =
        File('scripts/prepare_sherpa_kws.sh').readAsStringSync();

    expect(service, contains('keywordsScore = 1.5f'));
    expect(service, contains('keywordsThreshold = 0.25f'));
    expect(service, contains('maxActivePaths = 4'));
    expect(service, contains('WAKE_MIN_RMS = 0.006f'));
    expect(service, contains('MIN_WAKE_VOICED_FRAMES = 2'));
    expect(service, contains('WAKE_SIGNAL_HOLD_MS = 1_500L'));
    expect(service, contains('WAKE_REARM_COOLDOWN_MS = 4_000L'));
    expect(service, contains('WakeActivationGuard('));
    expect(service, contains('VoicePromptGuard('));
    expect(service, contains('numTrailingBlanks = 1'));
    expect(service, contains('wake_health frames='));
    expect(service, isNot(contains('queueRecognizedPhrase')));
    expect(service, isNot(contains('Iron опитва микрофона отново')));
    expect(keywordScript, contains('6.5, 0.03'));
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

  test('build 54 keeps any-song auto-play one-shot and YouTube-only', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final config = File(
      'android/app/src/main/res/xml/youtube_autoplay_accessibility_service.xml',
    ).readAsStringSync();
    final autoPlay = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/YoutubeAutoPlayAccessibilityService.kt',
    ).readAsStringSync();
    final commands = File('lib/pages/commands_page.dart').readAsStringSync();

    expect(
      manifest,
      contains('android.permission.BIND_ACCESSIBILITY_SERVICE'),
    );
    expect(config, contains('android:packageNames="com.google.android.youtube"'));
    expect(config, contains('android:canRetrieveWindowContent="true"'));
    expect(config, isNot(contains('canPerformGestures')));
    expect(autoPlay, contains('REQUEST_LIFETIME_MS = 15_000L'));
    expect(autoPlay, contains('clearPending(this)'));
    expect(autoPlay, contains('AccessibilityNodeInfo.ACTION_CLICK'));
    expect(
      autoPlay,
      contains('resultScore = if (score == Int.MIN_VALUE) 0 else score'),
    );
    expect(autoPlay, isNot(contains('dispatchGesture')));
    expect(commands, contains('Не чете други приложения'));
    expect(commands, contains('ВКЛЮЧИ В ДОСТЪПНОСТ'));
  });
}
