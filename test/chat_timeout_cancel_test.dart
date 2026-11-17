import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironmusic420ai/models/chat_message.dart';
import 'package:ironmusic420ai/services/ai_provider_config.dart';
import 'package:ironmusic420ai/services/gemini_service.dart';
import 'package:ironmusic420ai/services/voice_utterance.dart';

ChatMessage _user(String text) => ChatMessage(
      text: text,
      isUser: true,
      createdAt: DateTime(2026, 11, 18),
    );

void main() {
  setUp(() {
    AiProviderConfig.update(
      backupApiKey: '',
      backupBaseUrl: AiProviderConfig.defaultBackupBaseUrl,
      backupModel: AiProviderConfig.defaultBackupModel,
    );
  });

  test('chat has a hard 25 second overall timeout', () {
    expect(GeminiService.chatOverallTimeout, const Duration(seconds: 25));
    expect(GeminiException.timeoutMessage, VoiceUtterance.timeoutMessage);
  });

  test('generateChat surfaces a timeout instead of hanging past 25s', () {
    final client = MockClient((request) async {
      await Future<void>.delayed(const Duration(seconds: 60));
      return http.Response('{}', 500);
    });
    final service = GeminiService(client: client);
    addTearDown(service.dispose);

    fakeAsync((async) {
      Object? error;
      service.generateChat(
        apiKey: 'AIza-test',
        history: [_user('Чуваш ли ме?')],
      ).then<void>((_) {}, onError: (Object e) => error = e);
      async.elapse(const Duration(seconds: 24));
      async.flushMicrotasks();
      expect(error, isNull);
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(error, isA<GeminiException>());
      expect(
        (error! as GeminiException).message,
        GeminiException.timeoutMessage,
      );
    });
  });

  test('cancelActive stops an in-flight chat request', () {
    final started = Completer<void>();
    final client = MockClient((request) async {
      if (!started.isCompleted) started.complete();
      await Future<void>.delayed(const Duration(seconds: 20));
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Късно.'},
                ],
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = GeminiService(client: client);
    addTearDown(service.dispose);

    fakeAsync((async) {
      Object? error;
      String? reply;
      service.generateChat(
        apiKey: 'AIza-test',
        history: [_user('Разкажи ми нещо')],
      ).then<void>((value) => reply = value, onError: (Object e) => error = e);
      async.flushMicrotasks();
      service.cancelActive();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 20));
      async.flushMicrotasks();
      expect(reply, isNull);
      expect(error, isA<GeminiException>());
      expect((error! as GeminiException).cancelled, isTrue);
      expect(
        (error! as GeminiException).message,
        GeminiException.cancelledMessage,
      );
    });
  });
}
