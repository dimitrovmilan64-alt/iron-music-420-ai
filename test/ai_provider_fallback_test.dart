import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ironmusic420ai/models/chat_message.dart';
import 'package:ironmusic420ai/services/ai_provider_config.dart';
import 'package:ironmusic420ai/services/gemini_service.dart';

void main() {
  test('Gemini 429 switches automatically to the backup provider', () async {
    AiProviderConfig.update(
      backupApiKey: 'sk-test-backup',
      backupBaseUrl: 'https://api.openai.com/v1',
      backupModel: 'gpt-4.1-mini',
    );
    addTearDown(() {
      AiProviderConfig.update(
        backupApiKey: '',
        backupBaseUrl: AiProviderConfig.defaultBackupBaseUrl,
        backupModel: AiProviderConfig.defaultBackupModel,
      );
    });

    final client = MockClient((request) async {
      if (request.url.host == 'generativelanguage.googleapis.com') {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'models': [
                {
                  'name': 'models/gemini-2.5-flash',
                  'supportedGenerationMethods': ['generateContent'],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'error': {
              'code': 429,
              'status': 'RESOURCE_EXHAUSTED',
              'message': 'Quota exceeded',
            },
          }),
          429,
          headers: {'content-type': 'application/json'},
        );
      }

      expect(
        request.url.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(request.headers['Authorization'], 'Bearer sk-test-backup');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['model'], 'gpt-4.1-mini');

      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'Резервният AI работи.',
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

    final reply = await service.generateChat(
      apiKey: 'AIza-primary-test',
      history: [
        ChatMessage(
          text: 'Чуваш ли ме?',
          isUser: true,
          createdAt: DateTime(2026, 8, 1),
        ),
      ],
    );

    expect(reply, 'Резервният AI работи.');
    expect(service.activeModel, 'Резервен · gpt-4.1-mini');
  });

  test('missing both provider keys returns a clear setup message', () async {
    AiProviderConfig.update(
      backupApiKey: '',
      backupBaseUrl: AiProviderConfig.defaultBackupBaseUrl,
      backupModel: AiProviderConfig.defaultBackupModel,
    );

    final service = GeminiService(
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.generateChat(
        apiKey: '',
        history: [
          ChatMessage(
            text: 'Тест',
            isUser: true,
            createdAt: DateTime(2026, 8, 1),
          ),
        ],
      ),
      throwsA(
        isA<GeminiException>().having(
          (error) => error.message,
          'message',
          contains('Gemini или резервен AI API ключ'),
        ),
      ),
    );
  });
}
