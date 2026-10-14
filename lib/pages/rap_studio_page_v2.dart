import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/song_project.dart';
import '../services/gemini_service.dart';
import '../services/local_store.dart';
import '../ui/common_widgets.dart';

class RapStudioPage extends StatefulWidget {
  final LocalStore store;

  const RapStudioPage({super.key, required this.store});

  @override
  State<RapStudioPage> createState() => _RapStudioPageState();
}

class _RapStudioPageState extends State<RapStudioPage> {
  final GeminiService _gemini = GeminiService();

  late final TextEditingController _titleController;
  late final TextEditingController _themeController;
  late final TextEditingController _draftController;
  late final TextEditingController _resultController;
  late final TextEditingController _musicPromptController;
  late final TextEditingController _excludeController;

  Timer? _saveTimer;
  bool _restoring = false;
  bool _isLoading = false;
  String _activeAction = '';
  String _saveStatus = 'Запазено локално';
  late int _loadedRevision;

  String _style = 'Hard trap';
  String _mood = 'Тъмно и агресивно';
  int _bpm = 140;

  static const List<String> _styles = <String>[
    'Hard trap',
    'Boom bap',
    'Drill',
    'Melodic trap',
    'Cinematic rap',
    'Old school',
    'Trap soul',
    'Post-rock rap',
  ];

  static const List<String> _moods = <String>[
    'Тъмно и агресивно',
    'Емоционално',
    'Мотивиращо',
    'Улично',
    'Мрачно и кинематографично',
    'Спокойно и дълбоко',
  ];

  List<TextEditingController> get _watchedControllers => <TextEditingController>[
        _titleController,
        _themeController,
        _draftController,
        _resultController,
        _musicPromptController,
        _excludeController,
      ];

  @override
  void initState() {
    super.initState();
    final song = widget.store.activeSong;
    _titleController = TextEditingController(text: song?.title ?? '');
    _themeController = TextEditingController(text: song?.theme ?? '');
    _draftController = TextEditingController(text: widget.store.rapDraft);
    _resultController = TextEditingController(text: widget.store.rapResult);
    _musicPromptController = TextEditingController(text: song?.musicPrompt ?? '');
    _excludeController = TextEditingController(text: song?.excludePrompt ?? '');
    _loadedRevision = widget.store.studioRevision;

    if (song != null) {
      _style = _styles.contains(song.style) ? song.style : _styles.first;
      _mood = _moods.contains(song.mood) ? song.mood : _moods.first;
      _bpm = song.bpm.clamp(70, 190).toInt();
    }

    for (final controller in _watchedControllers) {
      controller.addListener(_scheduleSave);
    }
    widget.store.addListener(_handleStoreChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyPendingVoiceRequest();
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    widget.store.removeListener(_handleStoreChange);
    _gemini.dispose();
    for (final controller in _watchedControllers) {
      controller.removeListener(_scheduleSave);
      controller.dispose();
    }
    super.dispose();
  }

  void _handleStoreChange() {
    if (!mounted || _loadedRevision == widget.store.studioRevision) return;
    _loadedRevision = widget.store.studioRevision;
    final song = widget.store.activeSong;

    _restoring = true;
    setState(() {
      _draftController.text = widget.store.rapDraft;
      _resultController.text = widget.store.rapResult;
      _titleController.text = song?.title ?? '';
      _themeController.text = song?.theme ?? '';
      _musicPromptController.text = song?.musicPrompt ?? '';
      _excludeController.text = song?.excludePrompt ?? '';
      _style = song != null && _styles.contains(song.style)
          ? song.style
          : _styles.first;
      _mood = song != null && _moods.contains(song.mood)
          ? song.mood
          : _moods.first;
      _bpm = song?.bpm.clamp(70, 190).toInt() ?? 140;
      _saveStatus = 'Запазено локално';
    });
    _restoring = false;
    _applyPendingVoiceRequest();
  }

  void _applyPendingVoiceRequest() {
    if (!mounted) return;
    final prompt = widget.store.pendingStudioPrompt.trim();
    if (prompt.isEmpty) return;

    final outputType = widget.store.pendingStudioOutputType.trim().toLowerCase();
    final autoGenerate = widget.store.pendingStudioAutoGenerate;
    widget.store.clearPendingStudioVoiceRequest();

    _restoring = true;
    setState(() {
      _draftController.text = prompt;
      _saveStatus = 'Гласовата задача е заредена';
    });
    _restoring = false;

    if (!autoGenerate || !widget.store.hasAnyAiProvider) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (outputType.contains('припев')) {
        _createHook();
      } else if (outputType.contains('куплет')) {
        _createVerse();
      } else {
        _generateSong();
      }
    });
  }

  void _scheduleSave() {
    if (_restoring || !mounted) return;
    setState(() => _saveStatus = 'Незапазени промени');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _persist);
  }

  String _timeLabel() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _persist() async {
    if (!mounted) return;
    _saveTimer?.cancel();
    setState(() => _saveStatus = 'Запазвам...');

    await widget.store.saveRapState(
      draft: _draftController.text,
      result: _resultController.text,
    );

    final active = widget.store.activeSong;
    if (active != null) {
      await widget.store.upsertSong(
        active.copyWith(
          title: _titleController.text.trim().isEmpty
              ? active.title
              : _titleController.text.trim(),
          lyrics: _currentLyrics,
          musicPrompt: _musicPromptController.text.trim(),
          excludePrompt: _excludeController.text.trim(),
          theme: _themeController.text.trim(),
          style: _style,
          mood: _mood,
          rhymeScheme: 'Многосрични рими',
          outputType: 'Цяла песен',
          bpm: _bpm,
        ),
      );
    }

    if (mounted) {
      setState(() => _saveStatus = 'Запазено ${_timeLabel()}');
    }
  }

  String get _currentLyrics {
    final result = _resultController.text.trim();
    if (result.isNotEmpty) return result;
    return _draftController.text.trim();
  }

  String get _contextSeed {
    final lyrics = _currentLyrics;
    if (lyrics.isNotEmpty) return lyrics;
    final theme = _themeController.text.trim();
    if (theme.isNotEmpty) return theme;
    return '';
  }

  String _styleDescription() {
    return switch (_style) {
      'Boom bap' =>
        'dark classic boom bap, dusty sample texture, hard drums, warm bass',
      'Drill' =>
        'dark Bulgarian drill, sliding 808 bass, tense piano, syncopated drums',
      'Melodic trap' =>
        'melodic Bulgarian trap, atmospheric pads, emotional piano, modern 808s',
      'Cinematic rap' =>
        'cinematic Bulgarian rap, dramatic strings, deep percussion, wide ambience',
      'Old school' =>
        'raw old-school Bulgarian hip hop, gritty samples, dry drums, warm bass',
      'Trap soul' =>
        'dark trap soul, warm keys, spacious pads, deep 808s, emotional dynamics',
      'Post-rock rap' =>
        'post-rock rap fusion, tremolo electric guitars, cinematic drums, deep bass',
      _ =>
        'hard Bulgarian trap rap, punchy 808 sub-bass, distorted kick, crisp snare, rapid hi-hats',
    };
  }

  String _moodDescription() {
    return switch (_mood) {
      'Емоционално' => 'emotional, vulnerable, intense',
      'Мотивиращо' => 'motivational, victorious, determined',
      'Улично' => 'raw street energy, gritty, authentic',
      'Мрачно и кинематографично' =>
        'dark cinematic tension, dramatic build-ups, wide soundstage',
      'Спокойно и дълбоко' => 'calm, deep, reflective, controlled dynamics',
      _ => 'dark, aggressive, urgent, tense minor-key atmosphere',
    };
  }

  String _buildStylePrompt() {
    return '${_styleDescription()} at $_bpm BPM, ${_moodDescription()}, '
        'deep natural low male rap vocal, precise Bulgarian diction, '
        'strong verse-to-hook dynamics, tight vocal doubles, restrained autotune, '
        'wide ad-libs with short plate reverb, clean modern mix, powerful controlled low end';
  }

  String _buildExcludePrompt() {
    final values = <String>[
      'female vocal',
      'high-pitched vocal',
      'childlike vocal',
      'cheerful pop melody',
      'comedy delivery',
      'soft weak drums',
      'muddy mix',
      'harsh clipping',
      'spoken production notes',
      'singing bracket instructions',
    ];
    if (_style != 'Melodic trap' && _style != 'Trap soul') {
      values.add('excessive autotune');
    }
    return values.join(', ');
  }

  String _cleanForSuno(String source) {
    var text = cleanMarkdownForDisplay(source)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = <String>[];
    final fullDirection = RegExp(r'^\s*\(.+\)\s*$');
    final sectionDirection = RegExp(r'^(\[[^\]]+\])\s*\(.+\)\s*$');

    for (final raw in text.split('\n')) {
      final trimmed = raw.trim();
      if (fullDirection.hasMatch(trimmed)) continue;
      final sectionMatch = sectionDirection.firstMatch(trimmed);
      if (sectionMatch != null) {
        lines.add(sectionMatch.group(1)!.trim());
        continue;
      }
      if (trimmed.isEmpty) {
        if (lines.isNotEmpty && lines.last.isNotEmpty) lines.add('');
      } else {
        lines.add(trimmed);
      }
    }

    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }

    text = lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    if (text.isNotEmpty && !RegExp(r'^\s*\[[^\]]+\]', multiLine: true).hasMatch(text)) {
      text = '[Куплет 1]\n$text';
    }
    return text;
  }

  String _songInstruction() {
    final seed = _contextSeed;
    return '''
Напиши завършена оригинална българска рап песен.
Структура: [Интро], [Куплет 1], [Припев], [Куплет 2], [Бридж], [Финален припев], [Аутро].
Стил: $_style.
Настроение: $_mood.
Темпо: $_bpm BPM.
Вокал: нисък плътен естествен мъжки глас.
Използвай конкретни образи и детайли от материала, естествен разговорен български, ясен flow и запомнящ се припев.
Изгради римни поредици с вътрешни, многосрични, асонансни и неточни рими. Всеки ред трябва да движи историята или да носи удар.
Без общи фрази, пълнеж, готови мотивационни лозунги, насилени окончания и изтъркани двойки като „мрак–прах“, „бетон–закон“, „болка–борба“, „върха–страха“ и „нощта–самота“.
Не измисляй факти за живота на автора. Не копирай известна песен или конкретен изпълнител.
Не поставяй музикални и вокални режисьорски указания в кръгли скоби. Върни само текста за пеене с квадратни секционни етикети.

Заглавие: ${_titleController.text.trim().isEmpty ? 'измисли подходящо' : _titleController.text.trim()}
Тема: ${_themeController.text.trim().isEmpty ? 'изведи темата от подадения текст' : _themeController.text.trim()}
Материал от потребителя:
${seed.isEmpty ? 'Няма готов текст. Създай песента от зададената тема и настройки.' : seed}
''';
  }

  Future<void> _runAi({
    required String action,
    required String instruction,
    bool append = false,
  }) async {
    if (!widget.store.hasAnyAiProvider) {
      _showMessage('Добави Gemini или резервен AI ключ в раздел „AI“.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _activeAction = action;
    });

    try {
      final response = await _gemini.generateRap(
        apiKey: widget.store.apiKey.trim(),
        instruction: instruction,
      );
      if (!mounted) return;
      final cleaned = _cleanForSuno(response);
      if (cleaned.isEmpty) {
        _showMessage('AI върна празен резултат.');
        return;
      }

      final before = _currentLyrics;
      final value = append && before.isNotEmpty
          ? '$before\n\n$cleaned'.trim()
          : cleaned;
      _setResult(value);
      await _persist();
      if (mounted) _showMessage('$action — готово.');
    } on GeminiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Неочаквана грешка при AI обработката.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _activeAction = '';
        });
      }
    }
  }

  void _setResult(String value) {
    _restoring = true;
    _resultController.text = value;
    _resultController.selection = TextSelection.collapsed(
      offset: _resultController.text.length,
    );
    _restoring = false;
    _scheduleSave();
  }

  Future<void> _generateSong() async {
    if (_contextSeed.isEmpty) {
      _showMessage('Напиши поне тема, идея или няколко реда.');
      return;
    }
    await _runAi(
      action: 'Създавам песента',
      instruction: _songInstruction(),
    );
  }

  Future<void> _improveText() async {
    final current = _currentLyrics;
    if (current.isEmpty) {
      _showMessage('Първо добави текст.');
      return;
    }
    await _runAi(
      action: 'Подобрявам текста',
      instruction: '''
Преработи професионално следния български рап текст.
Запази историята, фактите, смисъла, речника и личния тон. Не измисляй нова биография.
Подобри flow-а чрез римни поредици, вътрешни, многосрични, асонансни и неточни рими. Римата да следва смисъла, без неестествен словоред.
Запази силните редове. Замени клишетата, празните редове, повторените идеи, общите фрази и слабите окончания с конкретни образи и действия.
Не добавяй обяснения. Не използвай кръгли скоби с указания.
Стил: $_style. Настроение: $_mood. Темпо: $_bpm BPM.

ТЕКСТ:
$current
''',
    );
  }

  Future<void> _createHook() async {
    final seed = _contextSeed;
    if (seed.isEmpty) {
      _showMessage('Напиши тема, идея или текст за припева.');
      return;
    }
    await _runAi(
      action: 'Правя припев',
      append: _currentLyrics.isNotEmpty,
      instruction: '''
Напиши силен оригинален български рап припев от 6 до 8 реда.
Да е лесен за запомняне, ритмичен и годен за повторение, но да не звучи като готов шаблон.
Изведи една ясна централна фраза от подадения контекст. Използвай естествен разговорен български, вътрешни и многосрични рими и конкретни образи.
Без кухи лозунги, произволни „мрак/бетон/болка“ образи, насилени окончания и нови факти извън материала.
Стил: $_style. Настроение: $_mood. Темпо: $_bpm BPM.
Върни само секция [Припев], без обяснения и без указания в кръгли скоби.

КОНТЕКСТ ИЛИ ТЕМА:
$seed
''',
    );
  }

  Future<void> _createVerse() async {
    final seed = _contextSeed;
    if (seed.isEmpty) {
      _showMessage('Напиши тема, идея или текст за куплета.');
      return;
    }
    await _runAi(
      action: 'Правя куплет',
      append: _currentLyrics.isNotEmpty,
      instruction: '''
Напиши един оригинален български рап куплет от 16 бара, който естествено пасва към подадения контекст.
Направи римни поредици от 2–4 бара с вътрешни, многосрични, асонансни и неточни рими, разнообразен flow и ясни punchlines.
Всеки бар да добавя конкретен образ, действие, детайл или позиция. Без пълнеж, общи фрази, измислени житейски факти, неестествен словоред и изтъркани римни двойки.
Стил: $_style. Настроение: $_mood. Темпо: $_bpm BPM.
Върни само секция [Куплет], без обяснения и без указания в кръгли скоби.

КОНТЕКСТ ИЛИ ТЕМА:
$seed
''',
    );
  }

  Future<void> _formatForSuno() async {
    final current = _currentLyrics;
    if (current.isEmpty) {
      _showMessage('Първо добави или генерирай текст.');
      return;
    }
    final cleaned = _cleanForSuno(current);
    _setResult(cleaned);
    if (_musicPromptController.text.trim().isEmpty) {
      _restoring = true;
      _musicPromptController.text = _buildStylePrompt();
      _excludeController.text = _buildExcludePrompt();
      _restoring = false;
    }
    await _persist();
    if (mounted) _showMessage('Текстът е подготвен за Suno.');
  }

  Future<void> _generateStylePrompt() async {
    FocusScope.of(context).unfocus();
    _restoring = true;
    _musicPromptController.text = _buildStylePrompt();
    _excludeController.text = _buildExcludePrompt();
    _restoring = false;
    _scheduleSave();
    await _persist();
    if (mounted) _showMessage('Style Prompt и Exclude са готови.');
  }

  Future<void> _copyLyrics() async {
    final lyrics = _cleanForSuno(_currentLyrics);
    if (lyrics.isEmpty) {
      _showMessage('Няма текст за копиране.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: lyrics));
    if (mounted) _showMessage('Lyrics са копирани.');
  }

  Future<void> _copyPrompt() async {
    final prompt = _musicPromptController.text.trim();
    if (prompt.isEmpty) {
      _showMessage('Първо направи Style Prompt.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: prompt));
    if (mounted) _showMessage('Style Prompt е копиран.');
  }

  Future<void> _copySunoPackage() async {
    final lyrics = _cleanForSuno(_currentLyrics);
    if (lyrics.isEmpty) {
      _showMessage('Няма текст за Suno.');
      return;
    }
    final style = _musicPromptController.text.trim().isEmpty
        ? _buildStylePrompt()
        : _musicPromptController.text.trim();
    final exclude = _excludeController.text.trim().isEmpty
        ? _buildExcludePrompt()
        : _excludeController.text.trim();
    final package = '''LYRICS
------
$lyrics

STYLE OF MUSIC
--------------
$style

EXCLUDE
-------
$exclude''';
    await Clipboard.setData(ClipboardData(text: package));
    if (mounted) _showMessage('Целият Suno пакет е копиран.');
  }

  Future<void> _moveResultToDraft() async {
    final result = _resultController.text.trim();
    if (result.isEmpty) {
      _showMessage('Няма AI резултат за преместване.');
      return;
    }
    _restoring = true;
    _draftController.text = result;
    _resultController.clear();
    _draftController.selection = TextSelection.collapsed(
      offset: _draftController.text.length,
    );
    _restoring = false;
    _scheduleSave();
    await _persist();
    if (mounted) _showMessage('Резултатът е преместен в основния текст.');
  }

  Future<void> _saveProject() async {
    final lyrics = _cleanForSuno(_currentLyrics);
    if (lyrics.isEmpty) {
      _showMessage('Няма текст за запазване.');
      return;
    }

    final title = _titleController.text.trim().isEmpty
        ? (_themeController.text.trim().isEmpty
            ? 'Нова песен'
            : _themeController.text.trim())
        : _titleController.text.trim();
    final stylePrompt = _musicPromptController.text.trim().isEmpty
        ? _buildStylePrompt()
        : _musicPromptController.text.trim();
    final exclude = _excludeController.text.trim().isEmpty
        ? _buildExcludePrompt()
        : _excludeController.text.trim();

    final existing = widget.store.activeSong;
    final project = existing == null
        ? SongProject.create(
            title: title,
            lyrics: lyrics,
            musicPrompt: stylePrompt,
            excludePrompt: exclude,
            theme: _themeController.text.trim(),
            style: _style,
            mood: _mood,
            rhymeScheme: 'Многосрични рими',
            outputType: 'Цяла песен',
            bpm: _bpm,
          )
        : existing.copyWith(
            title: title,
            lyrics: lyrics,
            musicPrompt: stylePrompt,
            excludePrompt: exclude,
            theme: _themeController.text.trim(),
            style: _style,
            mood: _mood,
            rhymeScheme: 'Многосрични рими',
            outputType: 'Цяла песен',
            bpm: _bpm,
          );

    await widget.store.upsertSong(project);
    _restoring = true;
    _titleController.text = project.title;
    _musicPromptController.text = stylePrompt;
    _excludeController.text = exclude;
    _restoring = false;
    await _persist();
    if (mounted) _showMessage('Песента е запазена в „Моите песни“.');
  }

  Future<void> _newProject() async {
    FocusScope.of(context).unfocus();
    _saveTimer?.cancel();
    await widget.store.startNewStudioProject();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Widget _quickAction({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: ironGreen,
        backgroundColor: ironGreen.withOpacity(0.035),
        side: BorderSide(color: ironGreen.withOpacity(0.45)),
        minimumSize: const Size(148, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      dropdownColor: ironPanelRaised,
      iconEnabledColor: ironGreen,
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(growable: false),
      onChanged: _isLoading ? null : onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: ironGreen),
        filled: true,
        fillColor: const Color(0xFF010A05).withOpacity(0.92),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: ironGreen.withOpacity(0.29)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: ironGreen, width: 1.6),
        ),
      ),
    );
  }

  Widget _providerStatus() {
    final ready = widget.store.hasAnyAiProvider;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: (ready ? ironGreen : Colors.amber).withOpacity(0.08),
        border: Border.all(
          color: (ready ? ironGreen : Colors.amber).withOpacity(0.42),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.bolt : Icons.info_outline,
            size: 16,
            color: ready ? ironGreen : Colors.amber,
          ),
          const SizedBox(width: 6),
          Text(
            ready ? 'AI готов' : 'AI ключ липсва',
            style: TextStyle(
              color: ready ? ironGreen : Colors.amber,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = _resultController.text.trim().isNotEmpty;

    return IronBackground(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: [
          PageTitle(
            eyebrow: 'IRON RAP LAB',
            title: 'Rap Studio',
            subtitle: 'Пишеш текста тук. Инструментите отдолу реално го обработват.',
            trailing: IconButton(
              tooltip: 'Нов проект',
              onPressed: _isLoading ? null : _newProject,
              icon: const Icon(Icons.note_add_outlined, color: ironGreen),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _providerStatus(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _saveStatus,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          IronInput(
            controller: _titleController,
            label: 'Заглавие',
            hint: 'По желание',
            icon: Icons.title,
          ),
          const SizedBox(height: 12),
          IronInput(
            controller: _themeController,
            label: 'Тема / посока',
            hint: 'Например: от дъното до върха, улица, загуба, победа',
            icon: Icons.lightbulb_outline,
            minLines: 2,
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          IronCard(
            margin: EdgeInsets.zero,
            bright: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'МОЯТ ТЕКСТ',
                  style: TextStyle(
                    color: ironGreen,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Постави готов текст, няколко реда или само идея. Нищо не се губи — полето се пази локално.',
                  style: TextStyle(color: Colors.white60, height: 1.35),
                ),
                const SizedBox(height: 12),
                IronInput(
                  controller: _draftController,
                  label: 'Lyrics / Чернова',
                  hint: 'Пиши тук…',
                  icon: Icons.edit_note,
                  minLines: 12,
                  maxLines: 24,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          IronButton(
            text: _isLoading ? _activeAction : 'Създай цяла песен',
            icon: Icons.auto_awesome,
            onPressed: _isLoading ? null : _generateSong,
          ),
          const SizedBox(height: 14),
          IronCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'БЪРЗИ ИНСТРУМЕНТИ',
                  style: TextStyle(
                    color: ironGreen,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _quickAction(
                      label: 'Подобри текста',
                      icon: Icons.auto_fix_high,
                      onPressed: _improveText,
                    ),
                    _quickAction(
                      label: 'Направи припев',
                      icon: Icons.repeat,
                      onPressed: _createHook,
                    ),
                    _quickAction(
                      label: 'Направи куплет',
                      icon: Icons.library_music_outlined,
                      onPressed: _createVerse,
                    ),
                    _quickAction(
                      label: 'Suno формат',
                      icon: Icons.cleaning_services_outlined,
                      onPressed: _formatForSuno,
                    ),
                    _quickAction(
                      label: 'Style Prompt',
                      icon: Icons.tune,
                      onPressed: _generateStylePrompt,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isLoading) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(color: ironGreen),
          ],
          const SizedBox(height: 14),
          IronCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'AI РЕЗУЛТАТ',
                        style: TextStyle(
                          color: ironGreen,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    if (hasResult)
                      IconButton(
                        tooltip: 'Копирай Lyrics',
                        onPressed: _copyLyrics,
                        icon: const Icon(Icons.copy, color: ironGreen),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _resultController,
                  minLines: 12,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  cursorColor: ironGreen,
                  style: const TextStyle(color: Colors.white, height: 1.45),
                  decoration: InputDecoration(
                    hintText: 'Генерираният или обработеният текст ще се появи тук.',
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xFF010A05).withOpacity(0.92),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: BorderSide(color: ironGreen.withOpacity(0.29)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: const BorderSide(color: ironGreen, width: 1.6),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: IronButton(
                        text: 'Copy Lyrics',
                        icon: Icons.copy,
                        compact: true,
                        secondary: true,
                        onPressed: hasResult || _draftController.text.trim().isNotEmpty
                            ? _copyLyrics
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: IronButton(
                        text: 'Към основния текст',
                        icon: Icons.arrow_upward,
                        compact: true,
                        secondary: true,
                        onPressed: hasResult ? _moveResultToDraft : null,
                      ),
                    ),
                  ],
                ),
                if (_gemini.activeModel != null) ...[
                  const SizedBox(height: 9),
                  Text(
                    'Модел: ${_gemini.activeModel}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          IronCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SUNO ПАКЕТ',
                  style: TextStyle(
                    color: ironGreen,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Lyrics, Style of Music и Exclude са отделени, за да ги поставиш директно в Suno.',
                  style: TextStyle(color: Colors.white60, height: 1.35),
                ),
                const SizedBox(height: 12),
                IronInput(
                  controller: _musicPromptController,
                  label: 'Style of Music',
                  hint: 'Натисни „Style Prompt“',
                  icon: Icons.graphic_eq,
                  minLines: 4,
                  maxLines: 8,
                ),
                const SizedBox(height: 10),
                IronInput(
                  controller: _excludeController,
                  label: 'Exclude',
                  hint: 'Нежелани елементи',
                  icon: Icons.block,
                  minLines: 2,
                  maxLines: 5,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: IronButton(
                        text: 'Copy Prompt',
                        icon: Icons.copy,
                        compact: true,
                        secondary: true,
                        onPressed: _musicPromptController.text.trim().isEmpty
                            ? null
                            : _copyPrompt,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: IronButton(
                        text: 'Copy Suno пакет',
                        icon: Icons.content_copy,
                        compact: true,
                        onPressed: _currentLyrics.isEmpty ? null : _copySunoPackage,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          IronCard(
            margin: EdgeInsets.zero,
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.tune, color: ironGreen),
              title: const Text(
                'Стил и темпо',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('$_style • $_bpm BPM • $_mood'),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                _dropdown(
                  label: 'Стил',
                  value: _style,
                  items: _styles,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _style = value);
                    _scheduleSave();
                  },
                ),
                const SizedBox(height: 12),
                _dropdown(
                  label: 'Настроение',
                  value: _mood,
                  items: _moods,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _mood = value);
                    _scheduleSave();
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.speed, color: ironGreen),
                    const SizedBox(width: 8),
                    Text(
                      '$_bpm BPM',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                Slider(
                  value: _bpm.toDouble(),
                  min: 70,
                  max: 190,
                  divisions: 24,
                  label: '$_bpm BPM',
                  onChanged: _isLoading
                      ? null
                      : (value) {
                          setState(() => _bpm = value.round());
                          _scheduleSave();
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          IronButton(
            text: 'Запази в „Моите песни“',
            icon: Icons.save,
            secondary: true,
            onPressed: _isLoading || _currentLyrics.isEmpty ? null : _saveProject,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
