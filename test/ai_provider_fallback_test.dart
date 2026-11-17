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
      expect(request.headers['authorization'], 'Bearer sk-test-backup');
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

  test('Gemini thought-only parts are not used as the visible reply', () async {
    AiProviderConfig.update(
      backupApiKey: '',
      backupBaseUrl: AiProviderConfig.defaultBackupBaseUrl,
      backupModel: AiProviderConfig.defaultBackupModel,
    );
    var calls = 0;
    final client = MockClient((request) async {
      if (request.url.path.contains('generateContent')) {
        calls += 1;
        if (calls == 1) {
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {'thought': true, 'text': 'тайно разсъждение'},
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'Видим отговор'},
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    final service = GeminiService(client: client);
    addTearDown(service.dispose);
    final reply = await service.generateChat(
      apiKey: 'AIza-test',
      history: [
        ChatMessage(
            text: 'Здравей', isUser: true, createdAt: DateTime(2026, 1, 1)),
      ],
    );
    expect(reply, 'Видим отговор');
    expect(reply, isNot(contains('тайно')));
  });

  test('Gemini MAX_TOKENS with empty visible text retries then succeeds',
      () async {
    AiProviderConfig.update(
      backupApiKey: '',
      backupBaseUrl: AiProviderConfig.defaultBackupBaseUrl,
      backupModel: AiProviderConfig.defaultBackupModel,
    );
    var calls = 0;
    final client = MockClient((request) async {
      if (!request.url.path.contains('generateContent')) {
        return http.Response('{}', 404);
      }
      calls += 1;
      if (calls == 1) {
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'MAX_TOKENS',
                'content': {
                  'parts': [
                    {'thought': true, 'text': 'think ' * 20},
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'finishReason': 'STOP',
              'content': {
                'parts': [
                  {'text': 'Готов текст'},
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
    final reply = await service.generateChat(
      apiKey: 'AIza-test',
      history: [
        ChatMessage(
            text: 'Текст', isUser: true, createdAt: DateTime(2026, 1, 1)),
      ],
    );
    expect(reply, 'Готов текст');
    expect(calls, greaterThanOrEqualTo(2));
  });

  test('Groq empty content with reasoning retries and then returns text',
      () async {
    AiProviderConfig.update(
      backupApiKey: 'gsk-test',
      backupBaseUrl: 'https://api.groq.com/openai/v1',
      backupModel: 'openai/gpt-oss-20b',
    );
    addTearDown(() {
      AiProviderConfig.update(
        backupApiKey: '',
        backupBaseUrl: AiProviderConfig.defaultBackupBaseUrl,
        backupModel: AiProviderConfig.defaultBackupModel,
      );
    });
    var calls = 0;
    final client = MockClient((request) async {
      if (request.url.host.contains('googleapis')) {
        return http.Response(
          jsonEncode({
            'error': {'code': 429, 'message': 'Quota exceeded'},
          }),
          429,
          headers: {'content-type': 'application/json'},
        );
      }
      expect(request.url.toString(), contains('api.groq.com'));
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload.containsKey('max_completion_tokens'), isTrue);
      expect(payload['reasoning_effort'], isNotNull);
      calls += 1;
      if (payload['model'] == 'openai/gpt-oss-20b' && calls == 1) {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '',
                  'reasoning': 'long private chain of thought',
                },
                'finish_reason': 'length',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'Припевът е готов.',
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
      apiKey: 'AIza-test',
      history: [
        ChatMessage(
            text: 'Направи припев',
            isUser: true,
            createdAt: DateTime(2026, 1, 1)),
      ],
    );
    expect(reply, 'Припевът е готов.');
    expect(reply, isNot(contains('private chain')));
  });

  test('404 model is skipped and a working model is used', () async {
    AiProviderConfig.update(
      backupApiKey: '',
      backupBaseUrl: AiProviderConfig.defaultBackupBaseUrl,
      backupModel: AiProviderConfig.defaultBackupModel,
    );
    final client = MockClient((request) async {
      if (!request.url.path.contains('generateContent')) {
        return http.Response('{}', 404);
      }
      if (request.url.path.contains('gemini-3.8-flash')) {
        return http.Response(
          jsonEncode({
            'error': {'code': 404, 'message': 'model not found'},
          }),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'finishReason': 'STOP',
              'content': {
                'parts': [
                  {'text': 'От следващия модел'},
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
    final reply = await service.generateChat(
      apiKey: 'AIza-test',
      history: [
        ChatMessage(
            text: 'Здравей', isUser: true, createdAt: DateTime(2026, 1, 1)),
      ],
    );
    expect(reply, 'От следващия модел');
    expect(service.activeModel, isNot(contains('gemini-3.8-flash')));
  });

  test('Gemini 429 message is in Bulgarian and backup is used', () async {
    AiProviderConfig.update(
      backupApiKey: 'gsk-test',
      backupBaseUrl: 'https://api.groq.com/openai/v1',
      backupModel: 'openai/gpt-oss-20b',
    );
    addTearDown(() {
      AiProviderConfig.update(
        backupApiKey: '',
        backupBaseUrl: AiProviderConfig.defaultBackupBaseUrl,
        backupModel: AiProviderConfig.defaultBackupModel,
      );
    });
    final client = MockClient((request) async {
      if (request.url.host.contains('googleapis')) {
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
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'Резервен отговор'},
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
      apiKey: 'AIza-test',
      history: [
        ChatMessage(
            text: 'Здравей', isUser: true, createdAt: DateTime(2026, 1, 1)),
      ],
    );
    expect(reply, 'Резервен отговор');
  });
}
