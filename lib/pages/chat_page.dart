import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/chat_message.dart';
import '../services/automation_service.dart';
import '../services/gemini_service.dart';
import '../services/local_store.dart';
import '../ui/common_widgets.dart';

class ChatPage extends StatefulWidget {
  final LocalStore store;

  const ChatPage({super.key, required this.store});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin {
  static const _welcomeText =
      'Аз съм Iron. Говори ми естествено на български — помня разговора и мога да продължавам по контекста.';

  final TextEditingController _messageController = TextEditingController();
  late final TextEditingController _apiKeyController;
  final ScrollController _scrollController = ScrollController();
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final GeminiService _gemini = GeminiService();
  final AutomationService _automation = AutomationService();
  late final AnimationController _coreController;

  late List<ChatMessage> _messages;
  bool _isLoading = false;
  bool _showApiBox = false;
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _voiceReady = false;
  bool _speechSendTriggered = false;
  bool _conversationMode = false;
  bool _ironActive = false;
  bool _ironBusy = false;
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
    _showApiBox = !widget.store.hasApiKey;
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
    _loadIronStatus();
  }

  @override
  void dispose() {
    _coreController.dispose();
    _flutterTts.stop();
    _speechToText.stop();
    _gemini.dispose();
    _messageController.dispose();
    _apiKeyController.dispose();
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
          if (!mounted) return;
          setState(() => _isListening = false);
          _showMessage('Проблем с микрофона: ${error.errorMsg}');
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

  Future<void> _loadIronStatus() async {
    final active = await _automation.isIronVoiceActive();
    if (!mounted) return;
    setState(() => _ironActive = active);
  }

  Future<void> _toggleIron() async {
    if (_ironBusy) return;
    setState(() => _ironBusy = true);
    final result = await _automation.execute(
      _ironActive ? 'iron_voice_off' : 'iron_voice_on',
    );
    if (!mounted) return;
    setState(() {
      _ironBusy = false;
      if (result.success) _ironActive = !_ironActive;
    });
    _showMessage(result.message);
  }

  Future<void> _toggleConversationMode() async {
    final enabled = !_conversationMode;
    setState(() => _conversationMode = enabled);

    if (!enabled) {
      await _speechToText.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    if (!_isLoading && !_speechToText.isListening) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (mounted && _conversationMode) await _toggleListening();
    }
  }

  void _scheduleConversationListening() {
    if (!_conversationMode) return;
    Future<void>.delayed(const Duration(milliseconds: 650)).then((_) async {
      if (!mounted || !_conversationMode || _isLoading) return;
      if (_speechToText.isListening || _isListening) return;
      await _toggleListening();
    });
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

  Future<void> _toggleListening() async {
    if (_speechToText.isListening) {
      await _speechToText.stop();
      if (mounted) setState(() => _isListening = false);
      await _sendRecognizedSpeech();
      return;
    }

    await _flutterTts.stop();

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

    _speechSendTriggered = false;
    setState(() => _isListening = true);

    try {
      await _speechToText.listen(
        localeId: _bulgarianLocale,
        listenFor: const Duration(seconds: 90),
        pauseFor: const Duration(seconds: 7),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
        onResult: (result) {
          if (!mounted) return;
          final recognized = result.recognizedWords.trim();
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
      _showMessage('Микрофонът не можа да стартира.');
    }
  }

  Future<void> _saveApiKey() async {
    final value = _apiKeyController.text.trim();
    if (value.isEmpty) {
      _showMessage('Постави Gemini API ключ.');
      return;
    }

    await widget.store.setApiKey(value);
    await _automation.syncGeminiApiKey(value);
    _gemini.resetModel();
    if (!mounted) return;
    setState(() => _showApiBox = false);
    _showMessage('API ключът е запазен локално на телефона.');
  }

  Future<void> _clearApiKey() async {
    _apiKeyController.clear();
    await widget.store.setApiKey('');
    await _automation.syncGeminiApiKey('');
    _gemini.resetModel();
    if (!mounted) return;
    setState(() => _showApiBox = true);
    _showMessage('API ключът е премахнат.');
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;

    await _speechToText.stop();

    final typedKey = _apiKeyController.text.trim();
    if (typedKey.isNotEmpty && typedKey != widget.store.apiKey) {
      await widget.store.setApiKey(typedKey);
      await _automation.syncGeminiApiKey(typedKey);
      _gemini.resetModel();
    }

    final apiKey = widget.store.apiKey.trim();
    if (apiKey.isEmpty) {
      setState(() => _showApiBox = true);
      _showMessage('Първо постави и запази Gemini API ключа.');
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
        _scheduleConversationListening();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Widget _buildApiSection() {
    if (!_showApiBox) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: IronButton(
                text: 'API ключът е запазен',
                icon: Icons.lock,
                secondary: true,
                onPressed: () => setState(() => _showApiBox = true),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: IronCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gemini API ключ',
              style: TextStyle(
                color: ironGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Ключът се пази само в локалните настройки на приложението.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 10),
            IronInput(
              controller: _apiKeyController,
              label: 'API ключ',
              hint: 'AIza...',
              obscureText: true,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: IronButton(
                    text: 'Запази',
                    icon: Icons.save,
                    onPressed: _saveApiKey,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: IronButton(
                    text: 'Премахни',
                    icon: Icons.delete_outline,
                    secondary: true,
                    onPressed: _clearApiKey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _coreStatus {
    if (_isListening) return 'СЛУШАМ';
    if (_isLoading) return 'МИСЛЯ';
    if (_conversationMode) return 'РАЗГОВОРЪТ Е АКТИВЕН';
    return 'ГОТОВ СЪМ';
  }

  Widget _coreControl({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? ironGreen.withOpacity(0.16)
                : Colors.black.withOpacity(0.28),
            border: Border.all(
              color: ironGreen.withOpacity(active ? 0.72 : 0.24),
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: ironGreen.withOpacity(0.18),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            color: active ? ironGreen : Colors.white54,
            size: 21,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showLargeCore = _messages.length <= 2;

    return IronBackground(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 10, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'IRON MUSIC 420 AI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Личен AI асистент',
                        style: TextStyle(
                          color: ironGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Настройки',
                  icon: const Icon(Icons.more_horiz, color: ironGreen),
                  onSelected: (value) {
                    if (value == 'api') {
                      setState(() => _showApiBox = !_showApiBox);
                    } else if (value == 'history') {
                      _clearHistory();
                    } else if (value == 'voice') {
                      _openVoiceSettings();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'api', child: Text('API ключ')),
                    PopupMenuItem(
                      value: 'voice',
                      child: Text('Настройки на гласа'),
                    ),
                    PopupMenuItem(
                      value: 'history',
                      child: Text('Изчисти историята'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOut,
            height: showLargeCore ? 246 : 174,
            child: AnimatedBuilder(
              animation: _coreController,
              builder: (context, _) {
                final activityBoost = (_isListening || _isLoading) ? 0.22 : 0.0;
                final progress =
                    (_coreController.value * 0.72 + activityBoost).clamp(0.0, 1.0);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _isLoading ? null : _toggleListening,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 220),
                        scale: _isListening ? 1.08 : 1.0,
                        child: CannabisCore(
                          progress: progress,
                          size: showLargeCore ? 184 : 126,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _coreStatus,
                      style: TextStyle(
                        color: _isListening ? ironGreenSoft : ironGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        shadows: const [
                          Shadow(color: ironGreen, blurRadius: 10),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _coreControl(
                          icon: _conversationMode
                              ? Icons.forum
                              : Icons.forum_outlined,
                          tooltip: 'Продължаващ разговор',
                          active: _conversationMode,
                          onPressed: _toggleConversationMode,
                        ),
                        const SizedBox(width: 12),
                        _coreControl(
                          icon: _ironActive
                              ? Icons.hearing
                              : Icons.hearing_disabled,
                          tooltip: 'Hey Iron',
                          active: _ironActive,
                          onPressed: _ironBusy ? null : _toggleIron,
                        ),
                        const SizedBox(width: 12),
                        _coreControl(
                          icon: widget.store.voiceRepliesEnabled
                              ? Icons.volume_up
                              : Icons.volume_off,
                          tooltip: 'Гласови отговори',
                          active: widget.store.voiceRepliesEnabled,
                          onPressed: _toggleVoiceReplies,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          _buildApiSection(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isLoading && index == _messages.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(left: 6, bottom: 12),
                      child: Text(
                        'Iron мисли...',
                        style: TextStyle(
                          color: ironGreen,
                          fontWeight: FontWeight.w700,
                        ),
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
            padding: const EdgeInsets.fromLTRB(10, 7, 7, 7),
            decoration: BoxDecoration(
              color: const Color(0xFF010A05).withOpacity(0.98),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: ironGreen.withOpacity(0.30)),
              boxShadow: [
                BoxShadow(
                  color: ironGreen.withOpacity(0.08),
                  blurRadius: 20,
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
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration.collapsed(
                      hintText: _isListening
                          ? 'Слушам... кажи всичко спокойно'
                          : 'Говори или напиши на Iron...',
                      hintStyle: const TextStyle(color: Colors.white38),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  tooltip: 'Микрофон',
                  onPressed: _isLoading ? null : _toggleListening,
                  icon: Icon(
                    _isListening ? Icons.stop_circle : Icons.mic_rounded,
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
        constraints: const BoxConstraints(maxWidth: 340),
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
