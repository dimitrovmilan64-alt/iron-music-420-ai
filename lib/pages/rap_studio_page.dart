import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/song_project.dart';
import '../services/gemini_service.dart';
import '../services/local_store.dart';
import '../ui/common_widgets.dart';

class _SunoLyricsCleanup {
  final String lyrics;
  final List<String> directions;

  const _SunoLyricsCleanup({required this.lyrics, required this.directions});
}

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
  late final TextEditingController _keywordsController;
  late final TextEditingController _draftController;
  late final TextEditingController _resultController;
  late final TextEditingController _musicPromptController;
  late final TextEditingController _excludeController;

  final List<String> _undoStack = <String>[];
  final List<String> _redoStack = <String>[];

  Timer? _saveTimer;
  bool _restoring = false;
  bool _isLoading = false;
  bool _resultIsMusicPrompt = false;
  String _saveStatus = 'Запазено локално';
  String _activeAction = '';
  final List<String> _sunoDirections = <String>[];
  late int _loadedRevision;

  String _style = 'Hard trap';
  String _mood = 'Тъмно и агресивно';
  String _outputType = 'Цяла песен';
  String _rhymeScheme = 'Многосрични рими';
  int _bpm = 140;

  static const _styles = <String>[
    'Hard trap',
    'Boom bap',
    'Drill',
    'Melodic trap',
    'Cinematic rap',
    'Old school',
    'Trap soul',
    'Post-rock rap',
  ];

  static const _moods = <String>[
    'Тъмно и агресивно',
    'Емоционално',
    'Мотивиращо',
    'Улично',
    'Мрачно и кинематографично',
    'Спокойно и дълбоко',
  ];

  static const _outputTypes = <String>[
    'Куплет',
    'Припев',
    'Цяла песен',
    'Редактирай черновата',
    'Рими и punchlines',
  ];

  static const _rhymeSchemes = <String>[
    'Многосрични рими',
    'AABB',
    'ABAB',
    'Вътрешни рими',
    'Свободна схема',
  ];

  List<TextEditingController> get _allControllers => [
        _titleController,
        _themeController,
        _keywordsController,
        _draftController,
        _resultController,
        _musicPromptController,
        _excludeController,
      ];

  @override
  void initState() {
    super.initState();
    final activeSong = widget.store.activeSong;
    _titleController = TextEditingController(text: activeSong?.title ?? '');
    _themeController = TextEditingController(text: activeSong?.theme ?? '');
    _keywordsController = TextEditingController(
      text: activeSong?.keywords ?? '',
    );
    _draftController = TextEditingController(text: widget.store.rapDraft);
    _resultController = TextEditingController(text: widget.store.rapResult);
    _musicPromptController = TextEditingController(
      text: activeSong?.musicPrompt ?? '',
    );
    _excludeController = TextEditingController(
      text: activeSong?.excludePrompt ?? '',
    );
    _loadedRevision = widget.store.studioRevision;

    if (activeSong != null) {
      _style =
          _styles.contains(activeSong.style) ? activeSong.style : _styles.first;
      _mood = _moods.contains(activeSong.mood) ? activeSong.mood : _moods.first;
      _rhymeScheme = _rhymeSchemes.contains(activeSong.rhymeScheme)
          ? activeSong.rhymeScheme
          : _rhymeSchemes.first;
      _outputType = activeSong.outputType == 'Suno / Riffusion промпт'
          ? 'Цяла песен'
          : (_outputTypes.contains(activeSong.outputType)
              ? activeSong.outputType
              : 'Цяла песен');
      _bpm = activeSong.bpm.clamp(60, 220).toInt();
    }

    for (final controller in _allControllers) {
      controller.addListener(_markChanged);
    }
    widget.store.addListener(_handleStoreChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyPendingStudioVoiceRequest();
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    widget.store.removeListener(_handleStoreChange);
    _gemini.dispose();
    for (final controller in _allControllers) {
      controller.removeListener(_markChanged);
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
      _resultIsMusicPrompt = false;
      _undoStack.clear();
      _redoStack.clear();
      _saveStatus = 'Запазено локално';

      if (song == null) {
        _titleController.clear();
        _themeController.clear();
        _keywordsController.clear();
        _musicPromptController.clear();
        _excludeController.clear();
        _style = _styles.first;
        _mood = _moods.first;
        _outputType = 'Цяла песен';
        _rhymeScheme = _rhymeSchemes.first;
        _bpm = 140;
      } else {
        _titleController.text = song.title;
        _themeController.text = song.theme;
        _keywordsController.text = song.keywords;
        _musicPromptController.text = song.musicPrompt;
        _excludeController.text = song.excludePrompt;
        _style = _styles.contains(song.style) ? song.style : _styles.first;
        _mood = _moods.contains(song.mood) ? song.mood : _moods.first;
        _rhymeScheme = _rhymeSchemes.contains(song.rhymeScheme)
            ? song.rhymeScheme
            : _rhymeSchemes.first;
        _outputType = song.outputType == 'Suno / Riffusion промпт'
            ? 'Цяла песен'
            : (_outputTypes.contains(song.outputType)
                ? song.outputType
                : 'Цяла песен');
        _bpm = song.bpm.clamp(60, 220).toInt();
      }
    });
    _restoring = false;
    _applyPendingStudioVoiceRequest();
  }

  void _applyPendingStudioVoiceRequest() {
    if (!mounted) return;
    final prompt = widget.store.pendingStudioPrompt.trim();
    if (prompt.isEmpty) return;

    final requestedType = widget.store.pendingStudioOutputType.trim();
    final autoGenerate = widget.store.pendingStudioAutoGenerate;
    widget.store.clearPendingStudioVoiceRequest();

    _restoring = true;
    setState(() {
      _themeController.text = prompt;
      if (_outputTypes.contains(requestedType)) {
        _outputType = requestedType;
      }
      _saveStatus = 'Гласова команда заредена';
    });
    _restoring = false;

    if (!autoGenerate) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.store.hasAnyAiProvider) {
        _generateWithAi();
      } else {
        _showMessage(
          'Командата е заредена. Добави Gemini или Groq, за да генерирам текста.',
        );
      }
    });
  }

  void _markChanged() {
    if (_restoring || !mounted) return;
    setState(() => _saveStatus = 'Незапазени промени');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), () {
      _persistStudioState();
    });
  }

  void _markOptionChanged() {
    if (!mounted) return;
    setState(() => _saveStatus = 'Незапазени промени');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), () {
      _persistStudioState();
    });
  }

  String _timeLabel() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _persistStudioState() async {
    if (!mounted) return;
    setState(() => _saveStatus = 'Запазвам...');

    await widget.store.saveRapState(
      draft: _draftController.text,
      result: _resultController.text,
    );

    final activeSong = widget.store.activeSong;
    if (activeSong != null) {
      final title = _titleController.text.trim().isEmpty
          ? activeSong.title
          : _titleController.text.trim();
      await widget.store.upsertSong(_buildProject(title));
    }

    if (mounted) {
      setState(() => _saveStatus = 'Запазено ${_timeLabel()}');
    }
  }

  String _buildInstruction() {
    final theme = _themeController.text.trim();
    final keywords = _keywordsController.text.trim();
    final draft = _draftController.text.trim();

    final structure = switch (_outputType) {
      'Куплет' => 'Напиши един куплет от 16 бара с ясен ритъм.',
      'Припев' =>
        'Напиши силен и лесен за запомняне припев от 8 реда, подходящ за повтаряне.',
      'Редактирай черновата' =>
        'Редактирай черновата професионално. Запази смисъла и личния стил, но оправи ритъма, римите, повторенията и слабите редове.',
      'Рими и punchlines' =>
        'Дай 16 оригинални рими и punchlines, които могат директно да се използват в песента.',
      _ =>
        'Напиши цяла песен със структура [Интро], [Куплет 1], [Припев], [Куплет 2], [Бридж], [Финален припев].',
    };

    return '''
$structure

Заглавие: ${_titleController.text.trim().isEmpty ? 'измисли подходящо заглавие' : _titleController.text.trim()}
Тема: ${theme.isEmpty ? 'борба, амбиция, загуби и победа' : theme}
Стил: $_style
Настроение: $_mood
BPM: $_bpm
Римна схема: $_rhymeScheme
Ключови думи: ${keywords.isEmpty ? 'болка, улица, вярност, сила' : keywords}
Език: български
Вокал: нисък плътен мъжки глас
Изискване: оригинален текст, естествен български език, силни вътрешни рими, ясна структура и без копиране на известни песни.
Правило за Suno: не поставяй режисьорски, вокални или инструментални указания в кръгли скоби и не използвай кръгли скоби в текста. Остави само секционни етикети в квадратни скоби, например [Интро], [Куплет 1], [Припев], [Бридж], [Аутро]. Всички музикални указания принадлежат в отделния музикален промпт, а не в текста за пеене.
Важно: завърши целия резултат и не прекъсвай последния ред. Ако текстът стане прекалено дълъг, съкрати броя редове, но запази всички поискани части и финален край.

Чернова на потребителя:
${draft.isEmpty ? 'Няма чернова. Създай съдържанието от нулата.' : draft}
''';
  }

  String _styleDescriptor() {
    return switch (_style) {
      'Boom bap' =>
        'dark classic boom bap, dusty vinyl texture, sampled piano and hard drums',
      'Drill' =>
        'dark Bulgarian drill, sliding 808 bass, tense piano and syncopated drums',
      'Melodic trap' =>
        'melodic Bulgarian trap, atmospheric pads, emotional piano and modern 808s',
      'Cinematic rap' =>
        'cinematic Bulgarian rap, dramatic strings, deep percussion and wide ambience',
      'Old school' =>
        'raw old-school Bulgarian hip hop, gritty samples, dry drums and warm bass',
      'Trap soul' =>
        'dark trap soul, warm keys, spacious pads, deep 808s and emotional dynamics',
      'Post-rock rap' =>
        'post-rock rap fusion, tremolo electric guitars, cinematic drums and deep bass',
      _ =>
        'hard Bulgarian trap rap, punchy 808 sub-bass, hard kick, crisp snare and detailed hi-hats',
    };
  }

  String _moodDescriptor() {
    return switch (_mood) {
      'Емоционално' => 'emotional, vulnerable and intense atmosphere',
      'Мотивиращо' => 'motivational, victorious and determined energy',
      'Улично' => 'raw street energy, gritty and authentic atmosphere',
      'Мрачно и кинематографично' =>
        'dark cinematic tension, dramatic build-ups and wide soundstage',
      'Спокойно и дълбоко' =>
        'calm, deep and reflective mood with controlled dynamics',
      _ => 'dark aggressive energy and tense minor-key atmosphere',
    };
  }

  String _buildLocalPrompt() {
    final parts = <String>[
      '${_styleDescriptor()} at $_bpm BPM',
      _moodDescriptor(),
      'deep natural low male rap vocal',
      'precise Bulgarian diction',
      'strong verse-to-hook dynamics',
      'restrained autotune',
      'wide but controlled ad-libs',
      'clean modern mix',
      'powerful controlled low end',
    ];

    if (_sunoDirections.isNotEmpty) {
      parts.add('arrangement notes: ${_sunoDirections.join('; ')}');
    }

    return parts.join(', ').trim();
  }

  String _buildExcludePrompt() {
    final exclusions = <String>[
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
      exclusions.addAll(['excessive autotune', 'pop chorus']);
    }
    if (_style != 'Drill') exclusions.add('drill sirens');
    if (_style != 'Post-rock rap') exclusions.add('rock guitar solo');

    return exclusions.join(', ');
  }

  _SunoLyricsCleanup _cleanLyricsForSuno(String source) {
    final directions = <String>[];
    final output = <String>[];
    final seenDirections = <String>{};
    final fullDirection = RegExp(r'^\((.+)\)$');
    final sectionWithDirection = RegExp(r'^(\[[^\]]+\])\s*\((.+)\)\s*$');

    for (final rawLine in source.replaceAll('\r\n', '\n').split('\n')) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) {
        if (output.isNotEmpty && output.last.isNotEmpty) output.add('');
        continue;
      }

      final sectionMatch = sectionWithDirection.firstMatch(trimmed);
      if (sectionMatch != null) {
        final section = sectionMatch.group(1)!.trim();
        final direction = sectionMatch.group(2)!.trim();
        output.add(section);
        if (direction.isNotEmpty && seenDirections.add(direction)) {
          directions.add(direction);
        }
        continue;
      }

      final directionMatch = fullDirection.firstMatch(trimmed);
      if (directionMatch != null) {
        final direction = directionMatch.group(1)!.trim();
        if (direction.isNotEmpty && seenDirections.add(direction)) {
          directions.add(direction);
        }
        continue;
      }

      output.add(rawLine.trimRight());
    }

    while (output.isNotEmpty && output.last.isEmpty) {
      output.removeLast();
    }

    final compact = <String>[];
    for (final line in output) {
      if (line.isEmpty && compact.isNotEmpty && compact.last.isEmpty) continue;
      compact.add(line);
    }

    return _SunoLyricsCleanup(
      lyrics: compact.join('\n').trim(),
      directions: directions,
    );
  }

  void _rememberSunoDirections(Iterable<String> values) {
    for (final value in values) {
      final cleaned = value.trim();
      if (cleaned.isEmpty) continue;
      final exists = _sunoDirections.any(
        (item) => item.toLowerCase() == cleaned.toLowerCase(),
      );
      if (!exists) _sunoDirections.add(cleaned);
    }
  }

  String _appendDirectionsToPrompt(String basePrompt) {
    if (_sunoDirections.isEmpty) return basePrompt.trim();
    final lower = basePrompt.toLowerCase();
    final missing = _sunoDirections
        .where((item) => !lower.contains(item.toLowerCase()))
        .toList();
    if (missing.isEmpty) return basePrompt.trim();

    return '${basePrompt.trim()}, arrangement notes: ${missing.join('; ')}';
  }

  Future<void> _cleanCurrentLyricsForSuno() async {
    final source = _currentLyrics;
    if (source.isEmpty) {
      _showMessage('Първо добави или генерирай текст.');
      return;
    }

    final cleanup = _cleanLyricsForSuno(source);
    if (cleanup.lyrics.isEmpty) {
      _showMessage('След почистването не остана текст за пеене.');
      return;
    }

    _captureSnapshot();
    _rememberSunoDirections(cleanup.directions);
    _setResult(cleanup.lyrics, musicPrompt: false);
    if (cleanup.directions.isNotEmpty) {
      final basePrompt = _musicPromptController.text.trim().isNotEmpty
          ? _musicPromptController.text.trim()
          : _buildLocalPrompt();
      _musicPromptController.text = _appendDirectionsToPrompt(basePrompt);
    }
    if (_excludeController.text.trim().isEmpty) {
      _excludeController.text = _buildExcludePrompt();
    }
    await _persistStudioState();

    if (!mounted) return;
    if (cleanup.directions.isEmpty) {
      _showMessage('Текстът вече е чист за Suno.');
    } else {
      _showMessage(
        'Премахнати са ${cleanup.directions.length} бележки в скоби. Те са добавени към музикалния промпт.',
      );
    }
  }

  Future<void> _copyCleanLyricsForSuno() async {
    final source = _currentLyrics;
    if (source.isEmpty) return;
    final cleanup = _cleanLyricsForSuno(source);
    _rememberSunoDirections(cleanup.directions);
    await Clipboard.setData(ClipboardData(text: cleanup.lyrics));
    if (mounted) _showMessage('Чистият текст за Suno е копиран.');
  }

  void _captureSnapshot() {
    final current = _resultController.text;
    if (current.isEmpty) return;
    if (_undoStack.isEmpty || _undoStack.last != current) {
      _undoStack.add(current);
      if (_undoStack.length > 20) _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _setResult(
    String value, {
    bool musicPrompt = false,
    bool moveCursorToEnd = true,
  }) {
    _restoring = true;
    _resultController.text = value;
    _resultIsMusicPrompt = musicPrompt;
    if (moveCursorToEnd) {
      _resultController.selection = TextSelection.collapsed(
        offset: _resultController.text.length,
      );
    }
    _restoring = false;
    _markChanged();
  }

  void _undoResult() {
    if (_undoStack.isEmpty) {
      _showMessage('Няма по-стара версия за връщане.');
      return;
    }
    final current = _resultController.text;
    if (current.isNotEmpty) _redoStack.add(current);
    final previous = _undoStack.removeLast();
    _setResult(previous, musicPrompt: _resultIsMusicPrompt);
  }

  void _redoResult() {
    if (_redoStack.isEmpty) {
      _showMessage('Няма следваща версия.');
      return;
    }
    final current = _resultController.text;
    if (current.isNotEmpty) _undoStack.add(current);
    final next = _redoStack.removeLast();
    _setResult(next, musicPrompt: _resultIsMusicPrompt);
  }

  Future<void> _generateWithAi() async {
    final apiKey = widget.store.apiKey.trim();
    if (!widget.store.hasAnyAiProvider) {
      _showMessage('Първо добави Gemini или резервен AI доставчик в раздел „AI“.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _activeAction = 'Генерирам';
    });

    try {
      final result = await _gemini.generateRap(
        apiKey: apiKey,
        instruction: _buildInstruction(),
      );
      if (!mounted) return;
      _captureSnapshot();
      final cleanup = _cleanLyricsForSuno(result);
      _rememberSunoDirections(cleanup.directions);
      _setResult(cleanup.lyrics, musicPrompt: false);
      if (_musicPromptController.text.trim().isEmpty) {
        _musicPromptController.text = _buildLocalPrompt();
      }
      if (_excludeController.text.trim().isEmpty) {
        _excludeController.text = _buildExcludePrompt();
      }
      await _persistStudioState();
    } on GeminiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Неочаквана грешка при AI генерацията.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _activeAction = '';
        });
      }
    }
  }

  Future<void> _runAiTool({
    required String actionName,
    required String instruction,
    required void Function(String result) applyResult,
  }) async {
    final apiKey = widget.store.apiKey.trim();
    if (!widget.store.hasAnyAiProvider) {
      _showMessage('Първо добави Gemini или резервен AI доставчик в раздел „AI“.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _activeAction = actionName;
    });

    try {
      final result = await _gemini.generateRap(
        apiKey: apiKey,
        instruction: instruction,
      );
      if (!mounted) return;
      _captureSnapshot();
      applyResult(result);
      await _persistStudioState();
    } on GeminiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Неочаквана грешка при AI редакцията.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _activeAction = '';
        });
      }
    }
  }

  String get _currentLyrics {
    final result = _resultController.text.trim();
    if (result.isNotEmpty) return result;
    return _draftController.text.trim();
  }

  Future<void> _continueText() async {
    final current = _currentLyrics;
    if (current.isEmpty) {
      _showMessage('Първо добави или генерирай текст.');
      return;
    }

    await _runAiTool(
      actionName: 'Продължавам текста',
      instruction: '''
Продължи следващия български рап текст естествено, без да повтаряш вече написаното.
Добави следваща логична част — куплет, бридж или финален припев според структурата.
Спази стил $_style, настроение $_mood, $_bpm BPM и римна схема $_rhymeScheme.
Върни само новото продължение, напълно завършено. Не използвай кръгли скоби и не добавяй музикални или вокални указания в текста.

ТЕКСТ ДО МОМЕНТА:
$current
''',
      applyResult: (result) {
        final cleanup = _cleanLyricsForSuno(result);
        _rememberSunoDirections(cleanup.directions);
        final combined = '$current\n\n${cleanup.lyrics}'.trim();
        _setResult(combined, musicPrompt: false);
      },
    );
  }

  Future<void> _createHook() async {
    final current = _currentLyrics;
    if (current.isEmpty) {
      _showMessage('Първо добави текст или тема.');
      return;
    }

    await _runAiTool(
      actionName: 'Правя припев',
      instruction: '''
Напиши оригинален силен български рап припев от 6 до 8 реда за следната песен.
Да е лесен за запомняне, ритмичен и подходящ за повторение два пъти.
Стил: $_style. Настроение: $_mood. BPM: $_bpm.
Върни само секция [Припев], без обяснения. Не използвай кръгли скоби и не добавяй музикални или вокални указания в текста.

КОНТЕКСТ НА ПЕСЕНТА:
$current
''',
      applyResult: (result) {
        final cleanup = _cleanLyricsForSuno(result);
        _rememberSunoDirections(cleanup.directions);
        final combined = '$current\n\n${cleanup.lyrics}'.trim();
        _setResult(combined, musicPrompt: false);
      },
    );
  }

  Future<void> _tightenRhymes() async {
    final current = _currentLyrics;
    if (current.isEmpty) {
      _showMessage('Първо добави или генерирай текст.');
      return;
    }

    await _runAiTool(
      actionName: 'Стягам римите',
      instruction: '''
Преработи целия български рап текст професионално.
Запази смисъла, историята, структурата и личния тон.
Подобри ритъма, вътрешните и многосричните рими, премахни слабите повторения и направи редовете по-ударни.
Не съкращавай важни части. Върни целия завършен редактиран текст, без обяснения. Не използвай кръгли скоби и не добавяй музикални или вокални указания в текста.

ОРИГИНАЛ:
$current
''',
      applyResult: (result) {
        final cleanup = _cleanLyricsForSuno(result);
        _rememberSunoDirections(cleanup.directions);
        _setResult(cleanup.lyrics, musicPrompt: false);
      },
    );
  }

  Future<void> _rewriteSelection() async {
    final text = _resultController.text;
    final selection = _resultController.selection;
    final valid = selection.isValid &&
        !selection.isCollapsed &&
        selection.start >= 0 &&
        selection.end <= text.length;

    if (!valid) {
      _showMessage('Маркирай редовете, които искаш да пренапишеш.');
      return;
    }

    final selected = text.substring(selection.start, selection.end);
    final start = selection.start;
    final end = selection.end;

    await _runAiTool(
      actionName: 'Пренаписвам избраното',
      instruction: '''
Пренапиши само избраните редове от българска рап песен.
Запази смисъла, броя редове и връзката с останалия текст.
Направи ги по-ритмични, с по-силни вътрешни рими и естествен български език.
Върни само новите редове, без заглавие и обяснение. Не използвай кръгли скоби и не добавяй музикални или вокални указания в текста.

ИЗБРАНИ РЕДОВЕ:
$selected

КОНТЕКСТ:
$text
''',
      applyResult: (result) {
        if (_resultController.text != text) {
          _showMessage(
            'Текстът е променен по време на редакцията. Опитай отново.',
          );
          return;
        }
        final cleanup = _cleanLyricsForSuno(result);
        _rememberSunoDirections(cleanup.directions);
        final replacement = cleanup.lyrics;
        final updated = text.replaceRange(start, end, replacement);
        _setResult(updated, musicPrompt: false, moveCursorToEnd: false);
        _resultController.selection = TextSelection(
          baseOffset: start,
          extentOffset: start + replacement.length,
        );
      },
    );
  }

  Future<void> _generateLocalPrompt() async {
    FocusScope.of(context).unfocus();
    _musicPromptController.text = _buildLocalPrompt();
    _excludeController.text = _buildExcludePrompt();
    await _persistStudioState();
    if (mounted) _showMessage('Style of Music и Exclude са подготвени.');
  }

  Future<void> _prepareSunoPackage() async {
    final source = _currentLyrics;
    if (source.isEmpty) {
      _showMessage('Първо добави или генерирай текст.');
      return;
    }

    final cleanup = _cleanLyricsForSuno(source);
    if (cleanup.lyrics.isEmpty) {
      _showMessage('След почистването не остана текст за Suno.');
      return;
    }

    _captureSnapshot();
    _rememberSunoDirections(cleanup.directions);
    _setResult(cleanup.lyrics, musicPrompt: false);
    _musicPromptController.text = _buildLocalPrompt();
    _excludeController.text = _buildExcludePrompt();
    await _persistStudioState();
    if (mounted) {
      _showMessage('Suno пакетът е готов: Lyrics, Style и Exclude.');
    }
  }

  void _showSavedPrompt() {
    final active = widget.store.activeSong;
    if (_musicPromptController.text.trim().isEmpty && active != null) {
      _musicPromptController.text = active.musicPrompt;
    }
    if (_excludeController.text.trim().isEmpty && active != null) {
      _excludeController.text = active.excludePrompt;
    }
    _showSunoPackageSheet();
  }

  String get _cleanCurrentLyrics {
    return _cleanLyricsForSuno(_currentLyrics).lyrics;
  }

  Future<void> _copyTextValue(String value, String message) async {
    final text = value.trim();
    if (text.isEmpty) {
      _showMessage('Полето е празно.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _showMessage(message);
  }

  Future<void> _copySunoPackage() async {
    final lyrics = _cleanCurrentLyrics;
    final style = _musicPromptController.text.trim().isNotEmpty
        ? _musicPromptController.text.trim()
        : _buildLocalPrompt();
    final exclude = _excludeController.text.trim().isNotEmpty
        ? _excludeController.text.trim()
        : _buildExcludePrompt();

    if (lyrics.isEmpty) {
      _showMessage('Няма текст за Suno.');
      return;
    }

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

  void _showSunoPackageSheet() {
    if (_musicPromptController.text.trim().isEmpty) {
      _musicPromptController.text = _buildLocalPrompt();
    }
    if (_excludeController.text.trim().isEmpty) {
      _excludeController.text = _buildExcludePrompt();
    }
    final lyrics = _cleanCurrentLyrics;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF06140A),
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.94,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Suno пакет',
                      style: TextStyle(
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
              const Text(
                'Поставяй трите части в отделните полета на Suno.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              IronCard(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '1. Lyrics / Текст',
                            style: TextStyle(
                              color: ironGreen,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Копирай Lyrics',
                          onPressed: () =>
                              _copyTextValue(lyrics, 'Lyrics са копирани.'),
                          icon: const Icon(Icons.copy, color: ironGreen),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12),
                    SelectableText(
                      lyrics.isEmpty ? 'Няма текст.' : lyrics,
                      style: const TextStyle(height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              IronInput(
                controller: _musicPromptController,
                label: '2. Style of Music',
                hint: 'Жанр, BPM, вокал, инструменти, атмосфера и микс',
                minLines: 5,
                maxLines: 10,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _copyTextValue(
                    _musicPromptController.text,
                    'Style of Music е копиран.',
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text('Копирай Style'),
                ),
              ),
              const SizedBox(height: 8),
              IronInput(
                controller: _excludeController,
                label: '3. Exclude',
                hint: 'Какво да не присъства в песента',
                minLines: 3,
                maxLines: 7,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _copyTextValue(
                    _excludeController.text,
                    'Exclude е копиран.',
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text('Копирай Exclude'),
                ),
              ),
              const SizedBox(height: 14),
              IronButton(
                text: 'Копирай целия пакет',
                icon: Icons.content_copy,
                onPressed: _copySunoPackage,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _sunoQualityIssues() {
    final lyrics = _cleanCurrentLyrics;
    final prompt = _musicPromptController.text.trim();
    final exclude = _excludeController.text.trim();
    final issues = <String>[];

    if (lyrics.isEmpty) {
      issues.add('Липсва текст за Lyrics.');
    } else {
      final words = lyrics
          .split(RegExp(r'\s+'))
          .where((item) => item.trim().isNotEmpty)
          .length;
      if (words < 50) issues.add('Текстът е много кратък ($words думи).');
      if (!RegExp(r'\[Припев', caseSensitive: false).hasMatch(lyrics)) {
        issues.add('Не е открита секция [Припев].');
      }
      if (RegExp(r'^\s*\(.+\)\s*$', multiLine: true).hasMatch(lyrics)) {
        issues.add('Има редове в кръгли скоби, които Suno може да изпее.');
      }
    }

    if (prompt.isEmpty) {
      issues.add('Липсва Style of Music.');
    } else {
      final lower = prompt.toLowerCase();
      const forbidden = <String>[
        'theme:',
        'keywords:',
        'lyrics / draft:',
        'generate original',
        'rhyme approach:',
        'structure:',
      ];
      if (forbidden.any((item) => lower.contains(item))) {
        issues.add(
          'Style of Music съдържа инструкции за текст, които трябва да се махнат.',
        );
      }
      if (prompt.length > 1000) {
        issues.add(
          'Style of Music е прекалено дълъг (${prompt.length} знака).',
        );
      }
    }

    if (exclude.isEmpty) issues.add('Полето Exclude е празно.');
    return issues;
  }

  void _showSunoQualityCheck() {
    final issues = _sunoQualityIssues();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          issues.isEmpty ? 'Готово за Suno' : 'Проверка на Suno пакета',
        ),
        content: SingleChildScrollView(
          child: issues.isEmpty
              ? const Text(
                  'Lyrics, Style of Music и Exclude са разделени правилно.',
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final issue in issues)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.amber,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(issue)),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Затвори'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _prepareSunoPackage();
            },
            child: const Text('Поправи автоматично'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateTitleWithAi() async {
    final apiKey = widget.store.apiKey.trim();
    final lyrics = _currentLyrics;
    if (!widget.store.hasAnyAiProvider) {
      _showMessage('Първо добави Gemini или резервен AI доставчик в раздел „AI“.');
      return;
    }
    if (lyrics.isEmpty) {
      _showMessage('Първо добави текст.');
      return;
    }

    setState(() {
      _isLoading = true;
      _activeAction = 'Измислям заглавие';
    });
    try {
      final excerpt = lyrics.length > 3500 ? lyrics.substring(0, 3500) : lyrics;
      final result = await _gemini.generateRap(
        apiKey: apiKey,
        instruction: '''
Измисли едно силно, кратко и оригинално заглавие на български за тази рап песен.
Върни само заглавието без кавички, обяснения, номерация или допълнителен текст.

$excerpt
''',
      );
      final title = cleanMarkdownForDisplay(
        result,
      ).split('\n').first.replaceAll(RegExp(r'^["„“]+|["„“]+$'), '').trim();
      if (title.isNotEmpty) {
        _titleController.text = title;
        await _persistStudioState();
        if (mounted) _showMessage('Заглавието е готово.');
      }
    } on GeminiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Не успях да генерирам заглавие.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _activeAction = '';
        });
      }
    }
  }

  Future<void> _improveSunoPromptWithAi() async {
    final apiKey = widget.store.apiKey.trim();
    if (!widget.store.hasAnyAiProvider) {
      _showMessage('Първо добави Gemini или резервен AI доставчик в раздел „AI“.');
      return;
    }

    final lyrics = _cleanCurrentLyrics;
    setState(() {
      _isLoading = true;
      _activeAction = 'Подобрявам Suno пакета';
    });
    try {
      final excerpt = lyrics.length > 2500 ? lyrics.substring(0, 2500) : lyrics;
      final response = await _gemini.generateRap(
        apiKey: apiKey,
        instruction: '''
Създай кратък професионален Suno пакет за българска рап песен.
Върни точно две секции в този формат:
STYLE:
един английски абзац само за музикалния стил — жанр, $_bpm BPM, барабани, бас, инструменти, нисък естествен мъжки вокал, динамика, атмосфера и микс.
EXCLUDE:
кратък английски списък, разделен със запетаи, с нежелани елементи.

Не добавяй Theme, Keywords, Structure, Lyrics, инструкции за генериране на текст или имена на известни изпълнители.
Стил: $_style
Настроение: $_mood
Тема: ${_themeController.text.trim()}
Текст за контекст:
$excerpt
''',
      );

      final cleanedResponse = cleanMarkdownForDisplay(response);
      final styleMatch = RegExp(
        r'STYLE:\s*([\s\S]*?)(?:\n\s*EXCLUDE:|$)',
        caseSensitive: false,
      ).firstMatch(cleanedResponse);
      final excludeMatch = RegExp(
        r'EXCLUDE:\s*([\s\S]*)$',
        caseSensitive: false,
      ).firstMatch(cleanedResponse);

      final style = styleMatch?.group(1)?.trim() ?? '';
      final exclude = excludeMatch?.group(1)?.trim() ?? '';
      _musicPromptController.text = style.isEmpty ? _buildLocalPrompt() : style;
      _excludeController.text =
          exclude.isEmpty ? _buildExcludePrompt() : exclude;
      await _persistStudioState();
      if (mounted) _showMessage('AI подобри Style of Music и Exclude.');
    } on GeminiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Не успях да подобря Suno пакета.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _activeAction = '';
        });
      }
    }
  }

  Future<void> _copyResult() async {
    if (_resultController.text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _resultController.text));
    if (mounted) _showMessage('Резултатът е копиран.');
  }

  Future<void> _moveResultToDraft() async {
    if (_resultController.text.trim().isEmpty) return;
    _draftController.text = _resultController.text;
    _draftController.selection = TextSelection.collapsed(
      offset: _draftController.text.length,
    );
    await _persistStudioState();
    if (mounted) _showMessage('Резултатът е преместен в черновата.');
  }

  String _safeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^a-zA-Z0-9а-яА-Я_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'iron_music_song' : cleaned;
  }

  SongProject _buildProject(String title) {
    final existing = widget.store.activeSong;
    final rawLyrics = _resultController.text.trim().isNotEmpty
        ? _resultController.text.trim()
        : _draftController.text.trim();
    final cleanup = _cleanLyricsForSuno(rawLyrics);
    _rememberSunoDirections(cleanup.directions);

    final lyrics = cleanup.lyrics;
    final prompt = _appendDirectionsToPrompt(
      _musicPromptController.text.trim().isNotEmpty
          ? _musicPromptController.text.trim()
          : _buildLocalPrompt(),
    );
    final exclude = _excludeController.text.trim().isNotEmpty
        ? _excludeController.text.trim()
        : _buildExcludePrompt();

    if (existing != null) {
      return existing.copyWith(
        title: title,
        lyrics: lyrics,
        musicPrompt: prompt,
        excludePrompt: exclude,
        theme: _themeController.text,
        keywords: _keywordsController.text,
        style: _style,
        mood: _mood,
        rhymeScheme: _rhymeScheme,
        outputType: _outputType,
        bpm: _bpm,
      );
    }

    return SongProject.create(
      title: title,
      lyrics: lyrics,
      musicPrompt: prompt,
      excludePrompt: exclude,
      theme: _themeController.text,
      keywords: _keywordsController.text,
      style: _style,
      mood: _mood,
      rhymeScheme: _rhymeScheme,
      outputType: _outputType,
      bpm: _bpm,
    );
  }

  Future<String?> _askForTitle() async {
    final suggested = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : (_themeController.text.trim().isNotEmpty
            ? _themeController.text.trim()
            : 'Нова песен');
    final controller = TextEditingController(text: suggested);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Запази песента'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Заглавие',
            hintText: 'Име на песента',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отказ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim().isEmpty
                  ? 'Нова песен'
                  : controller.text.trim(),
            ),
            child: const Text('Запази'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _saveProject() async {
    if (_draftController.text.trim().isEmpty &&
        _resultController.text.trim().isEmpty) {
      _showMessage('Добави чернова или генерирай резултат.');
      return;
    }

    final active = widget.store.activeSong;
    String? title;
    if (active != null && _titleController.text.trim().isNotEmpty) {
      title = _titleController.text.trim();
    } else {
      title = await _askForTitle();
    }
    if (title == null || !mounted) return;

    final project = _buildProject(title);
    await widget.store.upsertSong(project);
    _restoring = true;
    _titleController.text = project.title;
    _restoring = false;
    if (mounted) {
      setState(() => _saveStatus = 'Запазено ${_timeLabel()}');
      _showMessage('Песента е запазена в „Моите песни“.');
    }
  }

  Future<void> _exportCurrent() async {
    if (_draftController.text.trim().isEmpty &&
        _resultController.text.trim().isEmpty) {
      _showMessage('Няма съдържание за експорт.');
      return;
    }
    final title = _titleController.text.trim().isEmpty
        ? 'Iron Music песен'
        : _titleController.text.trim();
    final project = _buildProject(title);
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(
            utf8.encode(project.exportText),
            mimeType: 'text/plain',
          ),
        ],
        text: project.title,
        subject: 'Iron Music 420 AI — ${project.title}',
        fileNameOverrides: ['${_safeFileName(project.title)}.txt'],
      );
    } catch (_) {
      if (mounted) {
        _showMessage('Експортът не стартира. Използвай „Копирай“.');
      }
    }
  }

  Future<void> _clearStudio() async {
    FocusScope.of(context).unfocus();
    _saveTimer?.cancel();
    await widget.store.startNewStudioProject();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
      dropdownColor: ironPanelRaised,
      iconEnabledColor: ironGreen,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: ironGreen,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: const Color(0xFF010A05).withOpacity(0.94),
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

  Widget _toolButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        foregroundColor: ironGreen,
        backgroundColor: ironGreen.withOpacity(0.035),
        side: BorderSide(color: ironGreen.withOpacity(0.48)),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  int get _wordCount {
    final text = _resultController.text.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).where((item) => item.isNotEmpty).length;
  }

  @override
  Widget build(BuildContext context) {
    final activeSong = widget.store.activeSong;
    final hasResult = _resultController.text.trim().isNotEmpty;

    return IronBackground(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: [
          PageTitle(
            eyebrow: 'IRON STUDIO',
            title: 'Rap Studio',
            subtitle: activeSong == null
                ? 'Напиши идея и натисни „Създай“'
                : activeSong.title,
            trailing: IconButton(
              tooltip: 'Нов проект',
              onPressed: _isLoading ? null : _clearStudio,
              icon: const Icon(Icons.note_add_outlined, color: ironGreen),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                _saveStatus.startsWith('Незапазени')
                    ? Icons.edit_outlined
                    : Icons.cloud_done_outlined,
                color: _saveStatus.startsWith('Незапазени')
                    ? Colors.amber
                    : ironGreen,
                size: 18,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _saveStatus,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
              if (activeSong?.musicPrompt.trim().isNotEmpty == true ||
                  activeSong?.excludePrompt.trim().isNotEmpty == true)
                TextButton.icon(
                  onPressed: _isLoading ? null : _showSavedPrompt,
                  icon: const Icon(Icons.music_note, size: 17),
                  label: const Text('Suno'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          IronInput(
            controller: _titleController,
            label: 'Заглавие',
            hint: 'Име на песента',
            icon: Icons.title,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _isLoading ? null : _generateTitleWithAi,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('AI заглавие'),
            ),
          ),
          const SizedBox(height: 2),
          IronInput(
            controller: _draftController,
            label: 'Текст или идея',
            hint: 'Напиши няколко реда или постави готов текст',
            icon: Icons.edit_note,
            minLines: 8,
            maxLines: 18,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _dropdown(
                  label: 'Стил',
                  value: _style,
                  items: _styles,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _style = value);
                    _markOptionChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dropdown(
                  label: 'Резултат',
                  value: _outputType,
                  items: _outputTypes,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _outputType = value);
                    _markOptionChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          IronButton(
            text: _isLoading ? _activeAction : 'Създай с AI',
            icon: Icons.auto_awesome,
            onPressed: _isLoading ? null : _generateWithAi,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: IronButton(
                  text: 'Suno',
                  icon: Icons.library_music_outlined,
                  secondary: true,
                  compact: true,
                  onPressed: _isLoading || _currentLyrics.isEmpty
                      ? null
                      : _showSunoPackageSheet,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: IronButton(
                  text: 'Запази',
                  icon: Icons.save,
                  compact: true,
                  onPressed: _isLoading ? null : _saveProject,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _isLoading ? null : _exportCurrent,
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('Сподели TXT'),
            ),
          ),
          const SizedBox(height: 4),
          IronCard(
            margin: EdgeInsets.zero,
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.tune, color: ironGreen),
              title: const Text(
                'Още настройки',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('$_bpm BPM • $_mood'),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                IronInput(
                  controller: _themeController,
                  label: 'Тема',
                  hint: 'Например: от дъното до върха',
                  icon: Icons.lightbulb_outline,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                _dropdown(
                  label: 'Настроение',
                  value: _mood,
                  items: _moods,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _mood = value);
                    _markOptionChanged();
                  },
                ),
                const SizedBox(height: 12),
                _dropdown(
                  label: 'Рими',
                  value: _rhymeScheme,
                  items: _rhymeSchemes,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _rhymeScheme = value);
                    _markOptionChanged();
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.speed, color: ironGreen),
                    const SizedBox(width: 8),
                    Text(
                      'Темпо: $_bpm BPM',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Slider(
                  value: _bpm.toDouble(),
                  min: 70,
                  max: 190,
                  divisions: 24,
                  label: '$_bpm BPM',
                  onChanged: (value) {
                    setState(() => _bpm = value.round());
                    _markOptionChanged();
                  },
                ),
                IronInput(
                  controller: _keywordsController,
                  label: 'Ключови думи',
                  hint: 'болка, победа, вярност',
                  icon: Icons.tag,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          IronCard(
            margin: EdgeInsets.zero,
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.auto_fix_high, color: ironGreen),
              title: const Text(
                'AI инструменти',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _toolButton(
                      label: 'Продължи',
                      icon: Icons.add_to_photos_outlined,
                      onPressed: _continueText,
                    ),
                    _toolButton(
                      label: 'Припев',
                      icon: Icons.repeat,
                      onPressed: _createHook,
                    ),
                    _toolButton(
                      label: 'Стегни римите',
                      icon: Icons.auto_fix_high,
                      onPressed: _tightenRhymes,
                    ),
                    _toolButton(
                      label: 'Пренапиши',
                      icon: Icons.edit_note,
                      onPressed: _rewriteSelection,
                    ),
                    _toolButton(
                      label: 'Изчисти за Suno',
                      icon: Icons.cleaning_services_outlined,
                      onPressed: _cleanCurrentLyricsForSuno,
                    ),
                    _toolButton(
                      label: 'Направи Style',
                      icon: Icons.tune,
                      onPressed: _generateLocalPrompt,
                    ),
                    _toolButton(
                      label: 'Подобри Style',
                      icon: Icons.auto_awesome,
                      onPressed: _improveSunoPromptWithAi,
                    ),
                    _toolButton(
                      label: 'Провери Suno',
                      icon: Icons.fact_check_outlined,
                      onPressed: _showSunoQualityCheck,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(color: ironGreen),
          ],
          if (hasResult) ...[
            const SizedBox(height: 16),
            IronCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Резултат',
                              style: TextStyle(
                                color: ironGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$_wordCount думи',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Назад',
                        onPressed: _undoStack.isEmpty ? null : _undoResult,
                        icon: const Icon(Icons.undo, color: ironGreen),
                      ),
                      IconButton(
                        tooltip: 'Напред',
                        onPressed: _redoStack.isEmpty ? null : _redoResult,
                        icon: const Icon(Icons.redo, color: ironGreen),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: ironGreen),
                        onSelected: (value) {
                          if (value == 'draft') _moveResultToDraft();
                          if (value == 'copy') _copyResult();
                          if (value == 'copy_clean') {
                            _copyCleanLyricsForSuno();
                          }
                          if (value == 'prompt') _showSavedPrompt();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'draft',
                            child: Text('Премести в текста'),
                          ),
                          const PopupMenuItem(
                            value: 'copy',
                            child: Text('Копирай'),
                          ),
                          const PopupMenuItem(
                            value: 'copy_clean',
                            child: Text('Копирай за Suno'),
                          ),
                          if (_musicPromptController.text.trim().isNotEmpty ||
                              _excludeController.text.trim().isNotEmpty)
                            const PopupMenuItem(
                              value: 'prompt',
                              child: Text('Suno пакет'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  TextField(
                    controller: _resultController,
                    minLines: 12,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(height: 1.45, color: Colors.white),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Резултатът ще се появи тук…',
                      hintStyle: TextStyle(color: Colors.white38),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyResult,
                          icon: const Icon(Icons.copy),
                          label: const Text('Копирай'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _showSunoPackageSheet,
                          icon: const Icon(Icons.music_note),
                          label: const Text('Suno'),
                        ),
                      ),
                    ],
                  ),
                  if (_gemini.activeModel != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Модел: ${_gemini.activeModel}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
