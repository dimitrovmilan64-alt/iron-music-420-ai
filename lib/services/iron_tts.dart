import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import 'local_store.dart';

enum IronTtsProvider { device, gemini, groq }

class IronVoiceOption {
  final String id;
  final String name;
  final String locale;
  final IronTtsProvider provider;
  final String trait;
  final bool supportsBulgarian;
  final int score;

  const IronVoiceOption({
    required this.id,
    required this.name,
    required this.locale,
    required this.provider,
    this.trait = '',
    required this.supportsBulgarian,
    this.score = 0,
  });

  String get badge {
    if (provider == IronTtsProvider.gemini) {
      return locale.toLowerCase().replaceAll('_', '-').startsWith('en')
          ? 'Gemini · EN'
          : 'Gemini · BG';
    }
    if (provider == IronTtsProvider.groq) return 'Groq · само EN';
    if (score >= 10) return 'Подобрен';
    return 'Системен';
  }

  String get title {
    if (trait.isEmpty) return name;
    return '$name · $trait';
  }

  IronVoiceOption copyWith({String? locale, String? trait}) {
    return IronVoiceOption(
      id: id,
      name: name,
      locale: locale ?? this.locale,
      provider: provider,
      trait: trait ?? this.trait,
      supportsBulgarian: supportsBulgarian,
      score: score,
    );
  }
}

class _CacheEntry {
  final Uint8List bytes;
  final DateTime storedAt;
  _CacheEntry(this.bytes) : storedAt = DateTime.now();
  bool get isFresh => DateTime.now().difference(storedAt) < IronTts.cacheTtl;
}

/// Device TTS via flutter_tts, plus official cloud TTS when the user has
/// already saved a Gemini or Groq key in secure storage.
class IronTts {
  IronTts._();
  static final IronTts instance = IronTts._();

  static const cacheTtl = Duration(minutes: 15);
  static const _maxCacheEntries = 10;
  static const groqMaxChars = 180;
  static const deviceMaxChars = 220;

  static const defaultGeminiVoice = 'Sulafat';

  static const geminiModels = <String>[
    'gemini-3.8-flash-tts',
    'gemini-3.8-flash-lite-tts',
    'gemini-2.5-flash-tts',
    'gemini-2.5-pro-tts',
  ];

  static const groqModel = 'canopylabs/orpheus-v1-english';
  static const groqEndpoint = 'https://api.groq.com/openai/v1/audio/speech';
  static const geminiBase = 'https://generativelanguage.googleapis.com/v1beta';

  /// Curated Gemini voices for Bulgarian (primary). Short list, labeled in Bulgarian.
  static const geminiPrebuiltVoices = <(String, String)>[
    ('Sulafat', 'топъл, женски'),
    ('Kore', 'твърд и ясен, женски'),
    ('Charon', 'спокоен разказвач, мъжки'),
    ('Aoede', 'лек и жив, женски'),
    ('Puck', 'енергичен, мъжки'),
    ('Enceladus', 'мек, дъхав, мъжки'),
  ];

  /// A couple of the same Gemini voices offered with an English locale.
  static const geminiEnglishVoices = <(String, String)>[
    ('Kore', 'ясен, женски'),
    ('Charon', 'спокоен, мъжки'),
  ];

  /// Official Groq Orpheus English voices. Groq TTS is English/Arabic only.
  static const groqEnglishVoices = <(String, String, String)>[
    ('autumn', 'Autumn', 'женски'),
    ('diana', 'Diana', 'женски'),
    ('austin', 'Austin', 'мъжки'),
    ('daniel', 'Daniel', 'мъжки'),
  ];

  final FlutterTts _device = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  final Map<String, _CacheEntry> _cache = {};
  http.Client? _client;
  String? _lastGeminiModel;

  http.Client get _http => _client ??= http.Client();

  static bool looksBulgarian(String text) {
    return RegExp(r'[\u0400-\u04FF]').hasMatch(text);
  }

  static bool looksEnglish(String text) {
    return RegExp(r'[A-Za-z]').hasMatch(text) && !looksBulgarian(text);
  }

  static bool isAllowedDeviceLocale(String locale) {
    final normalized = locale.toLowerCase().replaceAll('_', '-');
    return normalized.startsWith('bg') || normalized.startsWith('en');
  }

  static int deviceVoiceScore(Map<String, String> voice) {
    final name = (voice['name'] ?? '').toLowerCase();
    final locale = (voice['locale'] ?? '').toLowerCase().replaceAll('_', '-');
    var score = 0;
    if (locale.startsWith('bg')) score += 100;
    if (locale.startsWith('en')) score += 40;
    for (final word in const [
      'natural',
      'neural',
      'network',
      'online',
      'enhanced',
      'premium',
      'wavenet',
      'studio',
      'high',
    ]) {
      if (name.contains(word)) score += 12;
    }
    final quality = int.tryParse(voice['quality'] ?? '');
    if (quality != null) score += quality ~/ 50;
    if ((voice['network_required'] ?? voice['networkRequired'] ?? '')
        .toString()
        .toLowerCase()
        .contains('true')) {
      score += 8;
    }
    for (final word in const ['embedded', 'local', 'compact', 'lite']) {
      if (name.contains(word)) score -= 20;
    }
    return score;
  }

  static List<String> chunkForSpeech(String text,
      {int maxChars = deviceMaxChars}) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return const <String>[];
    if (cleaned.length <= maxChars) return <String>[cleaned];

    final sentences = <String>[];
    final pattern = RegExp(r'.+?(?:[\.!?…]+["»”’]?|\n+|$)');
    for (final match in pattern.allMatches(cleaned)) {
      final piece = match.group(0)!.trim();
      if (piece.isNotEmpty) sentences.add(piece);
    }
    if (sentences.isEmpty) sentences.add(cleaned);

    final chunks = <String>[];
    var buffer = StringBuffer();
    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) chunks.add(value);
      buffer = StringBuffer();
    }

    for (final sentence in sentences) {
      if (sentence.length > maxChars) {
        flush();
        for (final piece in _splitLong(sentence, maxChars)) {
          chunks.add(piece);
        }
        continue;
      }
      final current = buffer.toString();
      if (current.isNotEmpty &&
          current.length + sentence.length + 1 > maxChars) {
        flush();
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(sentence);
    }
    flush();
    return chunks;
  }

  static List<String> _splitLong(String text, int maxChars) {
    final words = text.split(' ');
    final out = <String>[];
    var buffer = StringBuffer();
    for (final word in words) {
      if (buffer.isNotEmpty && buffer.length + word.length + 1 > maxChars) {
        out.add(buffer.toString().trim());
        buffer = StringBuffer();
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(word);
    }
    final last = buffer.toString().trim();
    if (last.isNotEmpty) out.add(last);
    return out;
  }

  static IronVoiceOption? parseStored(String name, String locale) {
    if (name.startsWith('gemini:') || name.startsWith('gemini-en:')) {
      final voice = name.contains(':') ? name.split(':').last : name;
      final resolvedLocale = locale.trim().isEmpty
          ? (name.startsWith('gemini-en:') ? 'en-US' : 'bg-BG')
          : locale;
      return IronVoiceOption(
        id: name,
        name: voice,
        locale: resolvedLocale,
        provider: IronTtsProvider.gemini,
        supportsBulgarian: true,
        score: 80,
      );
    }
    if (name.startsWith('groq:')) {
      final voice = name.substring(5);
      return IronVoiceOption(
        id: name,
        name: voice,
        locale: 'en-US',
        provider: IronTtsProvider.groq,
        supportsBulgarian: false,
        score: 50,
      );
    }
    if (name.isEmpty) return null;
    return IronVoiceOption(
      id: 'device:$name|$locale',
      name: name,
      locale: locale.isEmpty ? 'bg-BG' : locale,
      provider: IronTtsProvider.device,
      supportsBulgarian: locale.toLowerCase().startsWith('bg'),
    );
  }

  static List<IronVoiceOption> cloudVoices({
    required bool hasGemini,
    required bool hasGroq,
  }) {
    final options = <IronVoiceOption>[];
    if (hasGemini) {
      options.addAll(
        geminiPrebuiltVoices.map(
          (voice) => IronVoiceOption(
            id: 'gemini:${voice.$1}',
            name: voice.$1,
            locale: 'bg-BG',
            provider: IronTtsProvider.gemini,
            trait: voice.$2,
            supportsBulgarian: true,
            score: 80,
          ),
        ),
      );
      options.addAll(
        geminiEnglishVoices.map(
          (voice) => IronVoiceOption(
            id: 'gemini-en:${voice.$1}',
            name: voice.$1,
            locale: 'en-US',
            provider: IronTtsProvider.gemini,
            trait: voice.$2,
            supportsBulgarian: true,
            score: 70,
          ),
        ),
      );
    }
    if (hasGroq) {
      options.addAll(
        groqEnglishVoices.map(
          (voice) => IronVoiceOption(
            id: 'groq:${voice.$1}',
            name: voice.$2,
            locale: 'en-US',
            provider: IronTtsProvider.groq,
            trait: '${voice.$3} · само английски',
            supportsBulgarian: false,
            score: 50,
          ),
        ),
      );
    }
    return options;
  }

  static IronVoiceOption? _firstGemini(
    List<IronVoiceOption> voices, {
    required String locale,
    bool hasGemini = false,
  }) {
    final match = voices.where(
      (voice) =>
          voice.provider == IronTtsProvider.gemini &&
          voice.locale.toLowerCase().replaceAll('_', '-').startsWith(
                locale.toLowerCase().startsWith('en') ? 'en' : 'bg',
              ),
    );
    if (match.isNotEmpty) return match.first.copyWith(locale: locale);
    final anyGemini =
        voices.where((voice) => voice.provider == IronTtsProvider.gemini);
    if (anyGemini.isNotEmpty) return anyGemini.first.copyWith(locale: locale);
    if (!hasGemini) return null;
    return IronVoiceOption(
      id: 'gemini:$defaultGeminiVoice',
      name: defaultGeminiVoice,
      locale: locale,
      provider: IronTtsProvider.gemini,
      trait: 'топъл, женски',
      supportsBulgarian: true,
      score: 80,
    );
  }

  static IronVoiceOption? _bestDeviceVoice(
    List<IronVoiceOption> voices, {
    required bool bulgarian,
  }) {
    final filtered = voices.where((voice) {
      if (voice.provider != IronTtsProvider.device) return false;
      if (bulgarian) return voice.supportsBulgarian;
      return voice.locale.toLowerCase().replaceAll('_', '-').startsWith('en');
    }).toList();
    if (filtered.isNotEmpty) return filtered.first;
    final anyDevice =
        voices.where((voice) => voice.provider == IronTtsProvider.device);
    return anyDevice.isEmpty ? null : anyDevice.first;
  }

  /// Picks the actual voice used at playback: Bulgarian by default,
  /// English only when the text is Latin/English.
  static IronVoiceOption resolvePlaybackVoice({
    required IronVoiceOption selected,
    required String text,
    required List<IronVoiceOption> voices,
    required bool hasGemini,
  }) {
    final bulgarian = looksBulgarian(text);
    final english = looksEnglish(text);

    if (bulgarian || !english) {
      if (selected.provider == IronTtsProvider.gemini) {
        return selected.copyWith(locale: 'bg-BG');
      }
      if (selected.provider == IronTtsProvider.groq) {
        return _firstGemini(voices, locale: 'bg-BG', hasGemini: hasGemini) ??
            _bestDeviceVoice(voices, bulgarian: true) ??
            const IronVoiceOption(
              id: 'device:system|bg-BG',
              name: '',
              locale: 'bg-BG',
              provider: IronTtsProvider.device,
              supportsBulgarian: true,
            );
      }
      return selected;
    }

    if (selected.provider == IronTtsProvider.groq) return selected;
    if (selected.provider == IronTtsProvider.gemini) {
      return selected.copyWith(locale: 'en-US');
    }
    return _bestDeviceVoice(voices, bulgarian: false) ?? selected;
  }

  static IronTtsProvider playbackProvider({
    required IronVoiceOption selected,
    required String text,
    List<IronVoiceOption> voices = const [],
    bool hasGemini = false,
  }) {
    return resolvePlaybackVoice(
      selected: selected,
      text: text,
      voices: voices,
      hasGemini: hasGemini,
    ).provider;
  }

  static String cacheKey({
    required String voiceId,
    required double rate,
    required double pitch,
    required String text,
  }) {
    return '$voiceId|$rate|$pitch|$text';
  }

  Future<List<IronVoiceOption>> listVoices(LocalStore store) async {
    final device = <IronVoiceOption>[];
    try {
      final raw = await _device.getVoices;
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final locale = item['locale']?.toString() ?? '';
          final name = item['name']?.toString() ?? '';
          if (name.isEmpty) continue;
          if (!isAllowedDeviceLocale(locale)) continue;
          final map = <String, String>{
            'name': name,
            'locale': locale,
            'quality': item['quality']?.toString() ?? '',
            'network_required':
                (item['network_required'] ?? item['networkRequired'] ?? '')
                    .toString(),
          };
          device.add(
            IronVoiceOption(
              id: 'device:$name|$locale',
              name: name,
              locale: locale,
              provider: IronTtsProvider.device,
              supportsBulgarian:
                  locale.toLowerCase().replaceAll('_', '-').startsWith('bg'),
              score: deviceVoiceScore(map),
            ),
          );
        }
      }
    } catch (_) {
      // System TTS list is optional; chat still works without it.
    }

    device.sort((a, b) => b.score.compareTo(a.score));
    final limited = <IronVoiceOption>[
      ...device.where((voice) => voice.supportsBulgarian).take(2),
      ...device
          .where((voice) =>
              !voice.supportsBulgarian &&
              voice.locale.toLowerCase().replaceAll('_', '-').startsWith('en'))
          .take(2),
    ];

    final options = <IronVoiceOption>[
      ...cloudVoices(
          hasGemini: store.hasApiKey, hasGroq: store.hasBackupProvider),
      ...limited,
    ];
    options.sort((a, b) {
      final group = _group(a).compareTo(_group(b));
      if (group != 0) return group;
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      return a.name.compareTo(b.name);
    });
    return options;
  }

  static int _group(IronVoiceOption voice) {
    if (voice.provider == IronTtsProvider.gemini &&
        voice.supportsBulgarian &&
        !voice.locale.toLowerCase().replaceAll('_', '-').startsWith('en')) {
      return 0;
    }
    if (voice.provider == IronTtsProvider.gemini) return 1;
    if (voice.provider == IronTtsProvider.groq) return 2;
    if (voice.provider == IronTtsProvider.device && voice.supportsBulgarian) {
      return 3;
    }
    if (voice.provider == IronTtsProvider.device &&
        voice.locale.toLowerCase().replaceAll('_', '-').startsWith('en')) {
      return 4;
    }
    return 5;
  }

  Future<IronVoiceOption> resolveSelection(
    LocalStore store,
    List<IronVoiceOption> voices,
  ) async {
    final saved = parseStored(store.ttsVoiceName, store.ttsVoiceLocale);
    if (saved != null) {
      final match = voices.where((voice) => voice.id == saved.id);
      if (match.isNotEmpty) return match.first;
      if (saved.provider != IronTtsProvider.device) return saved;
    }
    final best = preferredDefaultVoice(store, voices);
    if (store.ttsVoiceName.isEmpty) {
      await store.saveVoiceSettings(
        rate: store.ttsRate,
        pitch: store.ttsPitch,
        voiceName:
            best.provider == IronTtsProvider.device ? best.name : best.id,
        voiceLocale: best.locale,
      );
    }
    return best;
  }

  static IronVoiceOption preferredDefaultVoice(
    LocalStore store,
    List<IronVoiceOption> voices,
  ) {
    if (store.hasApiKey) {
      final sulafat = voices.where(
        (voice) =>
            voice.provider == IronTtsProvider.gemini &&
            voice.name == defaultGeminiVoice &&
            !voice.locale.toLowerCase().replaceAll('_', '-').startsWith('en'),
      );
      if (sulafat.isNotEmpty) return sulafat.first;
      final geminiBg = voices.where(
        (voice) =>
            voice.provider == IronTtsProvider.gemini &&
            !voice.locale.toLowerCase().replaceAll('_', '-').startsWith('en'),
      );
      if (geminiBg.isNotEmpty) return geminiBg.first;
      return const IronVoiceOption(
        id: 'gemini:$defaultGeminiVoice',
        name: defaultGeminiVoice,
        locale: 'bg-BG',
        provider: IronTtsProvider.gemini,
        trait: 'топъл, женски',
        supportsBulgarian: true,
        score: 80,
      );
    }
    final deviceBg = voices.where(
      (voice) =>
          voice.provider == IronTtsProvider.device && voice.supportsBulgarian,
    );
    if (deviceBg.isNotEmpty) return deviceBg.first;
    if (voices.isNotEmpty) return voices.first;
    return const IronVoiceOption(
      id: 'device:system|bg-BG',
      name: '',
      locale: 'bg-BG',
      provider: IronTtsProvider.device,
      supportsBulgarian: true,
    );
  }

  Future<void> applyDeviceSettings(
      LocalStore store, IronVoiceOption voice) async {
    final locale =
        voice.locale.isEmpty ? 'bg-BG' : voice.locale.replaceAll('_', '-');
    await _device.setLanguage(locale);
    await _device.setSpeechRate(store.ttsRate);
    await _device.setVolume(1.0);
    await _device.setPitch(store.ttsPitch);
    await _device.awaitSpeakCompletion(true);
    if (voice.provider == IronTtsProvider.device && voice.name.isNotEmpty) {
      await _device.setVoice({'name': voice.name, 'locale': voice.locale});
    }
  }

  Future<void> stop() async {
    try {
      await _device.stop();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Speaks [text]. Cloud failures and Groq+Bulgarian fall back to device TTS.
  Future<String?> speak(String text, LocalStore store) async {
    final voices = await listVoices(store);
    final selected = await resolveSelection(store, voices);
    return speakWith(text, store, selected);
  }

  Future<String?> speakWith(
    String text,
    LocalStore store,
    IronVoiceOption voice,
  ) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return null;

    final voices = await listVoices(store);
    var use = resolvePlaybackVoice(
      selected: voice,
      text: cleaned,
      voices: voices,
      hasGemini: store.hasApiKey,
    );
    String? notice;
    if (voice.provider == IronTtsProvider.groq &&
        use.provider != IronTtsProvider.groq) {
      notice = use.provider == IronTtsProvider.gemini
          ? 'Groq TTS е само за английски. За български се ползва Gemini.'
          : 'Groq TTS е само за английски. За български се ползва гласът от телефона.';
    }

    try {
      if (use.provider == IronTtsProvider.device) {
        await _speakDevice(cleaned, store, use);
        return notice;
      }
      await _speakCloud(cleaned, store, use);
      return notice;
    } catch (_) {
      try {
        final fallback =
            await _bestDevice(store, voices: await listVoices(store));
        await _speakDevice(cleaned, store, fallback);
        return notice ??
            'Облачният глас не беше достъпен, затова се ползва гласът от телефона.';
      } catch (_) {
        return 'Гласът не можа да се пусне.';
      }
    }
  }

  Future<void> _speakDevice(
    String text,
    LocalStore store,
    IronVoiceOption voice,
  ) async {
    await applyDeviceSettings(store, voice);
    for (final chunk in chunkForSpeech(text, maxChars: deviceMaxChars)) {
      await _device.stop();
      await _device.speak(chunk).timeout(const Duration(minutes: 3));
    }
  }

  Future<void> _speakCloud(
    String text,
    LocalStore store,
    IronVoiceOption voice,
  ) async {
    final maxChars =
        voice.provider == IronTtsProvider.groq ? groqMaxChars : 900;
    for (final chunk in chunkForSpeech(text, maxChars: maxChars)) {
      final bytes = await _cachedAudio(chunk, store, voice);
      await _player.stop();
      await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
      await _player.onPlayerComplete.first.timeout(const Duration(minutes: 3));
    }
  }

  Future<Uint8List> _cachedAudio(
    String chunk,
    LocalStore store,
    IronVoiceOption voice,
  ) async {
    final key = cacheKey(
        voiceId: '${voice.id}|${voice.locale}',
        rate: store.ttsRate,
        pitch: store.ttsPitch,
        text: chunk);
    final existing = _cache[key];
    if (existing != null && existing.isFresh) return existing.bytes;

    late final Uint8List bytes;
    if (voice.provider == IronTtsProvider.gemini) {
      bytes = await _geminiSpeech(chunk, store.apiKey, voice.name,
          locale: voice.locale);
    } else {
      bytes = await _groqSpeech(
          chunk, store.backupApiKey, voice.id.substring(5), store.ttsRate);
    }
    if (_cache.length >= _maxCacheEntries) {
      final oldest = _cache.entries.reduce(
        (a, b) => a.value.storedAt.isBefore(b.value.storedAt) ? a : b,
      );
      _cache.remove(oldest.key);
    }
    _cache[key] = _CacheEntry(bytes);
    return bytes;
  }

  Future<Uint8List> _geminiSpeech(String text, String apiKey, String voiceName,
      {String locale = 'bg-BG'}) async {
    if (apiKey.trim().isEmpty) {
      throw StateError('Липсва Gemini ключ.');
    }
    Object? lastError;
    final models = [
      if (_lastGeminiModel != null) _lastGeminiModel!,
      ...geminiModels,
    ].toSet().toList();
    for (final model in models) {
      for (final body in _geminiBodies(text, voiceName, locale: locale)) {
        try {
          final uri = Uri.parse(
              '$geminiBase/models/$model:generateContent?key=${Uri.encodeQueryComponent(apiKey)}');
          final response = await _http
              .post(
                uri,
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode(body),
              )
              .timeout(const Duration(seconds: 45));
          if (response.statusCode == 429) {
            throw _RateLimit('Gemini достигна лимита.');
          }
          if (response.statusCode >= 400) {
            lastError = response.body;
            continue;
          }
          final decoded = jsonDecode(response.body);
          if (decoded is! Map) continue;
          final candidates = decoded['candidates'];
          if (candidates is! List || candidates.isEmpty) continue;
          final content = candidates.first['content'];
          final parts = content is Map ? content['parts'] : null;
          if (parts is! List || parts.isEmpty) continue;
          final inline =
              parts.first['inlineData'] ?? parts.first['inline_data'];
          if (inline is! Map) continue;
          final data = inline['data']?.toString();
          if (data == null || data.isEmpty) continue;
          _lastGeminiModel = model;
          final raw = base64Decode(data);
          final mime =
              (inline['mimeType'] ?? inline['mime_type'] ?? '').toString();
          return audioBytesForPlayback(raw, mime);
        } on _RateLimit {
          rethrow;
        } catch (error) {
          lastError = error;
        }
      }
    }
    throw StateError('Gemini TTS не успя: $lastError');
  }

  List<Map<String, Object>> _geminiBodies(
    String text,
    String voiceName, {
    String locale = 'bg-BG',
  }) {
    final languageCode =
        locale.trim().isEmpty ? 'bg-BG' : locale.replaceAll('_', '-');
    return [
      {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': text},
            ],
          },
        ],
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'speechConfig': {
            'languageCode': languageCode,
            'voiceConfig': {'voice': voiceName},
          },
        },
      },
      {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': text},
            ],
          },
        ],
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'speechConfig': {
            'languageCode': languageCode,
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': voiceName},
            },
          },
        },
      },
    ];
  }

  Future<Uint8List> _groqSpeech(
    String text,
    String apiKey,
    String voiceId,
    double rate,
  ) async {
    if (apiKey.trim().isEmpty) {
      throw StateError('Липсва Groq ключ.');
    }
    final speed = (0.5 + (rate - 0.3) * (1.5 / 0.4)).clamp(0.5, 1.5);
    final response = await _http
        .post(
          Uri.parse(groqEndpoint),
          headers: {
            'Authorization': 'Bearer ${apiKey.trim()}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': groqModel,
            'input': text,
            'voice': voiceId,
            'response_format': 'wav',
            'speed': speed,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 429) {
      throw _RateLimit('Groq достигна лимита.');
    }
    if (response.statusCode >= 400) {
      throw StateError('Groq TTS грешка ${response.statusCode}');
    }
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) throw StateError('Groq върна празен аудио отговор.');
    return _isWav(bytes) ? bytes : _wrapPcmAsWav(bytes);
  }

  Future<IronVoiceOption> _bestDevice(
    LocalStore store, {
    required List<IronVoiceOption> voices,
  }) async {
    return _bestDeviceVoice(voices, bulgarian: true) ??
        await resolveSelection(store, voices);
  }

  static bool _isWav(Uint8List bytes) {
    return bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46;
  }

  /// Parses a Gemini/Groq audio mime type into encoding + sample rate.
  /// Linear PCM/WAV from Gemini TTS is 24 kHz mono 16-bit unless rate= is set.
  /// μ-law / A-law default to 8 kHz and must not be wrapped as 24 kHz PCM.
  static ({int sampleRate, String encoding}) parseAudioMime(String mime) {
    final lower = mime.toLowerCase();
    var rate = 24000;
    final match = RegExp(r'rate=(\d+)').firstMatch(lower);
    if (match != null) {
      rate = int.parse(match.group(1)!);
    }
    if (lower.contains('mulaw') ||
        lower.contains('u-law') ||
        lower.contains('ulaw') ||
        lower.contains('pcmu')) {
      return (sampleRate: match != null ? rate : 8000, encoding: 'mulaw');
    }
    if (lower.contains('alaw') ||
        lower.contains('a-law') ||
        lower.contains('pcma')) {
      return (sampleRate: match != null ? rate : 8000, encoding: 'alaw');
    }
    return (sampleRate: rate, encoding: 'pcm');
  }

  static Uint8List audioBytesForPlayback(Uint8List raw, String mime) {
    final lower = mime.toLowerCase();
    if (lower.contains('wav') || _isWav(raw)) return raw;
    final parsed = parseAudioMime(mime);
    var pcm = raw;
    if (parsed.encoding == 'mulaw') {
      pcm = _mulawToPcm16(raw);
    } else if (parsed.encoding == 'alaw') {
      pcm = _alawToPcm16(raw);
    }
    return _wrapPcmAsWav(pcm, sampleRate: parsed.sampleRate);
  }

  static Uint8List _mulawToPcm16(Uint8List mulaw) {
    final out = Uint8List(mulaw.length * 2);
    for (var i = 0; i < mulaw.length; i++) {
      final sample = _decodeMulaw(mulaw[i]);
      out[i * 2] = sample & 0xff;
      out[i * 2 + 1] = (sample >> 8) & 0xff;
    }
    return out;
  }

  static Uint8List _alawToPcm16(Uint8List alaw) {
    final out = Uint8List(alaw.length * 2);
    for (var i = 0; i < alaw.length; i++) {
      final sample = _decodeAlaw(alaw[i]);
      out[i * 2] = sample & 0xff;
      out[i * 2 + 1] = (sample >> 8) & 0xff;
    }
    return out;
  }

  static int _decodeMulaw(int value) {
    final byte = ~value & 0xff;
    final sign = byte & 0x80;
    final exponent = (byte >> 4) & 0x07;
    final mantissa = byte & 0x0f;
    var sample = ((mantissa << 3) + 0x84) << exponent;
    sample -= 0x84;
    return sign != 0 ? -sample : sample;
  }

  static int _decodeAlaw(int value) {
    var byte = value ^ 0x55;
    final sign = byte & 0x80;
    final exponent = (byte >> 4) & 0x07;
    final mantissa = byte & 0x0f;
    var sample = exponent == 0
        ? (mantissa << 4) + 8
        : ((mantissa << 4) + 0x108) << (exponent - 1);
    return sign != 0 ? sample : -sample;
  }

  static Uint8List _wrapPcmAsWav(Uint8List pcm, {int sampleRate = 24000}) {
    final header = BytesBuilder();
    final dataLength = pcm.length;
    final fileLength = 36 + dataLength;
    header.add(ascii.encode('RIFF'));
    header.add(_le32(fileLength));
    header.add(ascii.encode('WAVE'));
    header.add(ascii.encode('fmt '));
    header.add(_le32(16));
    header.add(_le16(1));
    header.add(_le16(1));
    header.add(_le32(sampleRate));
    header.add(_le32(sampleRate * 2));
    header.add(_le16(2));
    header.add(_le16(16));
    header.add(ascii.encode('data'));
    header.add(_le32(dataLength));
    header.add(pcm);
    return header.toBytes();
  }

  static Uint8List _le16(int value) =>
      Uint8List.fromList([value & 0xff, (value >> 8) & 0xff]);

  static Uint8List _le32(int value) => Uint8List.fromList([
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ]);
}

class _RateLimit implements Exception {
  final String message;
  _RateLimit(this.message);
  @override
  String toString() => message;
}
