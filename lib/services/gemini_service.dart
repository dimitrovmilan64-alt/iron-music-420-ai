import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';

class GeminiException implements Exception {
  final String message;

  const GeminiException(this.message);

  @override
  String toString() => message;
}

class GeminiService {
  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';

  static const _preferredModels = <String>[
    'gemini-3.6-flash',
    'gemini-3.5-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash',
    'gemini-flash-latest',
  ];

  final http.Client _client;
  String? _activeModel;
  String? _modelForKeyFingerprint;

  GeminiService({http.Client? client}) : _client = client ?? http.Client();

  String? get activeModel => _activeModel;

  void dispose() {
    _client.close();
  }

  void resetModel() {
    _activeModel = null;
    _modelForKeyFingerprint = null;
  }

  Future<String> generateChat({
    required String apiKey,
    required List<ChatMessage> history,
  }) async {
    const systemPrompt = '''
Ти си Iron Music 420 AI, личен музикален асистент.
Говориш само на български.
Помагаш основно с рап текстове, рими, припеви, идеи за песни, анализ на музика, Suno и Riffusion промптове, технически и ежедневни проблеми.
Отговаряш кратко, ясно и практично.
Когато работиш по песен, мислиш като професионален рап продуцент.
Когато потребителят иска готов текст, дай завършен текст, без излишно обяснение.
Не твърди, че можеш да управляваш телефона директно, освен чрез реално настроени Android автоматизации.
''';

    final contextMessages = history
        .where((message) => !message.isLocalNotice)
        .toList(growable: false);
    final limitedHistory = contextMessages.length > 24
        ? contextMessages.sublist(contextMessages.length - 24)
        : contextMessages;

    final List<Map<String, dynamic>> contents = limitedHistory
        .map<Map<String, dynamic>>(
          (message) => {
            'role': message.isUser ? 'user' : 'model',
            'parts': [
              {'text': message.text},
            ],
          },
        )
        .toList(growable: false);

    return _generate(
      apiKey: apiKey,
      systemPrompt: systemPrompt,
      contents: contents,
      maxOutputTokens: 3600,
      temperature: 0.82,
    );
  }

  Future<String> generateRap({
    required String apiKey,
    required String instruction,
  }) {
    const systemPrompt = '''
Ти си професионален български рап автор и музикален продуцент.
Пишеш оригинални текстове, без да копираш конкретни изпълнители или песни.
Спазваш зададената тема, настроение, структура и римна схема.
Използваш естествен български език, силен ритъм и ясни вътрешни рими.
Връщаш само готовия резултат, структуриран с означения като [Куплет], [Припев], [Бридж], когато са нужни.
Никога не прекъсвай текста по средата на ред или изречение. При цяла песен завърши всички поискани части; ако е нужно, направи куплетите по-кратки, но дай завършен финал.
''';

    return _generate(
      apiKey: apiKey,
      systemPrompt: systemPrompt,
      contents: [
        {
          'role': 'user',
          'parts': [
            {'text': instruction},
          ],
        },
      ],
      maxOutputTokens: 7000,
      temperature: 0.92,
    );
  }

  Future<String> _generate({
    required String apiKey,
    required String systemPrompt,
    required List<Map<String, dynamic>> contents,
    required int maxOutputTokens,
    required double temperature,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const GeminiException('Липсва Gemini API ключ.');
    }

    final resolvedModel = await _resolveModel(apiKey);
    final modelsToTry = <String>[
      resolvedModel,
      ..._preferredModels,
    ].toSet().toList(growable: false);

    GeminiException? lastError;

    for (final model in modelsToTry) {
      final uri = Uri.parse('$_baseUrl/models/$model:generateContent');
      final generationConfig = <String, dynamic>{
        'maxOutputTokens': maxOutputTokens,
      };

      // Gemini 3.5/3.6 no longer need the older sampling fields.
      if (!model.startsWith('gemini-3.5') &&
          !model.startsWith('gemini-3.6')) {
        generationConfig['temperature'] = temperature;
        generationConfig['topP'] = 0.95;
      }

      for (var attempt = 0; attempt < 3; attempt++) {
        http.Response response;

        try {
          response = await _client
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'x-goog-api-key': apiKey.trim(),
                },
                body: jsonEncode({
                  'systemInstruction': {
                    'parts': [
                      {'text': systemPrompt},
                    ],
                  },
                  'contents': contents,
                  'generationConfig': generationConfig,
                }),
              )
              .timeout(const Duration(seconds: 70));
        } catch (_) {
          if (attempt < 2) {
            await Future<void>.delayed(Duration(seconds: 1 << attempt));
            continue;
          }
          lastError = const GeminiException(
            'Няма връзка с Gemini. Провери интернет връзката и опитай пак.',
          );
          break;
        }

        if (response.statusCode == 200) {
          final text = _extractText(response.body);
          if (text.isEmpty) {
            lastError = const GeminiException(
              'Gemini върна празен отговор. Опитай с по-кратка заявка.',
            );
            break;
          }
          _activeModel = model;
          _modelForKeyFingerprint = _fingerprint(apiKey);
          return text;
        }

        final message = _extractError(response.body);
        lastError = GeminiException(
          _friendlyError(response.statusCode, message),
        );

        final transient = response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode == 500 ||
            response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504;

        if (transient && attempt < 2) {
          final retryAfter = int.tryParse(
            response.headers['retry-after'] ?? '',
          );
          final delaySeconds = retryAfter ?? (1 << attempt);
          await Future<void>.delayed(
            Duration(seconds: delaySeconds.clamp(1, 8).toInt()),
          );
          continue;
        }

        // При липсващ/натоварен/лимитиран модел пробваме следващ Flash модел.
        if (response.statusCode == 404 || transient) {
          break;
        }

        throw lastError;
      }
    }

    throw lastError ??
        const GeminiException('Не е намерен работещ Gemini модел.');
  }

  Future<String> _resolveModel(String apiKey) async {
    final fingerprint = _fingerprint(apiKey);
    if (_activeModel != null && _modelForKeyFingerprint == fingerprint) {
      return _activeModel!;
    }

    try {
      final uri = Uri.parse('$_baseUrl/models?pageSize=1000');
      final response = await _client.get(
        uri,
        headers: {'x-goog-api-key': apiKey.trim()},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        return 'gemini-2.5-flash';
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final models = decoded['models'] as List<dynamic>? ?? const [];
      final available = <String>[];

      for (final item in models.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        final methods = (map['supportedGenerationMethods'] as List<dynamic>?)
                ?.map((method) => method.toString())
                .toList() ??
            const <String>[];
        if (!methods.contains('generateContent')) continue;

        final rawName = map['name']?.toString() ?? '';
        final name = rawName.startsWith('models/')
            ? rawName.substring('models/'.length)
            : rawName;
        if (name.isNotEmpty) available.add(name);
      }

      for (final preferred in _preferredModels) {
        if (available.contains(preferred)) {
          _activeModel = preferred;
          _modelForKeyFingerprint = fingerprint;
          return preferred;
        }
      }

      final stableFlash = available.where((name) {
        final lower = name.toLowerCase();
        return lower.contains('gemini') &&
            lower.contains('flash') &&
            !lower.contains('live') &&
            !lower.contains('tts') &&
            !lower.contains('image') &&
            !lower.contains('embedding') &&
            !lower.contains('preview') &&
            !lower.contains('experimental') &&
            !lower.contains('-exp');
      }).toList()
        ..sort((a, b) => b.compareTo(a));

      if (stableFlash.isNotEmpty) {
        _activeModel = stableFlash.first;
        _modelForKeyFingerprint = fingerprint;
        return stableFlash.first;
      }
    } catch (_) {
      // При проблем с models.list използваме стабилен резервен модел.
    }

    return 'gemini-2.5-flash';
  }

  String _extractText(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return '';

      final first = candidates.first;
      if (first is! Map) return '';
      final content = first['content'];
      if (content is! Map) return '';
      final parts = content['parts'];
      if (parts is! List) return '';

      return parts
          .whereType<Map>()
          .map((part) => part['text']?.toString() ?? '')
          .where((text) => text.trim().isNotEmpty)
          .join('\n')
          .trim();
    } catch (_) {
      return '';
    }
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'];
      if (error is Map) {
        return error['message']?.toString() ?? body;
      }
    } catch (_) {
      // Връщаме суровия текст само ако JSON не може да се прочете.
    }
    return body;
  }

  String _friendlyError(int statusCode, String rawMessage) {
    final compact = rawMessage.replaceAll(RegExp(r'\s+'), ' ').trim();
    switch (statusCode) {
      case 400:
        return 'Gemini отхвърли заявката. Провери API ключа или съкрати текста. $compact';
      case 401:
      case 403:
        return 'API ключът не е валиден или няма разрешение за Gemini API.';
      case 404:
        return 'Избраният Gemini модел не е наличен.';
      case 429:
        return 'Достигнат е лимитът на Gemini API. Изчакай малко и опитай пак.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'Gemini временно не отговаря. Опитай отново след малко.';
      default:
        return 'Gemini грешка $statusCode: $compact';
    }
  }

  String _fingerprint(String value) {
    if (value.length < 8) return value;
    return '${value.substring(0, 4)}:${value.substring(value.length - 4)}';
  }
}
