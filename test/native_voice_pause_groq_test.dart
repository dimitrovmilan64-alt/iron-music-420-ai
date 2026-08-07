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

  test('chat speech waits for wake capture and retries once', () {
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();

    expect(activity, contains('launchChatSpeechRecognizerWhenReady'));
    expect(activity, contains('IronVoiceService.isMicrophoneCaptureActive()'));
    expect(activity, contains('MAX_CHAT_SPEECH_RELEASE_CHECKS'));
    expect(activity, contains('chatSpeechAttemptTracker.canRetry()'));
    expect(activity, contains('retryChatSpeechRecognition(error)'));
    expect(service, contains('fun isMicrophoneCaptureActive()'));
    expect(service, contains('VoiceCaptureRegistry.isAnyCaptureActive()'));
  });

  test('stale callbacks cannot close a retried recognition attempt', () {
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('RecognitionAttemptTracker()'));
    expect(activity, contains('isCurrentChatSpeechAttempt'));
    expect(activity, contains('chatSpeechRecognizer === recognizer'));
    expect(activity, contains('chatSpeechAttemptTracker.isCurrent(generation)'));
  });

  test('pending speech can stop and activity always releases recognizer', () {
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('if (recognizer == null)'));
    expect(activity, contains('chatSpeechStopTimeout'));
    expect(activity, contains('releaseChatSpeechRecognizer()'));
    expect(activity, contains('override fun onDestroy()'));
    expect(
      activity,
      contains('mainHandler.removeCallbacks(beginChatSpeechRecognition)'),
    );
  });

  test('TTS cannot compete with dictation or leave wake mode blocked', () {
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();
    final automation =
        File('lib/services/automation_service.dart').readAsStringSync();
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();

    expect(activity, contains('pauseIronVoiceCapture'));
    expect(activity, contains('resumeIronVoiceCapture'));
    expect(automation, contains('Future<bool> pauseIronVoiceCapture()'));
    expect(chat, contains('_playSpeechWithWakePaused'));
    expect(chat, contains('await _automation.resumeIronVoiceCapture()'));
    expect(service, contains('finishSpeechWatchdog'));
    expect(service, contains('activeUtteranceId'));
    expect(service, contains('consumeExpectedRecognitionCancellation()'));
    expect(service, contains('requestGeneration != aiRequestGeneration'));
  });

  test('enabled Hey Iron mode is restored after reopening the app', () {
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();

    expect(activity, contains('override fun onPostResume()'));
    expect(activity, contains('restoreIronVoiceIfEnabled()'));
    expect(activity, contains('IronVoiceService.KEY_VOICE_ENABLED'));
    expect(service, contains('ACTION_STOP'));
    expect(service, contains('.putBoolean(KEY_VOICE_ENABLED, false)'));
  });

  test('wake command recognition is one-shot on Android errors', () {
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();

    expect(service, isNot(contains('commandRecognitionRetryCount')));
    expect(service, isNot(contains('Iron опитва микрофона отново')));
    expect(service, contains('voiceState = VoiceState.WAITING_FOR_WAKE'));
    expect(service, contains('scheduleWakeWordListening('));
  });
}
