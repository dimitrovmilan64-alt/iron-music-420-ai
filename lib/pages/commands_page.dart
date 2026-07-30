import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/automation_models.dart';
import '../services/automation_service.dart';
import '../services/local_store.dart';
import '../ui/common_widgets.dart';

class CommandsPage extends StatefulWidget {
  final LocalStore store;
  final ValueChanged<int> onOpenSection;

  const CommandsPage({
    super.key,
    required this.store,
    required this.onOpenSection,
  });

  @override
  State<CommandsPage> createState() => _CommandsPageState();
}

class _CommandsPageState extends State<CommandsPage>
    with WidgetsBindingObserver {
  final AutomationService _automation = AutomationService();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _commandController = TextEditingController();
  bool _isListening = false;
  bool _isRunning = false;
  bool _ironActive = false;
  bool _ironBusy = false;
  bool _voiceResultHandled = false;
  bool _flashlightOn = false;

  static const _quickActions = <_AutomationItem>[
    _AutomationItem('youtube', 'YouTube', 'Отвори YouTube', Icons.play_circle),
    _AutomationItem('camera', 'Камера', 'Отвори камерата', Icons.camera_alt),
    _AutomationItem('maps', 'Карти', 'Отвори картите', Icons.map),
    _AutomationItem(
      'flash_toggle',
      'Фенер',
      'Включи или изключи',
      Icons.flashlight_on,
    ),
    _AutomationItem('volume_up', 'Звук +', 'Увеличи звука', Icons.volume_up),
    _AutomationItem('volume_down', 'Звук −', 'Намали звука', Icons.volume_down),
    _AutomationItem(
      'settings',
      'Настройки',
      'Отвори настройките',
      Icons.settings,
    ),
    _AutomationItem('alarms', 'Аларми', 'Отвори алармите', Icons.alarm),
    _AutomationItem(
      'calendar',
      'Календар',
      'Отвори календара',
      Icons.calendar_month,
    ),
    _AutomationItem('dialer', 'Телефон', 'Отвори телефона', Icons.phone),
    _AutomationItem(
      'bluetooth',
      'Bluetooth',
      'Bluetooth настройки',
      Icons.bluetooth,
    ),
    _AutomationItem('wifi', 'Wi‑Fi', 'Wi‑Fi настройки', Icons.wifi),
    _AutomationItem('chrome', 'Chrome', 'Отвори браузъра', Icons.language),
  ];

  static const _routines = <_AutomationItem>[
    _AutomationItem(
      'music_mode',
      'Музика',
      'Пуска музикалния режим чрез Automate',
      Icons.headphones,
    ),
    _AutomationItem(
      'studio_mode',
      'Студио',
      'Подготвя телефона за запис',
      Icons.mic_external_on,
    ),
    _AutomationItem(
      'night_mode',
      'Нощ',
      'Намалява звука',
      Icons.nightlight_round,
    ),
  ];

  static const _customActionCatalog = <_AutomationItem>[
    _AutomationItem('app_home', 'Начало', 'Отвори началния екран', Icons.home),
    _AutomationItem(
      'app_studio',
      'Rap Studio',
      'Отвори Studio',
      Icons.mic_external_on,
    ),
    _AutomationItem(
      'app_songs',
      'Моите песни',
      'Отвори библиотеката',
      Icons.library_music,
    ),
    _AutomationItem('app_chat', 'AI чат', 'Отвори чата', Icons.chat_bubble),
    _AutomationItem('youtube', 'YouTube', 'Отвори YouTube', Icons.play_circle),
    _AutomationItem('chrome', 'Chrome', 'Отвори браузъра', Icons.language),
    _AutomationItem('camera', 'Камера', 'Отвори камерата', Icons.camera_alt),
    _AutomationItem('maps', 'Карти', 'Отвори Google Maps', Icons.map),
    _AutomationItem(
      'flash_toggle',
      'Фенер',
      'Включи или изключи',
      Icons.flashlight_on,
    ),
    _AutomationItem('volume_up', 'Звук +', 'Увеличи звука', Icons.volume_up),
    _AutomationItem('volume_down', 'Звук −', 'Намали звука', Icons.volume_down),
    _AutomationItem(
      'keep_awake_on',
      'Екран буден',
      'Не изгасвай екрана',
      Icons.light_mode,
    ),
    _AutomationItem(
      'keep_awake_off',
      'Екран нормално',
      'Разреши изгасване',
      Icons.bedtime,
    ),
    _AutomationItem(
      'bluetooth',
      'Bluetooth',
      'Отвори Bluetooth',
      Icons.bluetooth,
    ),
    _AutomationItem('wifi', 'Wi‑Fi', 'Отвори Wi‑Fi', Icons.wifi),
    _AutomationItem('dialer', 'Телефон', 'Отвори набиране', Icons.phone),
    _AutomationItem('alarms', 'Аларми', 'Отвори алармите', Icons.alarm),
    _AutomationItem(
      'calendar',
      'Календар',
      'Отвори календара',
      Icons.calendar_month,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(_storeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIronStatus());
  }

  void _storeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadIronStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_storeChanged);
    _commandController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _loadIronStatus() async {
    final active = await _automation.isIronVoiceActive();
    if (mounted && active != _ironActive) {
      setState(() => _ironActive = active);
    }
  }

  Future<void> _toggleIron() async {
    if (_ironBusy) return;
    if (_isListening) {
      await _speech.stop();
    }
    setState(() {
      _ironBusy = true;
      _isListening = false;
    });
    final result = await _automation.execute(
      _ironActive ? 'iron_voice_off' : 'iron_voice_on',
    );
    if (!mounted) return;
    setState(() {
      _ironBusy = false;
      if (result.success) {
        _ironActive = !_ironActive;
      }
    });
    _showResult(result);
  }

  Future<AutomationResult> _executeActionInternal(
    String action, {
    Map<String, dynamic> arguments = const <String, dynamic>{},
  }) async {
    switch (action) {
      case 'app_home':
        widget.onOpenSection(0);
        return const AutomationResult(true, 'Отворен е началният екран.');
      case 'app_studio':
        widget.onOpenSection(1);
        return const AutomationResult(true, 'Rap Studio е отворено.');
      case 'app_songs':
        widget.onOpenSection(2);
        return const AutomationResult(true, 'Библиотеката е отворена.');
      case 'app_chat':
        widget.onOpenSection(3);
        return const AutomationResult(true, 'AI чатът е отворен.');
      default:
        final result = await _automation.execute(action, arguments: arguments);
        if (result.success && action == 'studio_mode') {
          widget.onOpenSection(1);
        }
        return result;
    }
  }

  Future<void> _run(
    String action, {
    String? title,
    Map<String, dynamic> arguments = const <String, dynamic>{},
  }) async {
    if (_isRunning) return;
    setState(() => _isRunning = true);
    final executedAction = action == 'flash_toggle'
        ? (_flashlightOn ? 'flash_off' : 'flash_on')
        : action;
    final result = await _executeActionInternal(
      executedAction,
      arguments: arguments,
    );
    if (result.success && executedAction == 'flash_on') {
      _flashlightOn = true;
    } else if (result.success && executedAction == 'flash_off') {
      _flashlightOn = false;
    }
    await _recordHistory(title ?? _titleForAction(action), result);
    if (!mounted) return;
    setState(() => _isRunning = false);
    _showResult(result);
  }

  Future<void> _runCustom(CustomAutomation automation) async {
    if (_isRunning) return;
    setState(() => _isRunning = true);

    var success = true;
    final messages = <String>[];
    for (final action in automation.actions) {
      final result = await _executeActionInternal(action);
      success = success && result.success;
      messages.add(result.message);
      if (!result.success) break;
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }

    final finalResult = AutomationResult(
      success,
      success
          ? '„${automation.name}“ е изпълнена.'
          : '„${automation.name}“ спря: ${messages.last}',
    );
    await _recordHistory(automation.name, finalResult);
    if (!mounted) return;
    setState(() => _isRunning = false);
    _showResult(finalResult);
  }

  Future<void> _recordHistory(String title, AutomationResult result) async {
    final now = DateTime.now();
    await widget.store.addAutomationHistory(
      AutomationHistoryEntry(
        id: now.microsecondsSinceEpoch.toString(),
        title: title,
        success: result.success,
        message: result.message,
        executedAt: now,
      ),
    );
  }

  void _showResult(AutomationResult result) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.success ? ironPanelRaised : const Color(0xFF5A1B14),
      ),
    );
  }

  Future<void> _toggleVoiceCommand() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      await _finishVoiceCommand();
      return;
    }

    _voiceResultHandled = false;
    final available = await _speech.initialize(
      onStatus: (status) async {
        if ((status == 'done' || status == 'notListening') && _isListening) {
          if (mounted) setState(() => _isListening = false);
          await _finishVoiceCommand();
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (!available || !mounted) return;

    setState(() => _isListening = true);
    await _speech.listen(
      localeId: 'bg_BG',
      partialResults: true,
      listenMode: stt.ListenMode.confirmation,
      onResult: (result) {
        _commandController.text = result.recognizedWords;
        _commandController.selection = TextSelection.collapsed(
          offset: _commandController.text.length,
        );
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _finishVoiceCommand() async {
    if (_voiceResultHandled) return;
    _voiceResultHandled = true;
    await _executeSpokenCommand(_commandController.text);
  }

  Future<void> _executeSpokenCommand(String raw) async {
    final text = _normalize(raw);
    if (text.isEmpty) return;

    for (final custom in widget.store.customAutomations) {
      final phrase = _normalize(custom.voicePhrase);
      final name = _normalize(custom.name);
      if ((phrase.isNotEmpty && text.contains(phrase)) ||
          (name.isNotEmpty && text.contains(name))) {
        await _runCustom(custom);
        return;
      }
    }

    if (text.startsWith('automate ') ||
        text.startsWith('аутомейт ') ||
        text.startsWith('макро ') ||
        text.startsWith('макродроид ')) {
      final command = text
          .replaceFirst(RegExp(r'^(automate|аутомейт|макро(дроид)?)\s+'), '')
          .trim();
      if (command.isNotEmpty) {
        await _run(
          'macrodroid_broadcast',
          title: 'Automate: $command',
          arguments: {'command': command},
        );
        return;
      }
    }

    String? action;
    if (text.contains('youtube') || text.contains('ютуб')) {
      action = 'youtube';
    } else if (text.contains('камера')) {
      action = 'camera';
    } else if (text.contains('карти') || text.contains('maps')) {
      action = 'maps';
    } else if (text.contains('фенер') &&
        (text.contains('спри') || text.contains('изключи'))) {
      action = 'flash_off';
    } else if (text.contains('фенер')) {
      action = 'flash_on';
    } else if (text.contains('увеличи') && text.contains('звук')) {
      action = 'volume_up';
    } else if (text.contains('намали') && text.contains('звук')) {
      action = 'volume_down';
    } else if (text.contains('bluetooth') || text.contains('блутут')) {
      action = 'bluetooth';
    } else if (text.contains('wi-fi') ||
        text.contains('wifi') ||
        text.contains('уай фай')) {
      action = 'wifi';
    } else if (text.contains('music mode') ||
        text.contains('музикален режим')) {
      action = 'music_mode';
    } else if (text.contains('studio mode') || text.contains('студио режим')) {
      action = 'studio_mode';
    } else if (text.contains('night mode') || text.contains('нощен режим')) {
      action = 'night_mode';
    } else if (text.contains('аларм')) {
      action = 'alarms';
    } else if (text.contains('календар')) {
      action = 'calendar';
    } else if (text.contains('телефон') || text.contains('набиране')) {
      action = 'dialer';
    } else if (text.contains('отвори студио') || text.contains('rap studio')) {
      action = 'app_studio';
    } else if (text.contains('отвори чат')) {
      action = 'app_chat';
    } else if (text.contains('отвори песни') || text.contains('библиотека')) {
      action = 'app_songs';
    } else if (text.contains('начален екран') || text == 'начало') {
      action = 'app_home';
    } else if (text.contains('настройки')) {
      action = 'settings';
    } else if (text.contains('chrome') || text.contains('браузър')) {
      action = 'chrome';
    }

    if (action == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не разпознах командата. Добави я като лична автоматизация.',
          ),
        ),
      );
      return;
    }
    await _run(action);
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-zа-я0-9+\- ]', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _titleForAction(String action) {
    for (final item in [
      ..._routines,
      ..._quickActions,
      ..._customActionCatalog,
    ]) {
      if (item.action == action) return item.title;
    }
    if (action == 'flash_on' || action == 'flash_off') return 'Фенер';
    if (action == 'macrodroid_broadcast') return 'Automate команда';
    return 'Автоматизация';
  }

  Future<void> _openCustomAutomationEditor([CustomAutomation? existing]) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final phraseController = TextEditingController(
      text: existing?.voicePhrase ?? '',
    );
    final selected = <String>[...?existing?.actions];

    final saved = await showModalBottomSheet<CustomAutomation>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF031108),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          existing == null
                              ? 'Нова лична команда'
                              : 'Редактирай командата',
                          style: const TextStyle(
                            color: ironGreen,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Име',
                      hintText: 'Например: Започвам запис',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phraseController,
                    decoration: const InputDecoration(
                      labelText: 'Гласова фраза',
                      hintText: 'Например: Стартирай запис',
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Избери действията по ред',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (selected.isNotEmpty)
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (var index = 0; index < selected.length; index++)
                          InputChip(
                            label: Text(
                              '${index + 1}. ${_titleForAction(selected[index])}',
                            ),
                            onDeleted: () {
                              setSheetState(() => selected.removeAt(index));
                            },
                          ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  ..._customActionCatalog.map((item) {
                    final chosen = selected.contains(item.action);
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: chosen,
                      activeColor: ironGreen,
                      title: Text(item.title),
                      subtitle: Text(
                        item.subtitle,
                        style: const TextStyle(color: Colors.white54),
                      ),
                      secondary: Icon(item.icon, color: ironGreen),
                      onChanged: (value) {
                        setSheetState(() {
                          if (value == true) {
                            if (selected.length < 6) selected.add(item.action);
                          } else {
                            selected.remove(item.action);
                          }
                        });
                      },
                    );
                  }),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        final name = nameController.text.trim();
                        final phrase = phraseController.text.trim();
                        if (name.isEmpty ||
                            phrase.isEmpty ||
                            selected.isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Попълни име, гласова фраза и поне едно действие.',
                              ),
                            ),
                          );
                          return;
                        }
                        final now = DateTime.now();
                        Navigator.pop(
                          sheetContext,
                          CustomAutomation(
                            id: existing?.id ??
                                'custom_${now.microsecondsSinceEpoch}',
                            name: name,
                            voicePhrase: phrase,
                            actions: List<String>.from(selected),
                            createdAt: existing?.createdAt ?? now,
                            updatedAt: now,
                          ),
                        );
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('ЗАПАЗИ ЛИЧНАТА КОМАНДА'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    nameController.dispose();
    phraseController.dispose();
    if (saved != null) {
      await widget.store.upsertCustomAutomation(saved);
    }
  }

  Future<void> _confirmDeleteCustom(CustomAutomation automation) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Изтриване'),
        content: Text('Да изтрия ли „${automation.name}“?'),
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
    if (shouldDelete == true) {
      await widget.store.deleteCustomAutomation(automation.id);
    }
  }

  Future<void> _openAutomateSheet() async {
    final commandController = TextEditingController(text: 'music_mode_420');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF031108),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Връзка с Automate',
                style: TextStyle(
                  color: ironGreen,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '1. В блока „Broadcast receive“ включи fx за Action и постави:',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 12),
              _CodeBox(
                text: '"com.ironmusic420ai.MACRODROID_COMMAND"',
                onCopy: () => Clipboard.setData(
                  const ClipboardData(
                    text: '"com.ironmusic420ai.MACRODROID_COMMAND"',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '2. В „Broadcast extras“ напиши: extras\n'
                '3. След блока добави „Expression true“:',
                style: TextStyle(color: Colors.white60, height: 1.4),
              ),
              const SizedBox(height: 8),
              _CodeBox(
                text: 'extras["command"] = "music_mode_420"',
                onCopy: () => Clipboard.setData(
                  const ClipboardData(
                    text: 'extras["command"] = "music_mode_420"',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: commandController,
                decoration: const InputDecoration(
                  labelText: 'Тестова команда',
                  hintText: 'Например: music_mode_420',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _run('open_automate'),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Отвори Automate'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        final command = commandController.text.trim();
                        if (command.isEmpty) return;
                        Navigator.pop(context);
                        _run(
                          'macrodroid_broadcast',
                          title: 'Automate: $command',
                          arguments: {'command': command},
                        );
                      },
                      icon: const Icon(Icons.send),
                      label: const Text('Тест'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    commandController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final favoriteIds = widget.store.favoriteAutomationIds;
    final mainActions = _quickActions.take(6).toList(growable: false);
    final moreActions = _quickActions.skip(6).toList(growable: false);

    return IronBackground(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: [
          const PageTitle(
            eyebrow: 'IRON',
            title: 'Команди',
            subtitle: 'Кажи команда или натисни бутон',
          ),
          const SizedBox(height: 14),
          IronCard(
            bright: true,
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ironGreen.withOpacity(0.12),
                        border: Border.all(
                          color: ironGreen.withOpacity(
                            _ironActive ? 0.72 : 0.28,
                          ),
                        ),
                      ),
                      child: Icon(
                        _ironActive ? Icons.graphic_eq : Icons.hearing,
                        color: ironGreen,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _ironActive ? 'Iron е активен' : 'Хей, Iron',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _ironActive
                                ? 'Кажи „Хей, Iron“ — отговаря „Слушам“'
                                : 'Фонов гласов режим',
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: _ironActive
                      ? OutlinedButton.icon(
                          onPressed: _ironBusy ? null : _toggleIron,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Спри Iron'),
                        )
                      : FilledButton.icon(
                          onPressed: _ironBusy ? null : _toggleIron,
                          icon: _ironBusy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.power_settings_new),
                          label: const Text('Активирай Iron'),
                        ),
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                if (!_ironActive) ...[
                  Row(
                    children: [
                      Material(
                        color: _isListening
                            ? Colors.redAccent.withOpacity(0.16)
                            : ironGreen.withOpacity(0.12),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _isRunning ? null : _toggleVoiceCommand,
                          child: SizedBox.square(
                            dimension: 58,
                            child: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              color:
                                  _isListening ? Colors.redAccent : ironGreen,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isListening ? 'Слушам…' : 'Натисни и говори',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Например: „Пусни музика“',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: _commandController,
                  onSubmitted: _executeSpokenCommand,
                  decoration: InputDecoration(
                    hintText: 'Или напиши команда',
                    suffixIcon: IconButton(
                      tooltip: 'Изпълни',
                      onPressed: _isRunning
                          ? null
                          : () =>
                              _executeSpokenCommand(_commandController.text),
                      icon: _isRunning
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward, color: ironGreen),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const _SectionTitle('Режими'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _routines.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              childAspectRatio: 1.05,
            ),
            itemBuilder: (context, index) {
              final item = _routines[index];
              return _CommandButton(
                item: item,
                onTap: _isRunning ? null : () => _run(item.action),
              );
            },
          ),
          const _SectionTitle('Бързи бутони'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: mainActions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              childAspectRatio: 1.65,
            ),
            itemBuilder: (context, index) {
              final item = mainActions[index];
              return _CommandButton(
                item: item,
                active: item.action == 'flash_toggle' && _flashlightOn,
                title: item.action == 'flash_toggle'
                    ? (_flashlightOn ? 'Фенер включен' : 'Фенер')
                    : null,
                icon: item.action == 'flash_toggle'
                    ? (_flashlightOn
                        ? Icons.flashlight_off
                        : Icons.flashlight_on)
                    : null,
                onTap: _isRunning ? null : () => _run(item.action),
              );
            },
          ),
          const SizedBox(height: 12),
          IronCard(
            margin: EdgeInsets.zero,
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.apps, color: ironGreen),
              title: const Text(
                'Още команди',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: moreActions.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 9,
                    crossAxisSpacing: 9,
                    childAspectRatio: 1.65,
                  ),
                  itemBuilder: (context, index) {
                    final item = moreActions[index];
                    return _CommandButton(
                      item: item,
                      onTap: _isRunning ? null : () => _run(item.action),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          IronCard(
            margin: EdgeInsets.zero,
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.auto_awesome, color: ironGreen),
              title: const Text(
                'Моите команди',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                if (widget.store.customAutomations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Все още нямаш лични команди.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                else
                  ...widget.store.customAutomations.map(
                    (automation) => _CustomAutomationTile(
                      automation: automation,
                      favorite: favoriteIds.contains('custom:${automation.id}'),
                      actionTitle: _titleForAction,
                      onRun: () => _runCustom(automation),
                      onEdit: () => _openCustomAutomationEditor(automation),
                      onDelete: () => _confirmDeleteCustom(automation),
                      onFavorite: () => widget.store.toggleAutomationFavorite(
                        'custom:${automation.id}',
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openCustomAutomationEditor(),
                    icon: const Icon(Icons.add),
                    label: const Text('Нова команда'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          IronCard(
            margin: EdgeInsets.zero,
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.settings_outlined, color: ironGreen),
              title: const Text(
                'Настройки',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.settings_input_antenna,
                    color: ironGreen,
                  ),
                  title: const Text('Automate'),
                  subtitle: const Text('Връзка за музикалния режим'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openAutomateSheet,
                ),
                if (widget.store.automationHistory.isNotEmpty) ...[
                  const Divider(),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Последни действия',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton(
                        onPressed: widget.store.clearAutomationHistory,
                        child: const Text('Изчисти'),
                      ),
                    ],
                  ),
                  for (var index = 0;
                      index < widget.store.automationHistory.length &&
                          index < 5;
                      index++) ...[
                    _HistoryRow(entry: widget.store.automationHistory[index]),
                    if (index < widget.store.automationHistory.length - 1 &&
                        index < 4)
                      const Divider(),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}

class _CommandButton extends StatelessWidget {
  final _AutomationItem item;
  final VoidCallback? onTap;
  final bool active;
  final String? title;
  final IconData? icon;

  const _CommandButton({
    required this.item,
    required this.onTap,
    this.active = false,
    this.title,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: active
                  ? ironGreen.withOpacity(0.18)
                  : ironPanelRaised.withOpacity(0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: active ? ironGreen : ironGreen.withOpacity(0.28),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon ?? item.icon, color: ironGreen, size: 28),
                const SizedBox(height: 7),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title ?? item.title,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _CustomAutomationTile extends StatelessWidget {
  final CustomAutomation automation;
  final bool favorite;
  final String Function(String action) actionTitle;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onFavorite;

  const _CustomAutomationTile({
    required this.automation,
    required this.favorite,
    required this.actionTitle,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) => IronCard(
        bright: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: ironGreen, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        automation.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Кажи: „${automation.voicePhrase}“',
                        style: const TextStyle(color: ironGreenSoft),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onFavorite,
                  icon: Icon(
                    favorite ? Icons.star : Icons.star_border,
                    color: favorite ? ironGreen : Colors.white38,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Редактирай')),
                    PopupMenuItem(value: 'delete', child: Text('Изтрий')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (var index = 0; index < automation.actions.length; index++)
                  Chip(
                    label: Text(
                      '${index + 1}. ${actionTitle(automation.actions[index])}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRun,
                icon: const Icon(Icons.play_arrow),
                label: const Text('ИЗПЪЛНИ'),
              ),
            ),
          ],
        ),
      );
}

class _HistoryRow extends StatelessWidget {
  final AutomationHistoryEntry entry;

  const _HistoryRow({required this.entry});

  String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final date = entry.executedAt;
    final time = '${_two(date.day)}.${_two(date.month)} '
        '${_two(date.hour)}:${_two(date.minute)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            entry.success ? Icons.check_circle : Icons.error,
            color: entry.success ? ironGreen : Colors.redAccent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  final String text;
  final VoidCallback onCopy;

  const _CodeBox({required this.text, required this.onCopy});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ironGreen.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(
                text,
                style: const TextStyle(
                  color: ironGreenSoft,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            IconButton(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, color: ironGreen),
            ),
          ],
        ),
      );
}

class _AutomationItem {
  final String action;
  final String title;
  final String subtitle;
  final IconData icon;

  const _AutomationItem(this.action, this.title, this.subtitle, this.icon);
}
