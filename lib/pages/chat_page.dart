import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../services/ai_provider_config.dart';
import '../services/automation_service.dart';
import '../services/gemini_service.dart';
import '../services/hey_iron_controller.dart';
import '../services/iron_voice_flags.dart';
import '../services/iron_tts.dart';
import '../services/local_store.dart';
import '../widgets/voice_settings_panel.dart';
import '../ui/common_widgets.dart';

class ChatPage extends StatefulWidget {
  final LocalStore store;
  final bool isActive;
  final HeyIronController? heyIron;
  final VoidCallback? onOpenTools;
  final VoidCallback? onOpenSettings;
  final Future<void> Function(String text)? onSendToStudio;

  const ChatPage({
    super.key,
    required this.store,
    this.isActive = true,
    this.heyIron,
    this.onOpenTools,
    this.onOpenSettings,
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
  final FocusNode _composerFocus = FocusNode();
  late final TextEditingController _apiKeyController;
  late final TextEditingController _backupApiKeyController;
  late final TextEditingController _backupBaseUrlController;
  late final TextEditingController _backupModelController;
  final ScrollController _scrollController = ScrollController();
  final IronTts _tts = IronTts.instance;
  final GeminiService _gemini = GeminiService();
  final AutomationService _automation = AutomationService();
  late final AnimationController _coreController;

  late List<ChatMessage> _messages;
  bool _isLoading = false;
  DateTime? _handledWakeAt;
  bool _isListening = false;
  bool _ironActive = false;
  bool _voiceToggleBusy = false;
  bool _processingPendingChatPrompt = false;
  bool _voiceReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composerFocus.addListener(() {
      if (mounted) setState(() {});
    });
    widget.store.addListener(_handleStoreChange);
    _coreController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _syncCoreAnimation();
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

    _prepareVoice();
    _automation.setNativeSpeechPartialListener((recognized) {
      if (!mounted || !_isListening) return;
      setState(() {
        _messageController.text = recognized;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
      });
    });
    widget.heyIron?.onWakeWord = () {
      if (!mounted) return;
      if (_currentListeningLocked()) return;
      _toggleListening();
    };
    widget.heyIron?.addListener(_onHeyIronChanged);
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
    _tts.stop();
    _automation.setNativeSpeechPartialListener(null);
    _automation.cancelNativeSpeechRecognition();
    _gemini.dispose();
    _composerFocus.dispose();
    _messageController.dispose();
    _apiKeyController.dispose();
    _backupApiKeyController.dispose();
    _backupBaseUrlController.dispose();
    _backupModelController.dispose();
    widget.heyIron?.removeListener(_onHeyIronChanged);
    if (widget.heyIron?.onWakeWord != null) {
      widget.heyIron!.onWakeWord = null;
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onHeyIronChanged() {
    final wake = widget.heyIron?.lastWakeAt;
    if (wake != null && wake != _handledWakeAt && !_currentListeningLocked()) {
      _handledWakeAt = wake;
      _toggleListening();
    }
    if (mounted) setState(() {});
  }

  bool _currentListeningLocked() => _isListening || _isLoading;

  @override
  void didUpdateWidget(ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _syncCoreAnimation();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadIronStatus();
      _consumePendingChatVoiceRequest();
      _syncCoreAnimation();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _coreController.stop();
    }
  }

  void _syncCoreAnimation() {
    final active = widget.isActive &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed);
    final shouldAnimate = active && (_isListening || _isLoading);
    if (shouldAnimate) {
      if (!_coreController.isAnimating) {
        _coreController.repeat(reverse: true);
      }
    } else if (_coreController.isAnimating) {
      _coreController
        ..stop()
        ..value = 0;
    }
  }

  void _handleStoreChange() {
    if (mounted) setState(() {});
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
    if (!ironVoiceServiceEnabled) {
      if (mounted) setState(() => _ironActive = false);
      return;
    }
    final active = await _automation.isIronVoiceActive();
    if (!mounted) return;
    setState(() => _ironActive = active);
  }

  Future<void> _toggleIronMode() async {
    if (!ironVoiceServiceEnabled) {
      setState(() => _ironActive = false);
      _showMessage(ironVoiceDisabledMessage);
      return;
    }
    if (_voiceToggleBusy) return;
    setState(() => _voiceToggleBusy = true);
    final turningOn = !_ironActive;
    final result = await _automation.execute(
      turningOn ? 'iron_voice_on' : 'iron_voice_off',
    );
    if (!mounted) return;
    setState(() {
      _voiceToggleBusy = false;
      if (result.success) {
        _ironActive = turningOn;
      } else if (turningOn) {
        _ironActive = false;
      }
    });
    if (!result.success && turningOn) {
      final message = result.message.trim().isEmpty
          ? '„Hey Iron“ е временно изключен'
          : result.message.trim();
      _showMessage(message);
      return;
    }
    _showMessage(result.message);
  }

  Future<void> _prepareVoice() async {
    try {
      final voices = await _tts.listVoices(widget.store);
      await _tts.resolveSelection(widget.store, voices);
      if (mounted) setState(() => _voiceReady = true);
    } catch (_) {
      if (mounted) setState(() => _voiceReady = false);
    }
  }

  Future<void> _openVoiceSettings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Настройки на гласа'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: VoiceSettingsPanel(store: widget.store),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
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
    final resumeIronVoice = await _automation.pauseIronVoiceCapture();
    try {
      if (resumeIronVoice) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
      await _tts.stop();
      final notice = await _tts.speak(text, widget.store);
      if (notice != null && mounted) {
        _showMessage(notice);
      }
    } catch (_) {
      try {
        await _tts.stop();
      } catch (_) {
        // The wake listener still has to be restored below.
      }
    } finally {
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
      await _tts.stop();
    }
  }

  Future<void> _toggleListening() async {
    if (_isLoading) return;

    if (_isListening) {
      await _automation.stopNativeSpeechRecognition();
      return;
    }

    await _tts.stop();
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;
    await widget.heyIron?.stopListening(clean: false);
    if (!mounted) return;

    setState(() => _isListening = true);
    _syncCoreAnimation();
    final result = await _automation.startNativeSpeechRecognition();
    if (!mounted) return;

    setState(() => _isListening = false);
    _syncCoreAnimation();
    if (widget.heyIron?.enabled == true) {
      await widget.heyIron!.startListening();
    }
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
      if (!message.isUser &&
          !message.isLocalNotice &&
          message.text.trim().isNotEmpty) {
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
    _syncCoreAnimation();
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
        _syncCoreAnimation();
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
              color:
                  active ? ironGreen.withValues(alpha: 0.14) : ironSurfaceHigh,
              border: Border.all(
                width: 1,
                color: active ? ironOutlineStrong : ironOutlineMuted,
              ),
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

  Widget _buildStatusHeader() {
    final hey = widget.heyIron;
    final status = _isListening
        ? 'Слушам…'
        : _isLoading
            ? 'Iron мисли…'
            : hey != null && hey.enabled
                ? hey.statusLabel
                : ironVoiceServiceEnabled && _ironActive
                    ? 'Хей Айрън е активен'
                    : 'Готов за разговор';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 6, 4),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _coreController,
            builder: (context, _) {
              final pulse = _isListening || _isLoading
                  ? 0.85 + (_coreController.value * 0.15)
                  : 1.0;
              return Transform.scale(
                scale: pulse,
                child: CannabisCore(
                    progress: _isListening || _isLoading ? 0.6 : 0.15,
                    size: 42),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Хей Айрън',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ironGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _roundAction(
            icon: (widget.heyIron?.enabled ?? _ironActive)
                ? Icons.hearing_rounded
                : Icons.hearing_disabled_rounded,
            tooltip: widget.heyIron != null
                ? (widget.heyIron!.enabled
                    ? 'Изключи „Хей Айрън“'
                    : 'Включи „Хей Айрън“')
                : !ironVoiceServiceEnabled
                    ? '„Hey Iron“ е временно изключен'
                    : _ironActive
                        ? 'Изключи „Хей Айрън“'
                        : 'Включи „Хей Айрън“',
            active: widget.heyIron?.enabled ?? _ironActive,
            onPressed: widget.heyIron != null
                ? () {
                    final hey = widget.heyIron!;
                    if (hey.phase == HeyIronPhase.downloading) return;
                    hey.setEnabled(!hey.enabled);
                  }
                : (!ironVoiceServiceEnabled || !_voiceToggleBusy)
                    ? _toggleIronMode
                    : null,
          ),
          const SizedBox(width: 6),
          _roundAction(
            icon: widget.store.voiceRepliesEnabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            tooltip: widget.store.voiceRepliesEnabled
                ? (_voiceReady
                    ? 'Гласовите отговори са включени'
                    : 'Системен глас')
                : 'Гласовите отговори са изключени',
            active: widget.store.voiceRepliesEnabled,
            onPressed: _toggleVoiceReplies,
          ),
          const SizedBox(width: 6),
          _roundAction(
            icon: Icons.key_rounded,
            tooltip: 'AI доставчици',
            active: widget.store.hasAnyAiProvider,
            onPressed: _openApiKeySheet,
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
              } else if (value == 'settings') {
                (widget.onOpenSettings ?? widget.onOpenTools)?.call();
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
              if (widget.onOpenSettings != null || widget.onOpenTools != null)
                const PopupMenuItem(
                  value: 'settings',
                  child: Text('Настройки и инструменти'),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return IronBackground(
      child: Column(
        children: [
          _buildStatusHeader(),
          if (widget.store.shouldPromptForApiKey)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: IronCard(
                bright: true,
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Добави AI ключ, за да започнеш',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Постави безплатен Gemini или Groq ключ. Пази се само на този телефон, криптиран.',
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: IronButton(
                            text: 'Добави ключ',
                            icon: Icons.key_rounded,
                            onPressed: _openApiKeySheet,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () async {
                            await widget.store.dismissApiKeyPrompt();
                            if (mounted) setState(() {});
                          },
                          child: const Text('По-късно'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isLoading && index == _messages.length) {
                  return const _ThinkingIndicator();
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ironSurfaceHigh,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  width: 1,
                  color:
                      _composerFocus.hasFocus ? ironOutlineStrong : ironOutline,
                ),
                boxShadow: ironFocusGlow(_composerFocus.hasFocus),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        focusNode: _composerFocus,
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        style:
                            const TextStyle(color: Colors.white, height: 1.35),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          hintText: _isListening
                              ? 'Слушам на български...'
                              : 'Напиши или говори с Iron...',
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
                        _isListening
                            ? Icons.stop_circle_rounded
                            : Icons.mic_rounded,
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
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingIndicator extends StatefulWidget {
  const _ThinkingIndicator();

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Row(
                  children: List.generate(3, (index) {
                    final t = (_controller.value + (index * 0.2)) % 1.0;
                    final dy = -3 * (t < 0.5 ? t * 2 : (1 - t) * 2);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Transform.translate(
                        offset: Offset(0, dy),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: ironGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(width: 10),
            const Text(
              'Iron мисли…',
              style: TextStyle(
                color: ironGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
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
    final Color fill;
    final Color outline;
    if (message.isUser) {
      fill = ironUserFill;
      outline = ironOutlineStrong;
    } else if (message.isLocalNotice) {
      fill = ironGraphite;
      outline = ironOutline;
    } else {
      fill = ironGraphite;
      outline = const Color(0x6600FF66);
    }
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(message.isUser ? 18 : 6),
      bottomRight: Radius.circular(message.isUser ? 6 : 18),
    );

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: radius,
          border: Border.all(color: outline, width: 1),
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
                      color: message.isUser ? ironGreen : Colors.white54,
                      fontWeight: FontWeight.w600,
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
              style: const TextStyle(color: Colors.white, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
