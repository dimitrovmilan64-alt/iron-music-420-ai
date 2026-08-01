import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/chat_message.dart';
import '../services/automation_service.dart';
import '../services/gemini_service.dart';
import '../services/local_store.dart';
import '../services/speech_error_policy.dart';
import '../ui/common_widgets.dart';

class ChatPage extends StatefulWidget {
  final LocalStore store;
  final VoidCallback? onOpenTools;

  const ChatPage({
    super.key,
    required this.store,
    this.onOpenTools,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin {
  static const _welcomeText =
      'Готов съм. Добави поне един AI доставчик и ме попитай на български.';

  final TextEditingController _messageController = TextEditingController();
  late final TextEditingController _apiKeyController;
  late final TextEditingController _backupApiKeyController;
  late final TextEditingController _backupBaseUrlController;
  late final TextEditingController _backupModelController;
  final ScrollController _scrollController = ScrollController();
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final GeminiService _gemini = GeminiService();
  final AutomationService _automation = AutomationService();
  late final AnimationController _coreController;

  late List<ChatMessage> _messages;
  bool _isLoading = false;
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _voiceReady = false;
  bool _speechSendTriggered = false;
  bool _speechHeard = false;
  bool _speechRetryScheduled = false;
  int _speechTimeoutRetryCount = 0;
  String _bulgarianLocale = 'bg_BG';
  List<Map<String, String>> _bulgarianVoices = const [];
  String _selectedVoiceName = '';
  String _selectedVoiceLocale = '';
  double _voiceRate = 0.44;
  double _voicePitch = 0.92;

  @override
  void initState() {
    super.initState();
    _coreController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _apiKeyController = TextEditingController(text: widget.store.apiKey);
    _backupApiKeyController =
        TextEditingController(text: widget.store.backupApiKey);
    _backupBaseUrlController =
        TextEditingController(text: widget.store.backupBaseUrl);
    _backupModelController =
        TextEditingController(text: widget.store.backupModel);
    _messages = List<ChatMessage>.from(widget.store.chatHistory);

    if (_messages.isEmpty) {
      _messages = [
        ChatMessage(
          text: _welcomeText,
          isUser: false,
          isLocalNotice: true,
          createdAt: DateTime.now(),
        ),
      ];
      Future.microtask(() => widget.store.replaceChatHistory(_messages));
    }

    _voiceRate = widget.store.ttsRate;
    _voicePitch = widget.store.ttsPitch;
    _selectedVoiceName = widget.store.ttsVoiceName;
    _selectedVoiceLocale = widget.store.ttsVoiceLocale;
    _configureBulgarianVoice();
    _prepareSpeechRecognition();
  }

  @override
  void dispose() {
    _coreController.dispose();
    _flutterTts.stop();
    _speechToText.stop();
    _gemini.dispose();
    _messageController.dispose();
    _apiKeyController.dispose();
    _backupApiKeyController.dispose();
    _backupBaseUrlController.dispose();
    _backupModelController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int _voiceScore(Map<String, String> voice) {
    final name = (voice['name'] ?? '').toLowerCase();
    var score = 0;
    for (final word in const [
      'natural',
      'neural',
      'network',
      'online',
      'enhanced',
      'premium',
      'wavenet',
      'high',
    ]) {
      if (name.contains(word)) score += 10;
    }
    for (final word in const ['embedded', 'local', 'compact']) {
      if (name.contains(word)) score -= 3;
    }
    return score;
  }

  Future<void> _applyVoice({
    required double rate,
    required double pitch,
    required String voiceName,
    required String voiceLocale,
  }) async {
    await _flutterTts.setLanguage(
      voiceLocale.isEmpty ? 'bg-BG' : voiceLocale.replaceAll('_', '-'),
    );
    await _flutterTts.setSpeechRate(rate);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(pitch);
    await _flutterTts.awaitSpeakCompletion(true);

    if (voiceName.isNotEmpty) {
      await _flutterTts.setVoice({
        'name': voiceName,
        'locale': voiceLocale.isEmpty ? 'bg-BG' : voiceLocale,
      });
    }
  }

  Future<void> _configureBulgarianVoice() async {
    try {
      final dynamic voices = await _flutterTts.getVoices;
      final found = <Map<String, String>>[];

      if (voices is List) {
        for (final dynamic item in voices) {
          if (item is! Map) continue;
          final locale = item['locale']?.toString() ?? '';
          final name = item['name']?.toString() ?? '';
          if (locale.toLowerCase().startsWith('bg') && name.isNotEmpty) {
            found.add({'name': name, 'locale': locale});
          }
        }
      }

      found.sort((a, b) {
        final scoreCompare = _voiceScore(b).compareTo(_voiceScore(a));
        if (scoreCompare != 0) return scoreCompare;
        return (a['name'] ?? '').compareTo(b['name'] ?? '');
      });

      var selectedName = _selectedVoiceName;
      var selectedLocale = _selectedVoiceLocale;
      final savedVoiceExists = found.any(
        (voice) =>
            voice['name'] == selectedName && voice['locale'] == selectedLocale,
      );

      if (!savedVoiceExists && found.isNotEmpty) {
        selectedName = found.first['name'] ?? '';
        selectedLocale = found.first['locale'] ?? 'bg-BG';
      }

      await _applyVoice(
        rate: _voiceRate,
        pitch: _voicePitch,
        voiceName: selectedName,
        voiceLocale: selectedLocale,
      );

      if (!mounted) return;
      setState(() {
        _bulgarianVoices = found;
        _selectedVoiceName = selectedName;
        _selectedVoiceLocale = selectedLocale;
        _voiceReady = true;
      });
    } catch (_) {
      try {
        await _applyVoice(
          rate: _voiceRate,
          pitch: _voicePitch,
          voiceName: '',
          voiceLocale: 'bg-BG',
        );
      } catch (_) {
        // Текстовите отговори остават достъпни и без TTS.
      }
      if (mounted) setState(() => _voiceReady = false);
    }
  }

  String _voiceKey(Map<String, String> voice) {
    return '${voice['name'] ?? ''}|${voice['locale'] ?? ''}';
  }

  Future<void> _openVoiceSettings() async {
    var tempRate = _voiceRate;
    var tempPitch = _voicePitch;
    var tempVoiceName = _selectedVoiceName;
    var tempVoiceLocale = _selectedVoiceLocale;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selectedKey =
              tempVoiceName.isEmpty ? null : '$tempVoiceName|$tempVoiceLocale';
          final validSelectedKey = _bulgarianVoices.any(
            (voice) => _voiceKey(voice) == selectedKey,
          )
              ? selectedKey
              : null;

          return AlertDialog(
            title: const Text('Настройки на гласа'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_bulgarianVoices.isEmpty)
                    const Text(
                      'На телефона не е намерен отделен български глас. Ще се използва системният.',
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: validSelectedKey,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Български глас',
                      ),
                      items: _bulgarianVoices.map((voice) {
                        final name = voice['name'] ?? 'Глас';
                        final locale = voice['locale'] ?? 'bg-BG';
                        return DropdownMenuItem<String>(
                          value: _voiceKey(voice),
                          child: Text(
                            '$name ($locale)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        final selected = _bulgarianVoices.firstWhere(
                          (voice) => _voiceKey(voice) == value,
                        );
                        setDialogState(() {
                          tempVoiceName = selected['name'] ?? '';
                          tempVoiceLocale = selected['locale'] ?? 'bg-BG';
                        });
                      },
                    ),
                  const SizedBox(height: 18),
                  Text('Скорост: ${(tempRate * 100).round()}%'),
                  Slider(
                    value: tempRate,
                    min: 0.30,
                    max: 0.65,
                    divisions: 14,
                    label: tempRate.toStringAsFixed(2),
                    onChanged: (value) {
                      setDialogState(() => tempRate = value);
                    },
                  ),
                  Text('Плътност на гласа: ${(tempPitch * 100).round()}%'),
                  Slider(
                    value: tempPitch,
                    min: 0.75,
                    max: 1.10,
                    divisions: 14,
                    label: tempPitch.toStringAsFixed(2),
                    onChanged: (value) {
                      setDialogState(() => tempPitch = value);
                    },
                  ),
                  const Text(
                    'За по-естествено звучене остави скоростта около 44% и плътността около 92%.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отказ'),
              ),
              TextButton.icon(
                onPressed: () async {
                  try {
                    await _flutterTts.stop();
                    await _applyVoice(
                      rate: tempRate,
                      pitch: tempPitch,
                      voiceName: tempVoiceName,
                      voiceLocale: tempVoiceLocale,
                    );
                    await _flutterTts.speak(
                      'Здравей. Аз съм Iron Music 420 AI. Това е тест на българския глас.',
                    );
                  } catch (_) {
                    if (mounted) {
                      _showMessage('Тестът на гласа не можа да стартира.');
                    }
                  }
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Тест'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Запази'),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true || !mounted) {
      await _configureBulgarianVoice();
      return;
    }

    _voiceRate = tempRate;
    _voicePitch = tempPitch;
    _selectedVoiceName = tempVoiceName;
    _selectedVoiceLocale = tempVoiceLocale;
    await widget.store.saveVoiceSettings(
      rate: tempRate,
      pitch: tempPitch,
      voiceName: tempVoiceName,
      voiceLocale: tempVoiceLocale,
    );
    await _configureBulgarianVoice();
    if (mounted) _showMessage('Настройките на гласа са запазени.');
  }

  Future<void> _prepareSpeechRecognition() async {
    try {
      final available = await _speechToText.initialize(
        options: [stt.SpeechToText.androidNoBluetooth],
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            final shouldAutoSend = _isListening &&
                !_speechSendTriggered &&
                _messageController.text.trim().isNotEmpty;
            setState(() => _isListening = false);
            if (shouldAutoSend) {
              Future.microtask(_sendRecognizedSpeech);
            }
          }
        },
        onError: (error) {
          _handleSpeechError(error.errorMsg);
        },
      );

      String localeId = 'bg_BG';
      if (available) {
        final locales = await _speechToText.locales();
        for (final locale in locales) {
          final normalized = locale.localeId.toLowerCase();
          if (normalized == 'bg_bg' || normalized.startsWith('bg')) {
            localeId = locale.localeId;
            break;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _speechAvailable = available;
        _bulgarianLocale = localeId;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _speechAvailable = false);
    }
  }

  Future<void> _speak(String text) async {
    if (!widget.store.voiceRepliesEnabled) return;

    final cleanText = cleanTextForSpeech(text);
    if (cleanText.isEmpty) return;

    final textForSpeech = cleanText.length > 3900
        ? '${cleanText.substring(0, 3900)}. Краят е съкратен за гласовото прочитане.'
        : cleanText;

    try {
      await _flutterTts.stop();
      await _flutterTts.speak(textForSpeech);
    } catch (_) {
      // Текстовият отговор остава наличен и без TTS.
    }
  }

  Future<void> _toggleVoiceReplies() async {
    final enabled = !widget.store.voiceRepliesEnabled;
    await widget.store.setVoiceRepliesEnabled(enabled);
    if (!mounted) return;
    setState(() {});

    if (enabled) {
      await _speak('Гласовите отговори са включени.');
    } else {
      await _flutterTts.stop();
    }
  }

  Future<void> _sendRecognizedSpeech() async {
    if (_speechSendTriggered || _isLoading) return;
    if (_messageController.text.trim().isEmpty) return;

    _speechSendTriggered = true;
    if (mounted) setState(() => _isListening = false);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _sendMessage();
  }

  void _handleSpeechError(String errorMessage) {
    if (!mounted) return;

    final canRetry = SpeechErrorPolicy.shouldRetry(errorMessage) &&
        !_speechHeard &&
        !_speechSendTriggered &&
        !_isLoading &&
        _speechTimeoutRetryCount < 1 &&
        !_speechRetryScheduled;

    setState(() => _isListening = false);

    if (canRetry) {
      _speechTimeoutRetryCount++;
      _speechRetryScheduled = true;
      Future<void>.delayed(const Duration(milliseconds: 550), () async {
        if (!mounted) return;
        _speechRetryScheduled = false;
        if (_isLoading || _speechSendTriggered) return;

        try {
          await _speechToText.cancel();
        } catch (_) {
          // Android may already have closed the timed-out recognizer.
        }
        if (!mounted) return;
        await _startSpeechListening(isRetry: true);
      });
      return;
    }

    _speechRetryScheduled = false;
    _showMessage(SpeechErrorPolicy.friendlyMessage(errorMessage));
  }

  Future<void> _startSpeechListening({required bool isRetry}) async {
    if (!mounted || _isLoading) return;

    await _flutterTts.stop();
    await Future<void>.delayed(
      Duration(milliseconds: isRetry ? 450 : 300),
    );
    if (!mounted) return;

    if (!_speechAvailable) {
      await _prepareSpeechRecognition();
    }

    if (!_speechAvailable) {
      if (mounted) {
        _showMessage(
          'Разпознаването на реч не е налично. Разреши микрофона и провери Google Speech Services.',
        );
      }
      return;
    }

    if (!isRetry) _speechTimeoutRetryCount = 0;
    _speechHeard = false;
    _speechSendTriggered = false;
    setState(() => _isListening = true);

    try {
      await _speechToText.listen(
        localeId: _bulgarianLocale,
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
        onResult: (result) {
          if (!mounted) return;
          final recognized = result.recognizedWords.trim();
          if (recognized.isNotEmpty) _speechHeard = true;
          setState(() {
            _messageController.text = recognized;
            _messageController.selection = TextSelection.fromPosition(
              TextPosition(offset: _messageController.text.length),
            );
          });

          if (result.finalResult && recognized.isNotEmpty) {
            Future.microtask(_sendRecognizedSpeech);
          }
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isListening = false);
      _showMessage(
        SpeechErrorPolicy.friendlyMessage('error_recognizer_busy'),
      );
    }
  }

  Future<void> _toggleListening() async {
    if (_speechToText.isListening) {
      _speechRetryScheduled = false;
      await _speechToText.stop();
      if (mounted) setState(() => _isListening = false);
      await _sendRecognizedSpeech();
      return;
    }

    await _startSpeechListening(isRetry: false);
  }

  Future<void> _syncNativeAiSettings() {
    return _automation.syncAiProviderSettings(
      geminiApiKey: widget.store.apiKey,
      backupApiKey: widget.store.backupApiKey,
      backupBaseUrl: widget.store.backupBaseUrl,
      backupModel: widget.store.backupModel,
    );
  }

  Future<bool> _saveAiProviders() async {
    final geminiKey = _apiKeyController.text.trim();
    final backupKey = _backupApiKeyController.text.trim();
    final backupBaseUrl = _backupBaseUrlController.text.trim();
    final backupModel = _backupModelController.text.trim();

    if (geminiKey.isEmpty && backupKey.isEmpty) {
      _showMessage('Добави Gemini или резервен AI API ключ.');
      return false;
    }

    if (backupKey.isNotEmpty) {
      final normalizedBase = backupBaseUrl.endsWith('/chat/completions')
          ? backupBaseUrl
          : '${backupBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/chat/completions';
      final endpoint = Uri.tryParse(normalizedBase);
      if (endpoint == null ||
          !endpoint.hasScheme ||
          endpoint.host.isEmpty ||
          (endpoint.scheme != 'https' && endpoint.scheme != 'http')) {
        _showMessage('Адресът на резервния AI доставчик не е валиден.');
        return false;
      }
      if (backupModel.isEmpty) {
        _showMessage('Въведи модел за резервния AI доставчик.');
        return false;
      }
    }

    await widget.store.setApiKey(geminiKey);
    await widget.store.setBackupProvider(
      apiKey: backupKey,
      baseUrl: backupBaseUrl,
      model: backupModel,
    );
    await _syncNativeAiSettings();
    _gemini.resetModel();
    if (!mounted) return false;
    setState(() {});
    _showMessage('AI доставчиците са запазени локално на телефона.');
    return true;
  }

  Future<void> _clearGeminiApiKey() async {
    _apiKeyController.clear();
    await widget.store.setApiKey('');
    await _syncNativeAiSettings();
    _gemini.resetModel();
    if (!mounted) return;
    setState(() {});
    _showMessage('Gemini ключът е премахнат.');
  }

  Future<void> _clearBackupProvider() async {
    _backupApiKeyController.clear();
    await widget.store.setBackupProvider(
      apiKey: '',
      baseUrl: _backupBaseUrlController.text,
      model: _backupModelController.text,
    );
    await _syncNativeAiSettings();
    _gemini.resetModel();
    if (!mounted) return;
    setState(() {});
    _showMessage('Резервният AI ключ е премахнат.');
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;

    await _speechToText.stop();

    final apiKey = widget.store.apiKey.trim();
    if (!widget.store.hasAnyAiProvider) {
      await _openApiKeySheet();
      return;
    }

    final userMessage = ChatMessage(
      text: text,
      isUser: true,
      createdAt: DateTime.now(),
    );

    setState(() {
      _isListening = false;
      _messages.add(userMessage);
      _messageController.clear();
      _isLoading = true;
    });
    await widget.store.replaceChatHistory(_messages);
    _scrollToBottom();

    try {
      final reply = await _gemini.generateChat(
        apiKey: apiKey,
        history: _messages,
      );
      if (!mounted) return;

      final aiMessage = ChatMessage(
        text: reply,
        isUser: false,
        createdAt: DateTime.now(),
      );
      setState(() => _messages.add(aiMessage));
      await widget.store.replaceChatHistory(_messages);
      _scrollToBottom();
      await _speak(reply);
    } on GeminiException catch (error) {
      if (!mounted) return;
      await _addLocalNotice(error.message);
    } catch (_) {
      if (!mounted) return;
      await _addLocalNotice('Неочаквана грешка при връзката с AI.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _addLocalNotice(String text) async {
    final message = ChatMessage(
      text: text,
      isUser: false,
      isLocalNotice: true,
      createdAt: DateTime.now(),
    );
    setState(() => _messages.add(message));
    await widget.store.replaceChatHistory(_messages);
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Изчистване на историята'),
        content: const Text(
          'Да бъдат ли изтрити всички запазени съобщения?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отказ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Изтрий'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final welcome = ChatMessage(
      text: _welcomeText,
      isUser: false,
      isLocalNotice: true,
      createdAt: DateTime.now(),
    );
    setState(() => _messages = [welcome]);
    await widget.store.replaceChatHistory(_messages);
    _showMessage('Историята е изчистена.');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _showMessage(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _openApiKeySheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    _apiKeyController.text = widget.store.apiKey;
    _backupApiKeyController.text = widget.store.backupApiKey;
    _backupBaseUrlController.text = widget.store.backupBaseUrl;
    _backupModelController.text = widget.store.backupModel;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Material(
            color: ironPanelRaised,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Icon(Icons.hub_rounded, color: ironGreen),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'AI доставчици',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Iron използва Gemini първо. При лимит или недостъпност автоматично преминава към резервния OpenAI-съвместим доставчик. Ключовете се пазят само локално на телефона.',
                    style: TextStyle(color: Colors.white60, height: 1.35),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '1. Основен доставчик · Gemini',
                    style: TextStyle(
                      color: ironGreen,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Gemini API ключ',
                      hintText: 'AIza...',
                      prefixIcon: Icon(Icons.key_rounded),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 14),
                  const Text(
                    '2. Резервен · OpenAI-съвместим',
                    style: TextStyle(
                      color: ironGreen,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'По подразбиране е OpenAI. Адресът и моделът могат да се сменят за друг съвместим доставчик.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _backupApiKeyController,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Резервен API ключ',
                      hintText: 'sk-...',
                      prefixIcon: Icon(Icons.shield_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _backupBaseUrlController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'API адрес',
                      hintText: 'https://api.openai.com/v1',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _backupModelController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Модел',
                      hintText: 'gpt-4.1-mini',
                      prefixIcon: Icon(Icons.memory_rounded),
                    ),
                    onSubmitted: (_) async {
                      final saved = await _saveAiProviders();
                      if (saved && sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                    },
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () async {
                      final saved = await _saveAiProviders();
                      if (saved && sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                    },
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Запази AI доставчиците'),
                  ),
                  if (widget.store.hasApiKey ||
                      widget.store.hasBackupProvider) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (widget.store.hasApiKey)
                          OutlinedButton.icon(
                            onPressed: () async {
                              await _clearGeminiApiKey();
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Премахни Gemini'),
                          ),
                        if (widget.store.hasBackupProvider)
                          OutlinedButton.icon(
                            onPressed: () async {
                              await _clearBackupProvider();
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Премахни резервния'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _roundAction({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? ironGreen.withOpacity(0.16)
                  : Colors.black.withOpacity(0.28),
              border: Border.all(
                color: ironGreen.withOpacity(active ? 0.68 : 0.25),
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: ironGreen.withOpacity(0.16),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: active ? ironGreen : Colors.white60,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantCore(double size) {
    final status = _isListening
        ? 'СЛУШАМ'
        : _isLoading
            ? 'МИСЛЯ'
            : 'ГОТОВ СЪМ';

    return AnimatedBuilder(
      animation: _coreController,
      builder: (context, _) {
        final activity = (_isListening || _isLoading) ? 0.22 : 0.0;
        final progress =
            (_coreController.value * 0.72 + activity).clamp(0.0, 1.0).toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              label: _isListening ? 'Спри слушането' : 'Говори с Iron',
              child: GestureDetector(
                onTap: _isLoading ? null : _toggleListening,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: _isListening ? 1.05 : 1.0,
                  child: CannabisCore(progress: progress, size: size),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              status,
              style: TextStyle(
                color: _isListening ? ironGreenSoft : ironGreen,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                shadows: const [Shadow(color: ironGreen, blurRadius: 10)],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _roundAction(
                  icon: _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                  tooltip: _isListening ? 'Спри слушането' : 'Микрофон',
                  active: _isListening,
                  onPressed: _isLoading ? null : _toggleListening,
                ),
                const SizedBox(width: 12),
                _roundAction(
                  icon: widget.store.voiceRepliesEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  tooltip: widget.store.voiceRepliesEnabled
                      ? (_voiceReady ? 'Гласовите отговори са включени' : 'Системен глас')
                      : 'Гласовите отговори са изключени',
                  active: widget.store.voiceRepliesEnabled,
                  onPressed: _toggleVoiceReplies,
                ),
                const SizedBox(width: 12),
                _roundAction(
                  icon: Icons.key_rounded,
                  tooltip: 'AI доставчици',
                  active: widget.store.hasAnyAiProvider,
                  onPressed: _openApiKeySheet,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final compactHeight = media.size.height < 720;
    final coreSize = compactHeight ? 126.0 : 156.0;

    return IronBackground(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'IRON MUSIC 420 AI',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.store.hasAnyAiProvider
                            ? 'Личен AI асистент'
                            : 'Добави AI доставчик от менюто',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ironGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Настройки',
                  icon: const Icon(Icons.more_horiz_rounded, color: ironGreen),
                  onSelected: (value) {
                    if (value == 'api') {
                      _openApiKeySheet();
                    } else if (value == 'voice') {
                      _openVoiceSettings();
                    } else if (value == 'history') {
                      _clearHistory();
                    } else if (value == 'tools') {
                      widget.onOpenTools?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'api',
                      child: Text('AI доставчици'),
                    ),
                    const PopupMenuItem(
                      value: 'voice',
                      child: Text('Настройки на гласа'),
                    ),
                    if (widget.onOpenTools != null)
                      const PopupMenuItem(
                        value: 'tools',
                        child: Text('Инструменти'),
                      ),
                    const PopupMenuItem(
                      value: 'history',
                      child: Text('Изчисти историята'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: keyboardOpen
                ? const SizedBox(height: 4)
                : Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      compactHeight ? 4 : 8,
                      12,
                      8,
                    ),
                    child: _buildAssistantCore(coreSize),
                  ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isLoading && index == _messages.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(8, 6, 8, 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ironGreen,
                            ),
                          ),
                          SizedBox(width: 9),
                          Text(
                            'Iron мисли...',
                            style: TextStyle(color: ironGreen),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return _ChatBubble(message: _messages[index]);
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: const Color(0xFF010A05).withOpacity(0.98),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: ironGreen.withOpacity(0.30)),
              boxShadow: [
                BoxShadow(
                  color: ironGreen.withOpacity(0.08),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration.collapsed(
                      hintText: _isListening
                          ? 'Слушам на български...'
                          : 'Говори или напиши на Iron...',
                      hintStyle: const TextStyle(color: Colors.white38),
                    ),
                    onSubmitted: (_) {
                      if (!_isLoading) _sendMessage();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Микрофон',
                  onPressed: _isLoading ? null : _toggleListening,
                  icon: Icon(
                    _isListening ? Icons.stop_circle_rounded : Icons.mic_rounded,
                    color: _isListening ? Colors.redAccent : ironGreen,
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Изпрати',
                  onPressed: _isLoading ? null : _sendMessage,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final alignment =
        message.isUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = message.isUser
        ? ironGreen.withOpacity(0.18)
        : message.isLocalNotice
            ? Colors.orange.withOpacity(0.12)
            : const Color(0xFF04150A);
    final borderColor = message.isUser
        ? ironGreen
        : message.isLocalNotice
            ? Colors.orangeAccent.withOpacity(0.7)
            : Colors.white12;

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.84,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(message.isUser ? 18 : 5),
            bottomRight: Radius.circular(message.isUser ? 5 : 18),
          ),
          border: Border.all(color: borderColor.withOpacity(0.8)),
          boxShadow: [
            BoxShadow(
              color:
                  (message.isUser ? ironGreen : Colors.black).withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    message.sender,
                    style: TextStyle(
                      color: message.isUser ? ironGreen : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: message.text),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Съобщението е копирано.')),
                      );
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.copy, size: 15, color: Colors.white54),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            SelectableText(
              cleanMarkdownForDisplay(message.text),
              style: const TextStyle(color: Colors.white, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
