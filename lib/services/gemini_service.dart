import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import 'ai_provider_config.dart';
import 'lyric_craft.dart';

class GeminiException implements Exception {
  final String message;
  final int? statusCode;
  final bool cancelled;

  const GeminiException(
    this.message, {
    this.statusCode,
    this.cancelled = false,
  });

  static const timeoutMessage =
      'Няма отговор до 25 секунди. Провери връзката и опитай отново.';

  static const cancelledMessage = 'Отговорът е спрян.';

  const GeminiException.timeout()
      : message = timeoutMessage,
        statusCode = null,
        cancelled = false;

  const GeminiException.cancelled()
      : message = cancelledMessage,
        statusCode = null,
        cancelled = true;

  @override
  String toString() => message;
}

class LyricGenerationStats {
  final int draftMs;
  final int reviseMs;
  final int rewriteMs;
  final int totalMs;
  final String model;
  final int passes;

  const LyricGenerationStats({
    required this.draftMs,
    required this.reviseMs,
    required this.rewriteMs,
    required this.totalMs,
    required this.model,
    required this.passes,
  });
}

class ProviderTestResult {
  final bool ok;
  final String message;
  final int? statusCode;
  final String? model;

  const ProviderTestResult({
    required this.ok,
    required this.message,
    this.statusCode,
    this.model,
  });
}

class _AiMessage {
  final String role;
  final String text;

  const _AiMessage(this.role, this.text);
}

class _GeminiParse {
  final String text;
  final String finishReason;
  final bool hadThoughts;

  const _GeminiParse({
    required this.text,
    required this.finishReason,
    required this.hadThoughts,
  });
}

class GeminiService {
  static const _geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  static const _preferredModels = <String>[
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-4-hydrogen',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash',
    'gemini-flash-latest',
  ];

  /// Official Gemini text models with a documented free tier, fastest first.
  /// gemini-3.1-pro-preview is official but has no free tier, so it is omitted.
  static const lyricPreferredModels = <String>[
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-4-hydrogen',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash',
    'gemini-flash-latest',
  ];

  /// Official Groq production chat models available outside Enterprise.
  /// llama-3.3-70b-versatile was deprecated for free/developer tiers on 2026-08-16.
  static const lyricBackupModels = <String>[
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'qwen/qwen3.8-27b',
  ];

  static const Duration lyricCallTimeout = Duration(seconds: 18);
  static const Duration chatCallTimeout = Duration(seconds: 20);
  static const Duration chatOverallTimeout = Duration(seconds: 25);

  final Set<String> _unavailableModels = <String>{};
  LyricGenerationStats? lastLyricStats;

  final http.Client _client;
  String? _activeModel;
  String? _activeGeminiModel;
  String? _modelForKeyFingerprint;
  int _generation = 0;
  int? _activeGeneration;
  Completer<void>? _cancelGate;

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

  bool get hasActiveGeneration => _activeGeneration != null;

  int _beginGeneration() {
    final id = ++_generation;
    _activeGeneration = id;
    _cancelGate = Completer<void>();
    return id;
  }

  void cancelActive() {
    _activeGeneration = null;
    final gate = _cancelGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  void _finishGeneration(int id) {
    if (_activeGeneration == id) {
      _activeGeneration = null;
    }
  }

  void _throwIfCancelled([int? id]) {
    // Lyric and other calls may run without a cancellable session.
    if (_activeGeneration == null && id == null) return;
    if (_activeGeneration == null || (id != null && _activeGeneration != id)) {
      throw const GeminiException.cancelled();
    }
  }

  Future<T> _cancellable<T>(int id, Future<T> work) {
    if (_activeGeneration == null) return work;
    _throwIfCancelled(id);
    final gate = _cancelGate;
    if (gate == null) return work;
    final done = Completer<T>();
    work.then((value) {
      if (!done.isCompleted) done.complete(value);
    }, onError: (Object error, StackTrace stack) {
      if (!done.isCompleted) done.completeError(error, stack);
    });
    gate.future.then((_) {
      if (!done.isCompleted) {
        done.completeError(const GeminiException.cancelled());
      }
    });
    return done.future;
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

    final id = _beginGeneration();
    try {
      return await _generateWithFallback(
        geminiApiKey: apiKey,
        systemPrompt: systemPrompt,
        messages: messages,
        maxOutputTokens: 3600,
        temperature: 0.82,
        timeout: chatCallTimeout,
        skipModelDiscovery: true,
        thinkingLevel: 'low',
        preferredModels: _preferredModels,
      ).timeout(chatOverallTimeout);
    } on TimeoutException {
      cancelActive();
      throw const GeminiException.timeout();
    } finally {
      _finishGeneration(id);
    }
  }

  Future<String> generateRap({
    required String apiKey,
    required String instruction,
    LyricLanguage? language,
    bool twoPass = true,
    bool shortForm = false,
    void Function(String status)? onProgress,
  }) async {
    final resolvedLanguage =
        language ?? LyricCraft.detectLanguage(material: instruction);
    final systemPrompt = LyricCraft.buildSystemPrompt(resolvedLanguage);
    final total = Stopwatch()..start();
    var draftMs = 0;
    var reviseMs = 0;
    var rewriteMs = 0;
    var passes = 1;

    onProgress?.call('Пиша…');
    final draftWatch = Stopwatch()..start();
    final draft = await _generateWithFallback(
      geminiApiKey: apiKey,
      systemPrompt: systemPrompt,
      messages: [_AiMessage('user', instruction)],
      maxOutputTokens: shortForm ? 1800 : 7000,
      temperature: 0.95,
      preferredModels: lyricPreferredModels,
      forceSampling: true,
      frequencyPenalty: 0.7,
      presencePenalty: 0.6,
      timeout: lyricCallTimeout,
      skipModelDiscovery: true,
      thinkingLevel: 'low',
    );
    draftMs = draftWatch.elapsedMilliseconds;
    if (!twoPass || draft.trim().isEmpty) {
      lastLyricStats = LyricGenerationStats(
        draftMs: draftMs,
        reviseMs: 0,
        rewriteMs: 0,
        totalMs: total.elapsedMilliseconds,
        model: _activeModel ?? '',
        passes: passes,
      );
      return draft;
    }

    var current = draft;
    var report = LyricCraft.analyzeLyricsRhymeQuality(current);
    final revisePasses = shortForm ? 1 : 2;
    const temperatures = <double>[0.7, 0.55];
    for (var pass = 0; pass < revisePasses; pass++) {
      if (pass > 0 && !report.needsRewrite) break;
      onProgress?.call('Проверявам римите…');
      final reviseWatch = Stopwatch()..start();
      final revisionInstruction = pass == 0
          ? LyricCraft.buildRevisionInstruction(
              draft: current,
              language: resolvedLanguage,
              report: report,
              originalInstruction: instruction,
            )
          : LyricCraft.buildWeakLinesInstruction(
              draft: current,
              language: resolvedLanguage,
              report: report,
              originalInstruction: instruction,
            );
      final revised = await _generateWithFallback(
        geminiApiKey: apiKey,
        systemPrompt: systemPrompt,
        messages: [_AiMessage('user', revisionInstruction)],
        maxOutputTokens: shortForm ? 1800 : 7000,
        temperature: temperatures[pass],
        preferredModels: lyricPreferredModels,
        forceSampling: true,
        frequencyPenalty: 0.55,
        presencePenalty: 0.45,
        timeout: lyricCallTimeout,
        skipModelDiscovery: true,
        thinkingLevel: 'low',
      );
      final elapsed = reviseWatch.elapsedMilliseconds;
      if (pass == 0) {
        reviseMs = elapsed;
      } else {
        rewriteMs = elapsed;
      }
      passes += 1;
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

    lastLyricStats = LyricGenerationStats(
      draftMs: draftMs,
      reviseMs: reviseMs,
      rewriteMs: rewriteMs,
      totalMs: total.elapsedMilliseconds,
      model: _activeModel ?? '',
      passes: passes,
    );
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
    Duration timeout = chatCallTimeout,
    bool skipModelDiscovery = false,
    String? thinkingLevel,
  }) async {
    _throwIfCancelled();
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
          timeout: timeout,
          skipModelDiscovery: skipModelDiscovery,
          thinkingLevel: thinkingLevel,
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
          timeout: timeout,
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
    Duration timeout = chatCallTimeout,
    bool skipModelDiscovery = false,
    String? thinkingLevel,
  }) async {
    final preferred = preferredModels ?? _preferredModels;
    String? resolvedModel;
    if (!skipModelDiscovery) {
      resolvedModel = await _resolveGeminiModel(
        apiKey,
        preferredModels: preferred,
      );
    } else if (_activeGeminiModel != null &&
        _modelForKeyFingerprint == _fingerprint(apiKey) &&
        !_unavailableModels.contains(_activeGeminiModel)) {
      resolvedModel = _activeGeminiModel;
    }
    final modelsToTry = <String>[
      if (resolvedModel != null) resolvedModel,
      ...preferred,
      if (!skipModelDiscovery) ..._preferredModels,
    ]
        .where((model) => !_unavailableModels.contains(model))
        .toSet()
        .toList(growable: false);
    if (modelsToTry.isEmpty) {
      throw const GeminiException(
        'Няма наличен Gemini модел за този ключ. Провери ключа в Настройки и опитай отново.',
      );
    }

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
      var useThinking = thinkingLevel != null &&
          thinkingLevel.isNotEmpty &&
          _supportsThinkingLevel(model);
      if (useThinking) {
        generationConfig['thinkingConfig'] = {
          'thinkingLevel': thinkingLevel,
        };
      }

      for (var attempt = 0; attempt < 2; attempt++) {
        http.Response response;

        _throwIfCancelled();
        try {
          response = await _cancellable(
            _activeGeneration ?? _generation,
            _client
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
                .timeout(timeout),
          );
        } on TimeoutException {
          lastError = const GeminiException(
            'Gemini не отговори навреме. Пробвам друг модел.',
          );
          break;
        } on GeminiException catch (error) {
          if (error.cancelled) rethrow;
          lastError = error;
          break;
        } catch (_) {
          lastError = const GeminiException(
            'Няма връзка с Gemini. Преминавам към резервния доставчик.',
          );
          break;
        }

        if (response.statusCode == 200) {
          final parsed = _extractGeminiText(response.body);
          if (parsed.text.isEmpty) {
            final exhausted =
                parsed.finishReason.toUpperCase().contains('MAX') ||
                    parsed.hadThoughts;
            if (exhausted && attempt == 0) {
              generationConfig['maxOutputTokens'] =
                  maxOutputTokens < 4096 ? 4096 : maxOutputTokens * 2;
              continue;
            }
            lastError = const GeminiException(
              'Gemini върна празен отговор.',
            );
            break;
          }
          _activeGeminiModel = model;
          _activeModel = 'Gemini · $model';
          _modelForKeyFingerprint = _fingerprint(apiKey);
          return parsed.text;
        }

        final message = _extractError(response.body);
        final lower = message.toLowerCase();

        if (response.statusCode == 404 ||
            (response.statusCode == 400 && lower.contains('not found'))) {
          _unavailableModels.add(model);
          lastError = GeminiException(
            'Моделът „$model“ не съществува за този ключ.',
          );
          break;
        }

        if (response.statusCode == 400 &&
            useThinking &&
            (lower.contains('thinking') || lower.contains('thinkinglevel'))) {
          generationConfig.remove('thinkingConfig');
          useThinking = false;
          lastError = GeminiException(
            'Моделът „$model“ не приема thinkingLevel. Пробвам без него.',
          );
          continue;
        }

        if (response.statusCode == 429) {
          lastError = const GeminiException(
            'Лимитът на Gemini е изчерпан за този модел. Пробвам следващия.',
          );
          break;
        }

        if (response.statusCode == 401) {
          throw const GeminiException(
            'Gemini API ключът не е валиден.',
          );
        }

        if (response.statusCode == 403) {
          final modelBlocked = lower.contains('not found') ||
              lower.contains('not supported') ||
              lower.contains('not available');
          if (modelBlocked) {
            _unavailableModels.add(model);
            lastError = GeminiException(
              'Моделът „$model“ не е достъпен за този ключ.',
            );
            break;
          }
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
          lastError = const GeminiException(
            'Gemini временно не отговаря. Пробвам следващия модел.',
          );
          break;
        }

        lastError = GeminiException(
          _friendlyGeminiError(response.statusCode, message),
        );
        break;
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
    Duration timeout = chatCallTimeout,
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
      if (isGroq) ...lyricBackupModels,
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
      final gptOss = lowerModel.contains('gpt-oss');
      final qwen = lowerModel.contains('qwen');
      final legacyReasoning = lowerModel.startsWith('gpt-5') ||
          lowerModel.startsWith('o1') ||
          lowerModel.startsWith('o3') ||
          lowerModel.startsWith('o4');
      if (gptOss) {
        payload['max_completion_tokens'] =
            maxOutputTokens < 4096 ? 4096 : maxOutputTokens;
        payload['reasoning_effort'] = 'low';
        payload['reasoning_format'] = 'hidden';
        payload['temperature'] = temperature;
      } else if (qwen) {
        payload['max_completion_tokens'] = maxOutputTokens;
        payload['reasoning_effort'] = 'none';
        payload['temperature'] = temperature;
      } else if (legacyReasoning) {
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
        _throwIfCancelled();
        try {
          response = await _cancellable(
            _activeGeneration ?? _generation,
            _client
                .post(
                  uri,
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer ${config.backupApiKey.trim()}',
                  },
                  body: jsonEncode(payload),
                )
                .timeout(timeout),
          );
        } on TimeoutException {
          lastError = const GeminiException(
            'Резервният AI не отговори навреме. Пробвам друг модел.',
          );
          break;
        } on GeminiException catch (error) {
          if (error.cancelled) rethrow;
          lastError = error;
          break;
        } catch (_) {
          lastError = const GeminiException(
            'Няма връзка с резервния AI доставчик.',
          );
          break;
        }

        if (response.statusCode == 200) {
          final text = _extractBackupText(response.body);
          if (text.isEmpty) {
            if (attempt == 0 && (gptOss || qwen || legacyReasoning)) {
              payload['max_completion_tokens'] = 8192;
              payload['reasoning_effort'] = gptOss ? 'low' : 'none';
              payload['reasoning_format'] = 'hidden';
              continue;
            }
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
              'Резервният API ключ не е валиден.',
            );
          case 404:
            lastError = GeminiException(
              'Резервният модел „$model“ не съществува.',
            );
            modelMissing = true;
            break;
          case 429:
            lastError = const GeminiException(
              'Лимитът на резервния AI доставчик е изчерпан. Пробвам следващия модел.',
            );
            modelMissing = true;
            break;
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

  static bool _supportsThinkingLevel(String model) {
    final lower = model.toLowerCase();
    return lower.startsWith('gemini-3') || lower.startsWith('gemini-4');
  }

  _GeminiParse _extractGeminiText(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        return const _GeminiParse(
            text: '', finishReason: '', hadThoughts: false);
      }

      final first = candidates.first;
      if (first is! Map) {
        return const _GeminiParse(
            text: '', finishReason: '', hadThoughts: false);
      }
      final finishReason = first['finishReason']?.toString() ?? '';
      final content = first['content'];
      if (content is! Map) {
        return _GeminiParse(
            text: '', finishReason: finishReason, hadThoughts: false);
      }
      final parts = content['parts'];
      if (parts is! List) {
        return _GeminiParse(
            text: '', finishReason: finishReason, hadThoughts: false);
      }

      var hadThoughts = false;
      final visible = <String>[];
      for (final part in parts.whereType<Map>()) {
        final isThought = part['thought'] == true;
        final text = part['text']?.toString() ?? '';
        if (isThought) {
          hadThoughts = true;
          continue;
        }
        if (text.trim().isNotEmpty) visible.add(text);
      }
      return _GeminiParse(
        text: visible.join('\n').trim(),
        finishReason: finishReason,
        hadThoughts: hadThoughts,
      );
    } catch (_) {
      return const _GeminiParse(text: '', finishReason: '', hadThoughts: false);
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
      if (content is String && content.trim().isNotEmpty) {
        return content.trim();
      }
      if (content is List) {
        final joined = content
            .whereType<Map>()
            .map((part) => part['text']?.toString() ?? '')
            .where((text) => text.trim().isNotEmpty)
            .join('\n')
            .trim();
        if (joined.isNotEmpty) return joined;
      }
      // Never use the reasoning/thinking field as the visible lyric or reply.
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
        return 'Gemini отхвърли заявката. $compact';
      case 401:
      case 403:
        return 'Gemini API ключът не е валиден.';
      case 404:
        return 'Моделът не съществува за този ключ.';
      case 429:
        return 'Лимитът на Gemini е изчерпан.';
      default:
        return 'Gemini грешка $statusCode: $compact';
    }
  }

  Future<ProviderTestResult> testGeminiKey(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return const ProviderTestResult(
        ok: false,
        message: 'Липсва Gemini ключ.',
      );
    }
    final model = lyricPreferredModels.first;
    try {
      final uri = Uri.parse('$_geminiBaseUrl/models/$model:generateContent');
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': key,
            },
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': 'Отговори само с OK.'},
                  ],
                },
              ],
              'generationConfig': {
                'maxOutputTokens': 16,
                'thinkingConfig': {'thinkingLevel': 'low'},
              },
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final parsed = _extractGeminiText(response.body);
        if (parsed.text.isNotEmpty) {
          return ProviderTestResult(
            ok: true,
            message: 'Gemini ключът работи (модел $model).',
            statusCode: 200,
            model: model,
          );
        }
        return ProviderTestResult(
          ok: false,
          message: 'Gemini върна празен отговор (модел $model).',
          statusCode: 200,
          model: model,
        );
      }
      return ProviderTestResult(
        ok: false,
        message: _friendlyGeminiError(
          response.statusCode,
          _extractError(response.body),
        ),
        statusCode: response.statusCode,
        model: model,
      );
    } on TimeoutException {
      return ProviderTestResult(
        ok: false,
        message: 'Gemini не отговори навреме (модел $model).',
        model: model,
      );
    } catch (_) {
      return const ProviderTestResult(
        ok: false,
        message: 'Няма връзка с Gemini.',
      );
    }
  }

  Future<ProviderTestResult> testGroqKey(String apiKey, {String? model}) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return const ProviderTestResult(
        ok: false,
        message: 'Липсва Groq ключ.',
      );
    }
    final chosen = (model ?? 'openai/gpt-oss-20b').trim();
    try {
      final uri = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $key',
            },
            body: jsonEncode({
              'model': chosen,
              'messages': [
                {'role': 'user', 'content': 'Reply with OK only.'},
              ],
              'max_completion_tokens': 256,
              'reasoning_effort': 'low',
              'reasoning_format': 'hidden',
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final text = _extractBackupText(response.body);
        if (text.isNotEmpty) {
          return ProviderTestResult(
            ok: true,
            message: 'Groq ключът работи (модел $chosen).',
            statusCode: 200,
            model: chosen,
          );
        }
        return ProviderTestResult(
          ok: false,
          message:
              'Groq върна празен отговор (модел $chosen). Пробвай отново или смени модела.',
          statusCode: 200,
          model: chosen,
        );
      }
      final raw = _extractError(response.body);
      final message = switch (response.statusCode) {
        401 || 403 => 'Groq API ключът не е валиден.',
        404 => 'Моделът „$chosen“ не съществува.',
        429 => 'Лимитът на Groq е изчерпан.',
        _ => 'Groq грешка ${response.statusCode}: $raw',
      };
      return ProviderTestResult(
        ok: false,
        message: message,
        statusCode: response.statusCode,
        model: chosen,
      );
    } on TimeoutException {
      return ProviderTestResult(
        ok: false,
        message: 'Groq не отговори навреме (модел $chosen).',
        model: chosen,
      );
    } catch (_) {
      return const ProviderTestResult(
        ok: false,
        message: 'Няма връзка с Groq.',
      );
    }
  }

  String _fingerprint(String value) {
    if (value.length < 8) return value;
    return '${value.substring(0, 4)}:${value.substring(value.length - 4)}';
  }
}
