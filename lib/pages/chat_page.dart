import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/chat_message.dart';
import '../services/ai_provider_config.dart';
import '../services/automation_service.dart';
import '../services/gemini_service.dart';
import '../services/local_store.dart';
import '../ui/common_widgets.dart';

class ChatPage extends StatefulWidget {
  final LocalStore store;
  final VoidCallback? onOpenTools;
  final VoidCallback? onOpenStudio;
  final VoidCallback? onOpenSongs;
  final Future<void> Function(String text)? onSendToStudio;

  const ChatPage({
    super.key,
    required this.store,
    this.onOpenTools,
    this.onOpenStudio,
    this.onOpenSongs,
    this.onSendToStudio,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _welcomeText =
      'Аз съм Айрън. Говори или пиши тук — това е единният ни разговор.';

  final TextEditingController _messageController = TextEditingController();
  late final TextEditingController _apiKeyController;
  late final TextEditingController _backupApiKeyController;
  late final TextEditingController _backupBaseUrlController;
  late final TextEditingController _backupModelController;
  final ScrollController _scrollController = ScrollController();
  final FlutterTts _flutterTts = FlutterTts();
  final GeminiService _gemini = GeminiService();
  final AutomationService _automation = AutomationService();
  late final AnimationController _coreController;

  late List<ChatMessage> _messages;
  bool _isLoading = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _ironActive = false;
  bool _chatPanelOpen = false;
  bool _voiceToggleBusy = false;
  bool _processingPendingChatPrompt = false;
  bool _voiceReady = false;
  List<Map<String, String>> _bulgarianVoices = const [];
  String _selectedVoiceName = '';
  String _selectedVoiceLocale = '';
  double _voiceRate = 0.44;
  double _voicePitch = 0.92;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(_handleStoreChange);
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
    _automation.setNativeSpeechPartialListener((recognized) {
      if (!mounted || !_isListening) return;
      setState(() {
        _messageController.text = recognized;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadIronStatus();
      _consumePendingChatVoiceRequest();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_handleStoreChange);
    _coreController.dispose();
    _flutterTts.stop();
    _automation.setNativeSpeechPartialListener(null);
    _automation.cancelNativeSpeechRecognition();
    _gemini.dispose();
    _messageController.dispose();
    _apiKeyController.dispose();
    _backupApiKeyController.dispose();
    _backupBaseUrlController.dispose();
    _backupModelController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadIronStatus();
      _consumePendingChatVoiceRequest();
    }
  }

  void _handleStoreChange() {
    if (!widget.store.hasPendingChatVoiceRequest ||
        _processingPendingChatPrompt) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingChatVoiceRequest();
    });
  }

  Future<void> _consumePendingChatVoiceRequest() async {
    if (!mounted || _processingPendingChatPrompt || _isLoading) return;
    final prompt = widget.store.takePendingChatVoiceRequest();
    if (prompt == null) return;

    _processingPendingChatPrompt = true;
    setState(() {
      _messageController.text = prompt;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: prompt.length),
      );
    });
    try {
      await _sendMessage();
    } finally {
      _processingPendingChatPrompt = false;
    }
    if (widget.store.hasPendingChatVoiceRequest) {
      _handleStoreChange();
    }
  }

  Future<void> _loadIronStatus() async {
    final active = await _automation.isIronVoiceActive();
    if (!mounted) return;
    setState(() => _ironActive = active);
  }

  Future<void> _toggleIronMode() async {
    if (_voiceToggleBusy) return;
    setState(() => _voiceToggleBusy = true);
    final result = await _automation.execute(
      _ironActive ? 'iron_voice_off' : 'iron_voice_on',
    );
    if (!mounted) return;
    setState(() {
      _voiceToggleBusy = false;
      if (result.success) _ironActive = !_ironActive;
    });
    _showMessage(result.message);
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
                    await _playSpeechWithWakePaused(
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

  Future<void> _speak(String text) async {
    if (!widget.store.voiceRepliesEnabled) return;

    final cleanText = cleanTextForSpeech(text);
    if (cleanText.isEmpty) return;

    final textForSpeech = cleanText.length > 3900
        ? '${cleanText.substring(0, 3900)}. Краят е съкратен за гласовото прочитане.'
        : cleanText;

    await _playSpeechWithWakePaused(textForSpeech);
  }

  Future<void> _playSpeechWithWakePaused(String text) async {
    if (mounted) setState(() => _isSpeaking = true);
    final resumeIronVoice = await _automation.pauseIronVoiceCapture();
    try {
      if (resumeIronVoice) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
      await _flutterTts.stop();
      await _flutterTts
          .speak(text)
          .timeout(const Duration(minutes: 7));
    } catch (_) {
      try {
        await _flutterTts.stop();
      } catch (_) {
        // The wake listener still has to be restored below.
      }
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
      if (resumeIronVoice) {
        await _automation.resumeIronVoiceCapture();
      }
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

  Future<void> _toggleListening() async {
    if (_isLoading) return;

    if (_isListening) {
      await _automation.stopNativeSpeechRecognition();
      return;
    }

    await _flutterTts.stop();
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;

    setState(() => _isListening = true);
    final result = await _automation.startNativeSpeechRecognition();
    if (!mounted) return;

    setState(() => _isListening = false);
    if (!result.success) {
      if (result.message.trim().isNotEmpty) {
        _showMessage(result.message.trim());
      }
      return;
    }

    final recognized = result.text.trim();
    if (recognized.isEmpty) {
      _showMessage('Не чух думи. Натисни микрофона и говори след сигнала.');
      return;
    }

    setState(() {
      _messageController.text = recognized;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
    });
    await _sendMessage();
  }

  bool _requestsStudioTransfer(String value) {
    final text = value.toLowerCase();
    final mentionsStudio = text.contains('рап студио') ||
        text.contains('rap studio') ||
        text.contains('студиото') ||
        text.contains('студио');
    final asksTransfer = text.contains('прехвърли') ||
        text.contains('прати') ||
        text.contains('изпрати') ||
        text.contains('сложи') ||
        text.contains('вкарай') ||
        text.contains('отвори го');
    return mentionsStudio && asksTransfer;
  }

  bool _isDirectStudioTransferCommand(String value) {
    if (!_requestsStudioTransfer(value)) return false;
    final text = value.toLowerCase();
    final asksCreation = text.contains('напиши') ||
        text.contains('направи') ||
        text.contains('създай') ||
        text.contains('генерирай') ||
        text.contains('измисли') ||
        text.contains('редактирай');
    return !asksCreation;
  }

  ChatMessage? _lastAssistantMessage() {
    for (final message in _messages.reversed) {
      if (!message.isUser && !message.isLocalNotice && message.text.trim().isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  Future<void> _sendTextToStudio(String text) async {
    final cleanText = cleanMarkdownForDisplay(text).trim();
    if (cleanText.isEmpty) {
      _showMessage('Няма текст за прехвърляне.');
      return;
    }
    final callback = widget.onSendToStudio;
    if (callback == null) {
      _showMessage('Рап студиото не е достъпно.');
      return;
    }
    await callback(cleanText);
    if (mounted) {
      _showMessage('Текстът е прехвърлен в Рап студио.');
    }
  }

  Future<bool> _saveAiProviders() async {
    final geminiKey = _apiKeyController.text.trim();
    final backupKey = _backupApiKeyController.text.trim();
    final backupBaseUrl = backupKey.isEmpty
        ? _backupBaseUrlController.text.trim()
        : AiProviderConfig.defaultBackupBaseUrl;
    final backupModel = backupKey.isEmpty
        ? _backupModelController.text.trim()
        : AiProviderConfig.defaultBackupModel;

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
    _gemini.resetModel();
    if (!mounted) return false;
    setState(() {});
    _showMessage('Gemini и Groq са запазени локално на телефона.');
    return true;
  }

  Future<void> _clearGeminiApiKey() async {
    _apiKeyController.clear();
    await widget.store.setApiKey('');
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
    _gemini.resetModel();
    if (!mounted) return;
    setState(() {});
    _showMessage('Groq ключът е премахнат.');
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;

    if (_isListening) {
      await _automation.cancelNativeSpeechRecognition();
      if (mounted) setState(() => _isListening = false);
    }

    final wantsStudioTransfer = _requestsStudioTransfer(text);
    if (_isDirectStudioTransferCommand(text)) {
      final previous = _lastAssistantMessage();
      _messageController.clear();
      if (previous == null) {
        _showMessage('Първо нека напиша текст, който да прехвърля.');
        return;
      }
      await _sendTextToStudio(previous.text);
      return;
    }

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
      if (wantsStudioTransfer) {
        await _sendTextToStudio(reply);
      }
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
                    'Iron използва Gemini първо. При лимит или недостъпност автоматично преминава към Groq. Ключовете се пазят само локално на телефона.',
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
                    '2. Резервен доставчик · Groq',
                    style: TextStyle(
                      color: ironGreen,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Постави само Groq API ключа. Адресът и моделът се настройват автоматично.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _backupApiKeyController,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Groq API ключ',
                      hintText: 'gsk_...',
                      prefixIcon: Icon(Icons.shield_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Color(0x3300FF77),
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                    ),
                    child: Text(
                      'Groq Free · openai/gpt-oss-20b',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
    required String label,
    required String tooltip,
    required bool active,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: active
                  ? ironGreen.withOpacity(0.18)
                  : Colors.black.withOpacity(0.34),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: active ? ironGreen : Colors.white60,
                  size: 17,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? ironGreenSoft : Colors.white60,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hudChip({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    final color = active ? ironGreenSoft : Colors.white54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? ironGreen.withOpacity(0.12)
            : Colors.black.withOpacity(0.24),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withOpacity(active ? 0.48 : 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.55,
            ),
          ),
        ],
      ),
    );
  }

  void _openChatPanel() {
    if (!mounted) return;
    setState(() => _chatPanelOpen = true);
  }

  Widget _hudPanel({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool active = false,
  }) {
    final color = active ? ironGreenSoft : ironGreen;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(active ? 0.44 : 0.30),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(active ? 0.70 : 0.34)),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(active ? 0.18 : 0.08),
                blurRadius: active ? 18 : 12,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: color.withOpacity(0.35)),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.35,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? ironGreenSoft : Colors.white60,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPanel({
    required IconData icon,
    required String title,
    required String value,
    bool active = true,
  }) {
    final color = active ? ironGreenSoft : Colors.white54;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(active ? 0.40 : 0.18)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(active ? 0.12 : 0.04),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _coreDockButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool active = false,
  }) {
    final color = active ? ironGreenSoft : Colors.white70;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 58,
            decoration: BoxDecoration(
              color: active
                  ? ironGreen.withOpacity(0.16)
                  : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: active
                    ? ironGreen.withOpacity(0.62)
                    : Colors.white.withOpacity(0.10),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantCore(double size) {
    final coreState = switch ((_isListening, _isSpeaking, _isLoading)) {
      (true, _, _) => IronCoreState.listening,
      (_, true, _) => IronCoreState.speaking,
      (_, _, true) => IronCoreState.thinking,
      _ => IronCoreState.idle,
    };
    final status = switch (coreState) {
      IronCoreState.listening => 'СЛУШАМ',
      IronCoreState.thinking => 'МИСЛЯ',
      IronCoreState.speaking => 'ГОВОРЯ',
      IronCoreState.idle => _ironActive
          ? 'ЧАКАМ „ХЕЙ АЙРЪН“'
          : 'ЯДРОТО Е В ПОКОЙ',
    };
    final statusColor = switch (coreState) {
      IronCoreState.listening => const Color(0xFF70FFB0),
      IronCoreState.thinking => const Color(0xFF00E5A0),
      IronCoreState.speaking => const Color(0xFFA8FF70),
      IronCoreState.idle => ironGreen,
    };

    return AnimatedBuilder(
      animation: _coreController,
      builder: (context, _) {
        final activity = coreState == IronCoreState.idle ? 0.0 : 0.16;
        final progress = (_coreController.value * 0.84 + activity)
            .clamp(0.0, 1.0)
            .toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 7,
              children: [
                _hudChip(
                  icon: Icons.hearing_rounded,
                  label: _ironActive ? 'HEY IRON' : 'WAKE OFF',
                  active: _ironActive,
                ),
                _hudChip(
                  icon: Icons.graphic_eq_rounded,
                  label: coreState == IronCoreState.idle ? 'IDLE' : status,
                  active: coreState != IronCoreState.idle,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Semantics(
              button: true,
              label: _isListening ? 'Спри слушането' : 'Говори с Iron',
              child: GestureDetector(
                onTap: _isLoading ? null : _toggleListening,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: _isListening ? 1.025 : 1.0,
                  child: CannabisCore(
                    progress: progress,
                    size: size,
                    state: coreState,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                status,
                key: ValueKey(status),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.7,
                  shadows: [Shadow(color: statusColor, blurRadius: 10)],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: _roundAction(
                    icon: _ironActive
                        ? Icons.hearing_rounded
                        : Icons.hearing_disabled_rounded,
                    label: 'Хей Айрън',
                    tooltip: _ironActive
                        ? 'Изключи „Хей Айрън“'
                        : 'Включи „Хей Айрън“',
                    active: _ironActive,
                    onPressed: _voiceToggleBusy ? null : _toggleIronMode,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _roundAction(
                    icon: widget.store.voiceRepliesEnabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    label: 'Глас',
                    tooltip: widget.store.voiceRepliesEnabled
                        ? (_voiceReady
                            ? 'Гласовите отговори са включени'
                            : 'Системен глас')
                        : 'Гласовите отговори са изключени',
                    active: widget.store.voiceRepliesEnabled,
                    onPressed: _toggleVoiceReplies,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _roundAction(
                    icon: Icons.key_rounded,
                    label: 'AI',
                    tooltip: 'AI доставчици',
                    active: widget.store.hasAnyAiProvider,
                    onPressed: _openApiKeySheet,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildHudDashboard() {
    final media = MediaQuery.of(context);
    final compactHeight = media.size.height < 760;
    final coreSize = (media.size.width * (compactHeight ? 0.86 : 0.94))
        .clamp(300.0, 410.0)
        .toDouble();

    return IronBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Column(
            children: [
              Row(
                children: [
                  _hudChip(
                    icon: Icons.circle_rounded,
                    label: _ironActive ? 'ONLINE' : 'STANDBY',
                    active: _ironActive,
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: 'Настройки',
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      color: ironGreen,
                    ),
                    onSelected: (value) {
                      if (value == 'api') {
                        _openApiKeySheet();
                      } else if (value == 'voice') {
                        _openVoiceSettings();
                      } else if (value == 'history') {
                        _clearHistory();
                      } else if (value == 'tools') {
                        widget.onOpenTools?.call();
                      } else if (value == 'studio') {
                        widget.onOpenStudio?.call();
                      } else if (value == 'songs') {
                        widget.onOpenSongs?.call();
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
                      if (widget.onOpenSongs != null)
                        const PopupMenuItem(
                          value: 'songs',
                          child: Text('Песни'),
                        ),
                      if (widget.onOpenStudio != null)
                        const PopupMenuItem(
                          value: 'studio',
                          child: Text('Студио'),
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
              Expanded(
                child: AnimatedBuilder(
                  animation: _coreController,
                  builder: (context, _) {
                    final coreState = switch ((_isListening, _isSpeaking, _isLoading)) {
                      (true, _, _) => IronCoreState.listening,
                      (_, true, _) => IronCoreState.speaking,
                      (_, _, true) => IronCoreState.thinking,
                      _ => IronCoreState.idle,
                    };
                    final status = switch (coreState) {
                      IronCoreState.listening => 'СЛУШАМ',
                      IronCoreState.thinking => 'МИСЛЯ',
                      IronCoreState.speaking => 'ГОВОРЯ',
                      IronCoreState.idle => _ironActive
                          ? 'КАЖИ „ХЕЙ АЙРЪН“'
                          : 'ДОКОСНИ ЯДРОТО',
                    };
                    final statusColor = switch (coreState) {
                      IronCoreState.listening => const Color(0xFF70FFB0),
                      IronCoreState.thinking => const Color(0xFF00E5A0),
                      IronCoreState.speaking => const Color(0xFFA8FF70),
                      IronCoreState.idle => ironGreen,
                    };
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final safeCoreSize = coreSize
                            .clamp(260.0, constraints.maxHeight * 0.72)
                            .toDouble();
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'IRON',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 7,
                              ),
                            ),
                            Text(
                              'MUSIC 420 AI',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.78),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.5,
                              ),
                            ),
                            SizedBox(height: compactHeight ? 6 : 14),
                            GestureDetector(
                              onTap: _isLoading ? null : _toggleListening,
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 180),
                                scale: _isListening ? 1.035 : 1.0,
                                child: CannabisCore(
                                  progress: _coreController.value,
                                  size: safeCoreSize,
                                  state: coreState,
                                ),
                              ),
                            ),
                            SizedBox(height: compactHeight ? 8 : 16),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Text(
                                status,
                                key: ValueKey(status),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.2,
                                  shadows: [
                                    Shadow(color: statusColor, blurRadius: 12),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _ironActive
                                  ? 'живото ядро слуша за теб'
                                  : 'докосни за разговор',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.58),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.34),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: ironGreen.withOpacity(0.20)),
                  boxShadow: [
                    BoxShadow(
                      color: ironGreen.withOpacity(0.10),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _coreDockButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Чат',
                      onTap: _openChatPanel,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Tooltip(
                        message: _isListening ? 'Спри слушането' : 'Говори',
                        child: FilledButton(
                          onPressed: _isLoading ? null : _toggleListening,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(58),
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                            backgroundColor:
                                _isListening ? Colors.redAccent : ironGreen,
                            foregroundColor: Colors.black,
                          ),
                          child: Icon(
                            _isListening
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _coreDockButton(
                      icon: widget.store.voiceRepliesEnabled
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      label: 'Глас',
                      active: widget.store.voiceRepliesEnabled,
                      onTap: _toggleVoiceReplies,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatMode() {
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final compactHeight = media.size.height < 720;
    final coreSize = compactHeight ? 138.0 : 168.0;

    return IronBackground(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Назад към HUD',
                    onPressed: () => setState(() => _chatPanelOpen = false),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: ironGreen,
                  ),
                  const Expanded(
                    child: Text(
                      'CHAT WITH IRON',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'AI доставчици',
                    onPressed: _openApiKeySheet,
                    icon: const Icon(Icons.key_rounded),
                    color: ironGreen,
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
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                      child: _buildAssistantCore(coreSize),
                    ),
            ),
            Expanded(child: _buildMessageStream()),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageStream() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 3, 10, 0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.20),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ironGreen.withOpacity(0.12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ListView.builder(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
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
            final message = _messages[index];
            return _ChatBubble(
              message: message,
              onSendToStudio: !message.isUser && !message.isLocalNotice
                  ? () => _sendTextToStudio(message.text)
                  : null,
            );
          },
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      padding: const EdgeInsets.fromLTRB(11, 5, 5, 5),
      decoration: BoxDecoration(
        color: const Color(0xFF010A05).withOpacity(0.98),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ironGreen.withOpacity(0.34)),
        boxShadow: [
          BoxShadow(
            color: ironGreen.withOpacity(0.10),
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
            onPressed: _isLoading ? null : () => _toggleListening(),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return _chatPanelOpen ? _buildChatMode() : _buildHudDashboard();
  }

}
class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onSendToStudio;

  const _ChatBubble({
    required this.message,
    this.onSendToStudio,
  });

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
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.90,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(message.isUser ? 18 : 5),
            bottomRight: Radius.circular(message.isUser ? 5 : 18),
          ),
          border: Border.all(color: borderColor.withOpacity(0.58)),
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
                      fontSize: 11,
                    ),
                  ),
                ),
                if (onSendToStudio != null) ...[
                  Tooltip(
                    message: 'В Рап студио',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onSendToStudio,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.mic_external_on_rounded,
                          size: 16,
                          color: ironGreen,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                ],
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
            const SizedBox(height: 4),
            SelectableText(
              cleanMarkdownForDisplay(message.text),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.34,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
