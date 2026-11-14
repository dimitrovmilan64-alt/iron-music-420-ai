import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import 'ai_provider_config.dart';
import 'lyric_craft.dart';

class GeminiException implements Exception {
  final String message;

  const GeminiException(this.message);

  @override
  String toString() => message;
}

class _AiMessage {
  final String role;
  final String text;

  const _AiMessage(this.role, this.text);
}

class GeminiService {
  static const _geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  static const _preferredModels = <String>[
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-3.5-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash',
    'gemini-flash-latest',
  ];

  static const lyricPreferredModels = <String>[
    'gemini-3.1-pro-preview',
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-3.5-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash',
    'gemini-flash-latest',
  ];

  static const lyricBackupModels = <String>[
    'llama-3.3-70b-versatile',
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
  ];

  final http.Client _client;
  String? _activeModel;
  String? _activeGeminiModel;
  String? _modelForKeyFingerprint;

  GeminiService({http.Client? client}) : _client = client ?? http.Client();

  String? get activeModel => _activeModel;

  void dispose() {
    _client.close();
  }

  void resetModel() {
    _activeModel = null;
    _activeGeminiModel = null;
    _modelForKeyFingerprint = null;
  }

  Future<String> generateChat({
    required String apiKey,
    required List<ChatMessage> history,
  }) async {
    const systemPrompt = '''
Ти си Iron Music 420 AI — личен разговорен AI асистент.
Говориш само на естествен български и се обръщаш към потребителя в мъжки род, когато е уместно.
Разговаряш нормално, като интелигентен партньор: разбираш контекста, помниш предишните реплики и приемаш кратки продължения като „не, другото“, „промени втория куплет“ или „обясни го по-просто“.
Помагаш с общи въпроси, идеи, технически и ежедневни проблеми, както и професионално с рап текстове, рими, припеви, музикален анализ, Suno и Riffusion промптове.
Отговаряш ясно и директно, но не режеш полезната информация само за да бъдеш кратък.
Когато работиш по песен, мислиш като професионален рап продуцент.
Когато потребителят иска готов текст, дай завършен текст без излишно обяснение.
Не твърди, че си изпълнил действие на телефона, освен когато приложението реално потвърди такова действие.
''';

    final contextMessages = history
        .where((message) => !message.isLocalNotice)
        .toList(growable: false);
    final limitedHistory = contextMessages.length > 24
        ? contextMessages.sublist(contextMessages.length - 24)
        : contextMessages;

    final messages = limitedHistory
        .map(
          (message) => _AiMessage(
            message.isUser ? 'user' : 'assistant',
            message.text,
          ),
        )
        .toList(growable: false);

    return _generateWithFallback(
      geminiApiKey: apiKey,
      systemPrompt: systemPrompt,
      messages: messages,
      maxOutputTokens: 3600,
      temperature: 0.82,
    );
  }

  Future<String> generateRap({
    required String apiKey,
    required String instruction,
    LyricLanguage? language,
    bool twoPass = true,
  }) async {
    final resolvedLanguage =
        language ?? LyricCraft.detectLanguage(material: instruction);
    final systemPrompt = LyricCraft.buildSystemPrompt(resolvedLanguage);

    final draft = await _generateWithFallback(
      geminiApiKey: apiKey,
      systemPrompt: systemPrompt,
      messages: [_AiMessage('user', instruction)],
      maxOutputTokens: 7000,
      temperature: 0.95,
      preferredModels: lyricPreferredModels,
      forceSampling: true,
      frequencyPenalty: 0.7,
      presencePenalty: 0.6,
    );
    if (!twoPass || draft.trim().isEmpty) return draft;

    var current = draft;
    var report = LyricCraft.analyzeLyricsRhymeQuality(current);
    const temperatures = <double>[0.7, 0.55];
    for (var pass = 0; pass < temperatures.length; pass++) {
      if (pass > 0 && !report.needsRewrite) break;
      final revisionInstruction = LyricCraft.buildRevisionInstruction(
        draft: current,
        language: resolvedLanguage,
        report: report,
        originalInstruction: instruction,
      );
      final revised = await _generateWithFallback(
        geminiApiKey: apiKey,
        systemPrompt: systemPrompt,
        messages: [_AiMessage('user', revisionInstruction)],
        maxOutputTokens: 7000,
        temperature: temperatures[pass],
        preferredModels: lyricPreferredModels,
        forceSampling: true,
        frequencyPenalty: 0.55,
        presencePenalty: 0.45,
      );
      if (revised.trim().isEmpty) break;
      final nextReport = LyricCraft.analyzeLyricsRhymeQuality(revised);
      final improved = nextReport.weakPairs.length < report.weakPairs.length ||
          (nextReport.weakPairs.length == report.weakPairs.length &&
              nextReport.clicheEndWords.length <= report.clicheEndWords.length);
      if (improved || pass == 0) {
        current = revised;
        report = nextReport;
      } else {
        break;
      }
    }
    return current;
  }

  Future<String> _generateWithFallback({
    required String geminiApiKey,
    required String systemPrompt,
    required List<_AiMessage> messages,
    required int maxOutputTokens,
    required double temperature,
    List<String>? preferredModels,
    bool forceSampling = false,
    double frequencyPenalty = 0,
    double presencePenalty = 0,
  }) async {
    final cleanGeminiKey = geminiApiKey.trim();
    final backup = AiProviderConfig.current;
    GeminiException? geminiError;
    GeminiException? backupError;

    if (cleanGeminiKey.isNotEmpty) {
      try {
        return await _generateGemini(
          apiKey: cleanGeminiKey,
          systemPrompt: systemPrompt,
          messages: messages,
          maxOutputTokens: maxOutputTokens,
          temperature: temperature,
          preferredModels: preferredModels,
          forceSampling: forceSampling,
        );
      } on GeminiException catch (error) {
        geminiError = error;
      }
    }

    if (backup.hasBackup) {
      try {
        return await _generateBackup(
          config: backup,
          systemPrompt: systemPrompt,
          messages: messages,
          maxOutputTokens: maxOutputTokens,
          temperature: temperature,
          preferredModels: preferredModels,
          frequencyPenalty: frequencyPenalty,
          presencePenalty: presencePenalty,
        );
      } on GeminiException catch (error) {
        backupError = error;
      }
    }

    if (cleanGeminiKey.isEmpty && !backup.hasBackup) {
      throw const GeminiException(
        'Добави Gemini или резервен AI API ключ от настройките.',
      );
    }

    if (geminiError != null && backupError != null) {
      throw GeminiException(
        '${geminiError.message}\nРезервният доставчик също не отговори: '
        '${backupError.message}',
      );
    }

    throw backupError ??
        geminiError ??
        const GeminiException('AI доставчиците временно не отговарят.');
  }

  Future<String> _generateGemini({
    required String apiKey,
    required String systemPrompt,
    required List<_AiMessage> messages,
    required int maxOutputTokens,
    required double temperature,
    List<String>? preferredModels,
    bool forceSampling = false,
  }) async {
    final preferred = preferredModels ?? _preferredModels;
    final resolvedModel = await _resolveGeminiModel(
      apiKey,
      preferredModels: preferred,
    );
    final modelsToTry = <String>[
      ...preferred,
      resolvedModel,
      ..._preferredModels,
    ].toSet().toList(growable: false);

    GeminiException? lastError;

    for (final model in modelsToTry) {
      final uri = Uri.parse(
        '$_geminiBaseUrl/models/$model:generateContent',
      );
      final generationConfig = <String, dynamic>{
        'maxOutputTokens': maxOutputTokens,
      };

      if (forceSampling ||
          (!model.startsWith('gemini-3.5') &&
              !model.startsWith('gemini-3.6'))) {
        generationConfig['temperature'] = temperature;
        generationConfig['topP'] = 0.95;
      }

      for (var attempt = 0; attempt < 2; attempt++) {
        http.Response response;

        try {
          response = await _client
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'x-goog-api-key': apiKey,
                },
                body: jsonEncode({
                  'systemInstruction': {
                    'parts': [
                      {'text': systemPrompt},
                    ],
                  },
                  'contents': messages
                      .map(
                        (message) => {
                          'role':
                              message.role == 'assistant' ? 'model' : 'user',
                          'parts': [
                            {'text': message.text},
                          ],
                        },
                      )
                      .toList(growable: false),
                  'generationConfig': generationConfig,
                }),
              )
              .timeout(const Duration(seconds: 70));
        } catch (_) {
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(seconds: 1));
            continue;
          }
          throw const GeminiException(
            'Няма връзка с Gemini. Преминавам към резервния доставчик.',
          );
        }

        if (response.statusCode == 200) {
          final text = _extractGeminiText(response.body);
          if (text.isEmpty) {
            throw const GeminiException('Gemini върна празен отговор.');
          }
          _activeGeminiModel = model;
          _activeModel = 'Gemini · $model';
          _modelForKeyFingerprint = _fingerprint(apiKey);
          return text;
        }

        final message = _extractError(response.body);

        if (response.statusCode == 404) {
          lastError = const GeminiException(
            'Избраният Gemini модел не е наличен.',
          );
          break;
        }

        if (response.statusCode == 429) {
          throw const GeminiException(
            'Лимитът на Gemini е достигнат. Преминавам към резервния доставчик.',
          );
        }

        if (response.statusCode == 401 || response.statusCode == 403) {
          throw const GeminiException(
            'Gemini API ключът не е валиден или няма разрешение.',
          );
        }

        final transient = response.statusCode == 408 ||
            response.statusCode == 500 ||
            response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504;
        if (transient && attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        if (transient) {
          throw const GeminiException(
            'Gemini временно не отговаря. Преминавам към резервния доставчик.',
          );
        }

        throw GeminiException(
          _friendlyGeminiError(response.statusCode, message),
        );
      }
    }

    throw lastError ??
        const GeminiException('Не е намерен работещ Gemini модел.');
  }

  Future<String> _generateBackup({
    required AiProviderConfig config,
    required String systemPrompt,
    required List<_AiMessage> messages,
    required int maxOutputTokens,
    required double temperature,
    List<String>? preferredModels,
    double frequencyPenalty = 0,
    double presencePenalty = 0,
  }) async {
    final uri = config.chatCompletionsUri;
    if (uri == null) {
      throw const GeminiException(
        'Адресът на резервния AI доставчик не е валиден.',
      );
    }

    final configured = config.backupModel.trim();
    if (configured.isEmpty) {
      throw const GeminiException('Липсва модел за резервния AI доставчик.');
    }

    final isGroq = config.backupBaseUrl.toLowerCase().contains('groq.com');
    final modelsToTry = <String>[
      configured,
      if (isGroq && preferredModels != null) ...lyricBackupModels,
    ].toSet().toList(growable: false);

    GeminiException? lastError;
    for (final model in modelsToTry) {
      final payload = <String, dynamic>{
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ...messages.map(
            (message) => {
              'role': message.role,
              'content': message.text,
            },
          ),
        ],
      };

      final lowerModel = model.toLowerCase();
      final reasoningModel = lowerModel.startsWith('gpt-5') ||
          lowerModel.startsWith('o1') ||
          lowerModel.startsWith('o3') ||
          lowerModel.startsWith('o4');
      if (reasoningModel) {
        payload['max_completion_tokens'] = maxOutputTokens;
      } else {
        payload['max_tokens'] = maxOutputTokens;
        payload['temperature'] = temperature;
        if (frequencyPenalty != 0) {
          payload['frequency_penalty'] = frequencyPenalty;
        }
        if (presencePenalty != 0) {
          payload['presence_penalty'] = presencePenalty;
        }
      }

      var modelMissing = false;
      for (var attempt = 0; attempt < 2; attempt++) {
        http.Response response;
        try {
          response = await _client
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer ${config.backupApiKey.trim()}',
                },
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 70));
        } catch (_) {
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(seconds: 1));
            continue;
          }
          lastError = const GeminiException(
            'Няма връзка с резервния AI доставчик.',
          );
          break;
        }

        if (response.statusCode == 200) {
          final text = _extractBackupText(response.body);
          if (text.isEmpty) {
            lastError = const GeminiException(
              'Резервният AI доставчик върна празен отговор.',
            );
            break;
          }
          _activeModel = 'Резервен · $model';
          return text;
        }

        final transient = response.statusCode == 408 ||
            response.statusCode == 500 ||
            response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504;
        if (transient && attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }

        final raw = _extractError(response.body);
        switch (response.statusCode) {
          case 401:
          case 403:
            throw const GeminiException(
              'Резервният API ключ не е валиден или няма разрешение.',
            );
          case 404:
            lastError = GeminiException(
              'Резервният модел „$model“ не е наличен.',
            );
            modelMissing = true;
            break;
          case 429:
            throw const GeminiException(
              'Лимитът на резервния AI доставчик също е достигнат.',
            );
          case 500:
          case 502:
          case 503:
          case 504:
            lastError = const GeminiException(
              'Резервният AI доставчик временно не отговаря.',
            );
            break;
          default:
            lastError = GeminiException(
              'Резервният AI върна грешка ${response.statusCode}: $raw',
            );
            break;
        }
        if (modelMissing) break;
      }
    }

    throw lastError ??
        const GeminiException(
          'Резервният AI доставчик временно не отговаря.',
        );
  }

  Future<String> _resolveGeminiModel(
    String apiKey, {
    List<String>? preferredModels,
  }) async {
    final fingerprint = _fingerprint(apiKey);
    if (_activeGeminiModel != null && _modelForKeyFingerprint == fingerprint) {
      return _activeGeminiModel!;
    }

    try {
      final uri = Uri.parse('$_geminiBaseUrl/models?pageSize=1000');
      final response = await _client.get(
        uri,
        headers: {'x-goog-api-key': apiKey},
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

      final preferredList = preferredModels ?? _preferredModels;
      for (final preferred in preferredList) {
        if (available.contains(preferred)) {
          _activeGeminiModel = preferred;
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
        _activeGeminiModel = stableFlash.first;
        _modelForKeyFingerprint = fingerprint;
        return stableFlash.first;
      }
    } catch (_) {
      // При проблем с models.list използваме стабилен резервен модел.
    }

    return 'gemini-2.5-flash';
  }

  String _extractGeminiText(String body) {
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

  String _extractBackupText(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return '';
      final first = choices.first;
      if (first is! Map) return '';
      final message = first['message'];
      if (message is! Map) return '';
      final content = message['content'];
      if (content is String) return content.trim();
      if (content is List) {
        return content
            .whereType<Map>()
            .map((part) => part['text']?.toString() ?? '')
            .where((text) => text.trim().isNotEmpty)
            .join('\n')
            .trim();
      }
    } catch (_) {
      return '';
    }
    return '';
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
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length > 400 ? compact.substring(0, 400) : compact;
  }

  String _friendlyGeminiError(int statusCode, String rawMessage) {
    final compact = rawMessage.replaceAll(RegExp(r'\s+'), ' ').trim();
    switch (statusCode) {
      case 400:
        return 'Gemini отхвърли заявката. Провери ключа или съкрати текста. $compact';
      case 401:
      case 403:
        return 'Gemini API ключът не е валиден или няма разрешение.';
      default:
        return 'Gemini грешка $statusCode: $compact';
    }
  }

  String _fingerprint(String value) {
    if (value.length < 8) return value;
    return '${value.substring(0, 4)}:${value.substring(value.length - 4)}';
  }
}
