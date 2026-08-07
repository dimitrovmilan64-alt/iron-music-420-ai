import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ironmusic420ai/services/automation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('iron_music_420/automations');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('native recognition returns Bulgarian text to the chat', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'startChatSpeechRecognition');
      return 'Как си, Айрън?';
    });

    final service = AutomationService();
    final result = await service.startNativeSpeechRecognition();

    expect(result.success, isTrue);
    expect(result.text, 'Как си, Айрън?');
    expect(result.message, isEmpty);
  });

  test('native recognition exposes a clear Android error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'CHAT_SPEECH_AUDIO',
        message: 'Android не успя да отвори микрофона.',
      );
    });

    final service = AutomationService();
    final result = await service.startNativeSpeechRecognition();

    expect(result.success, isFalse);
    expect(result.message, contains('Android не успя'));
  });

  test('stop and cancel call the native recognizer controls', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });

    final service = AutomationService();
    await service.stopNativeSpeechRecognition();
    await service.cancelNativeSpeechRecognition();

    expect(
      calls,
      ['stopChatSpeechRecognition', 'cancelChatSpeechRecognition'],
    );
  });
}
