from pathlib import Path
import re

RAP = Path('lib/pages/rap_studio_page.dart')
PUBSPEC = Path('pubspec.yaml')

text = RAP.read_text(encoding='utf-8')
pubspec = PUBSPEC.read_text(encoding='utf-8')

# Track which Suno fields are still auto-managed. Manual edits are preserved.
old = """  final List<String> _sunoDirections = <String>[];
  late int _loadedRevision;
"""
new = """  final List<String> _sunoDirections = <String>[];
  String _lastAutoMusicPrompt = '';
  String _lastAutoExcludePrompt = '';
  bool _updatingAutoSunoFields = false;
  late int _loadedRevision;
"""
if old not in text:
    raise RuntimeError('state marker not found')
text = text.replace(old, new, 1)

old = """    _excludeController = TextEditingController(
      text: activeSong?.excludePrompt ?? '',
    );
    _loadedRevision = widget.store.studioRevision;
"""
new = """    _excludeController = TextEditingController(
      text: activeSong?.excludePrompt ?? '',
    );
    _lastAutoMusicPrompt = _musicPromptController.text.trim();
    _lastAutoExcludePrompt = _excludeController.text.trim();
    _loadedRevision = widget.store.studioRevision;
"""
if old not in text:
    raise RuntimeError('init prompt tracker marker not found')
text = text.replace(old, new, 1)

old = """    });
    _restoring = false;
    _applyPendingStudioVoiceRequest();
  }

  void _applyPendingStudioVoiceRequest() {
"""
new = """    });
    _lastAutoMusicPrompt = _musicPromptController.text.trim();
    _lastAutoExcludePrompt = _excludeController.text.trim();
    _restoring = false;
    _applyPendingStudioVoiceRequest();
  }

  void _applyPendingStudioVoiceRequest() {
"""
if old not in text:
    raise RuntimeError('store restore tracker marker not found')
text = text.replace(old, new, 1)

pattern = re.compile(
    r"  void _markChanged\(\) \{.*?\n  \}\n\n  void _markOptionChanged\(\) \{.*?\n  \}\n",
    re.S,
)
replacement = r'''  void _refreshSunoFields({bool force = false}) {
    if (_updatingAutoSunoFields) return;

    final currentMusic = _musicPromptController.text.trim();
    final currentExclude = _excludeController.text.trim();
    final canReplaceMusic = force ||
        currentMusic.isEmpty ||
        currentMusic == _lastAutoMusicPrompt.trim();
    final canReplaceExclude = force ||
        currentExclude.isEmpty ||
        currentExclude == _lastAutoExcludePrompt.trim();

    if (!canReplaceMusic && !canReplaceExclude) return;

    final nextMusic = _buildLocalPrompt();
    final nextExclude = _buildExcludePrompt();
    _updatingAutoSunoFields = true;
    try {
      if (canReplaceMusic) {
        _musicPromptController.text = nextMusic;
        _lastAutoMusicPrompt = nextMusic;
      }
      if (canReplaceExclude) {
        _excludeController.text = nextExclude;
        _lastAutoExcludePrompt = nextExclude;
      }
    } finally {
      _updatingAutoSunoFields = false;
    }
  }

  void _markChanged() {
    if (_restoring || _updatingAutoSunoFields || !mounted) return;
    _refreshSunoFields();
    setState(() => _saveStatus = 'Незапазени промени');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), () {
      _persistStudioState();
    });
  }

  void _markOptionChanged() {
    if (!mounted) return;
    _refreshSunoFields();
    setState(() => _saveStatus = 'Незапазени промени');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), () {
      _persistStudioState();
    });
  }
'''
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise RuntimeError(f'mark changed block replacement count={count}')

pattern = re.compile(
    r"  String _buildLocalPrompt\(\) \{.*?\n  \}\n\n  String _buildExcludePrompt\(\) \{.*?\n  \}\n\n  _SunoLyricsCleanup _cleanLyricsForSuno",
    re.S,
)
replacement = r'''  String _compactPromptContext(String value, {int maxWords = 18}) {
    final cleaned = value
        .replaceAll(RegExp(r'\[[^\]]+\]'), ' ')
        .replaceAll(RegExp(r'[()\r\n,;:]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('"', '')
        .trim();
    if (cleaned.isEmpty) return '';
    final words = cleaned.split(' ');
    if (words.length <= maxWords) return cleaned;
    return words.take(maxWords).join(' ');
  }

  String _tempoDescriptor() {
    if (_bpm >= 165) {
      return 'high-energy double-time pocket, rapid hi-hat motion and tight short transitions';
    }
    if (_bpm >= 140) {
      return 'driving modern rap pocket, energetic drums and controlled half-time weight';
    }
    if (_bpm >= 110) {
      return 'mid-tempo head-nod groove with clear space between kick and snare';
    }
    return 'slow heavy pocket, spacious drum placement and long low-end sustain';
  }

  String _structureDescriptor() {
    return switch (_outputType) {
      'Куплет' =>
        'verse-forward arrangement with breathing room for dense bars and internal rhymes',
      'Припев' =>
        'hook-forward arrangement with an immediate memorable chorus lift and strong repeat point',
      'Рими и punchlines' =>
        'sparse punchline-focused arrangement with short gaps after key bars',
      'Редактирай черновата' =>
        'preserve the existing song arc while tightening transitions and dynamics',
      _ =>
        'full song arc with intro tension, two distinct verses, a bigger hook and a resolved outro',
    };
  }

  String _vocalDescriptor() {
    return switch (_mood) {
      'Емоционално' =>
        'deep natural Bulgarian male rap vocal, intimate chest tone, controlled rasp and emotional restraint',
      'Мотивиращо' =>
        'deep confident Bulgarian male rap vocal, forward projection and victorious hook delivery',
      'Спокойно и дълбоко' =>
        'low warm Bulgarian male rap vocal, calm close-mic delivery and reflective phrasing',
      _ =>
        'deep natural Bulgarian male rap vocal, firm chest voice, aggressive articulation and precise diction',
    };
  }

  String _buildLocalPrompt() {
    final theme = _compactPromptContext(_themeController.text.trim());
    final keywords = _compactPromptContext(
      _keywordsController.text.trim(),
      maxWords: 12,
    );
    final lyricSeed = _compactPromptContext(_currentLyrics, maxWords: 16);
    final title = _compactPromptContext(_titleController.text.trim(), maxWords: 8);
    final concept = theme.isNotEmpty
        ? theme
        : (keywords.isNotEmpty
            ? keywords
            : (lyricSeed.isNotEmpty
                ? lyricSeed
                : 'struggle ambition pressure loyalty and victory'));

    final parts = <String>[
      '${_styleDescriptor()} at $_bpm BPM',
      _moodDescriptor(),
      _tempoDescriptor(),
      _structureDescriptor(),
      _vocalDescriptor(),
      'song concept: $concept',
      if (title.isNotEmpty) 'title mood cue: $title',
      if (keywords.isNotEmpty) 'lyrical imagery: $keywords',
      'strong verse-to-hook contrast',
      'restrained autotune unless the selected style needs melody',
      'wide but controlled ad-libs',
      'clean modern mix with clear vocal separation',
      'powerful controlled low end without masking the Bulgarian vocal',
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
      'cheerful generic pop melody',
      'comedy delivery',
      'soft weak drums',
      'muddy mix',
      'harsh clipping',
      'spoken production notes',
      'singing bracket instructions',
      'generic stock beat feel',
    ];

    if (_style != 'Melodic trap' && _style != 'Trap soul') {
      exclusions.addAll(['excessive autotune', 'pop chorus']);
    }
    if (_style != 'Drill') exclusions.add('drill sirens');
    if (_style != 'Post-rock rap') exclusions.add('rock guitar solo');
    if (_bpm >= 160) exclusions.add('slow lethargic pacing');
    if (_outputType == 'Припев') exclusions.add('weak indistinct hook');
    if (_mood == 'Тъмно и агресивно') exclusions.add('soft sleepy delivery');
    if (_mood == 'Спокойно и дълбоко') exclusions.add('constant shouting');

    return exclusions.join(', ');
  }

  _SunoLyricsCleanup _cleanLyricsForSuno'''
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise RuntimeError(f'prompt builder replacement count={count}')

old = """      _setResult(cleanup.lyrics, musicPrompt: false);
      if (_musicPromptController.text.trim().isEmpty) {
        _musicPromptController.text = _buildLocalPrompt();
      }
      if (_excludeController.text.trim().isEmpty) {
        _excludeController.text = _buildExcludePrompt();
      }
      await _persistStudioState();
"""
new = """      _setResult(cleanup.lyrics, musicPrompt: false);
      _refreshSunoFields(force: true);
      await _persistStudioState();
"""
if old not in text:
    raise RuntimeError('generateWithAi Suno refresh marker not found')
text = text.replace(old, new, 1)

old = """    try {
      final result = await _gemini.generateRap(
        apiKey: apiKey,
        instruction: instruction,
      );
      if (!mounted) return;
      _captureSnapshot();
      applyResult(result);
      await _persistStudioState();
"""
new = """    final beforeLyrics = _currentLyrics;
    try {
      final result = await _gemini.generateRap(
        apiKey: apiKey,
        instruction: instruction,
      );
      if (!mounted) return;
      final cleanResult = result.trim();
      if (cleanResult.isEmpty) {
        _showMessage('AI върна празен резултат. Опитай отново.');
        return;
      }
      _captureSnapshot();
      applyResult(cleanResult);
      final changed = _currentLyrics != beforeLyrics;
      _refreshSunoFields(force: true);
      await _persistStudioState();
      if (mounted) {
        _showMessage(
          changed
              ? '$actionName — готово. Suno Style е обновен.'
              : 'AI не промени текста. Опитай функцията отново.',
        );
      }
"""
if old not in text:
    raise RuntimeError('runAiTool marker not found')
text = text.replace(old, new, 1)

old = """  Future<void> _createHook() async {
    final current = _currentLyrics;
    if (current.isEmpty) {
      _showMessage('Първо добави текст или тема.');
      return;
    }

    await _runAiTool(
"""
new = """  Future<void> _createHook() async {
    final current = _currentLyrics;
    final theme = _themeController.text.trim();
    if (current.isEmpty && theme.isEmpty) {
      _showMessage('Първо добави текст или тема.');
      return;
    }
    final hookContext = current.isNotEmpty
        ? current
        : 'Тема: $theme. Ключови думи: ${_keywordsController.text.trim()}. '
            'Стил: $_style. Настроение: $_mood.';

    await _runAiTool(
"""
if old not in text:
    raise RuntimeError('createHook guard marker not found')
text = text.replace(old, new, 1)

old = """КОНТЕКСТ НА ПЕСЕНТА:
$current
''',
      applyResult: (result) {
"""
new = """КОНТЕКСТ НА ПЕСЕНТА:
$hookContext
''',
      applyResult: (result) {
"""
if old not in text:
    raise RuntimeError('createHook context marker not found')
text = text.replace(old, new, 1)

old = """  Future<void> _generateLocalPrompt() async {
    FocusScope.of(context).unfocus();
    _musicPromptController.text = _buildLocalPrompt();
    _excludeController.text = _buildExcludePrompt();
    await _persistStudioState();
    if (mounted) _showMessage('Style of Music и Exclude са подготвени.');
  }
"""
new = """  Future<void> _generateLocalPrompt() async {
    FocusScope.of(context).unfocus();
    _refreshSunoFields(force: true);
    await _persistStudioState();
    if (mounted) {
      _showMessage('Нов Style of Music е направен от текущия текст и настройки.');
    }
  }
"""
if old not in text:
    raise RuntimeError('generateLocalPrompt marker not found')
text = text.replace(old, new, 1)

old = """    _captureSnapshot();
    _rememberSunoDirections(cleanup.directions);
    _setResult(cleanup.lyrics, musicPrompt: false);
    _musicPromptController.text = _buildLocalPrompt();
    _excludeController.text = _buildExcludePrompt();
    await _persistStudioState();
"""
new = """    _captureSnapshot();
    _rememberSunoDirections(cleanup.directions);
    _setResult(cleanup.lyrics, musicPrompt: false);
    _refreshSunoFields(force: true);
    await _persistStudioState();
"""
if old not in text:
    raise RuntimeError('prepareSunoPackage marker not found')
text = text.replace(old, new, 1)

old = """  void _showSunoPackageSheet() {
    if (_musicPromptController.text.trim().isEmpty) {
"""
new = """  void _showSunoPackageSheet() {
    _refreshSunoFields();
    if (_musicPromptController.text.trim().isEmpty) {
"""
if old not in text:
    raise RuntimeError('showSunoPackageSheet marker not found')
text = text.replace(old, new, 1)

old = """    final lyrics = _cleanCurrentLyrics;
    setState(() {
      _isLoading = true;
      _activeAction = 'Подобрявам Suno пакета';
    });
    try {
      final excerpt = lyrics.length > 2500 ? lyrics.substring(0, 2500) : lyrics;
      final response = await _gemini.generateRap(
"""
new = """    final lyrics = _cleanCurrentLyrics;
    final localStyle = _buildLocalPrompt();
    final localExclude = _buildExcludePrompt();
    setState(() {
      _isLoading = true;
      _activeAction = 'Подобрявам Suno пакета';
    });
    try {
      final excerpt = lyrics.length > 2500 ? lyrics.substring(0, 2500) : lyrics;
      final response = await _gemini.generateRap(
"""
if old not in text:
    raise RuntimeError('improve prompt local baseline marker not found')
text = text.replace(old, new, 1)

old = """Тема: ${_themeController.text.trim()}
Текст за контекст:
$excerpt
''',
"""
new = """Тема: ${_themeController.text.trim()}
Ключови думи: ${_keywordsController.text.trim()}
Текущ локален Style за надграждане:
$localStyle
Текущ Exclude:
$localExclude
Текст за контекст:
$excerpt

Направи STYLE конкретен за точно тази песен. Не връщай общ шаблон и не повтаряй дословно локалния Style.
''',
"""
if old not in text:
    raise RuntimeError('improve prompt instruction marker not found')
text = text.replace(old, new, 1)

old = """      _musicPromptController.text = style.isEmpty ? _buildLocalPrompt() : style;
      _excludeController.text =
          exclude.isEmpty ? _buildExcludePrompt() : exclude;
      await _persistStudioState();
"""
new = """      _musicPromptController.text = style.isEmpty ? localStyle : style;
      _excludeController.text = exclude.isEmpty ? localExclude : exclude;
      _lastAutoMusicPrompt = _musicPromptController.text.trim();
      _lastAutoExcludePrompt = _excludeController.text.trim();
      await _persistStudioState();
"""
if old not in text:
    raise RuntimeError('improve prompt apply marker not found')
text = text.replace(old, new, 1)

old_version = 'version: 3.4.0+68'
new_version = 'version: 3.4.0+69'
if old_version not in pubspec:
    raise RuntimeError('expected build 68 version not found')
pubspec = pubspec.replace(old_version, new_version, 1)

RAP.write_text(text, encoding='utf-8')
PUBSPEC.write_text(pubspec, encoding='utf-8')
print('Applied build 69 Rap Studio fix: dynamic Suno prompts, working hook theme mode, visible AI tool results.')
