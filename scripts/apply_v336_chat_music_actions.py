from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:160]!r}")
    file_path.write_text(text.replace(old, new, 1), encoding="utf-8")


chat = "lib/pages/chat_page.dart"

replace_once(
    chat,
    "import '../models/chat_message.dart';\n",
    "import '../models/chat_message.dart';\nimport '../models/song_project.dart';\n",
)

replace_once(
    chat,
    '''  Future<void> _syncNativeAiSettings() {
''',
    '''  String? _detectMusicCommand(String value) {
    final text = value.toLowerCase();
    final refersToExisting = text.contains('го') ||
        text.contains('това') ||
        text.contains('текста') ||
        text.contains('песента') ||
        text.contains('последн');
    if (!refersToExisting) return null;

    if (text.contains('запази') &&
        (text.contains('песен') || text.contains('моите песни'))) {
      return 'save';
    }
    if (text.contains('анализ')) return 'analyze';
    if (text.contains('припев') || text.contains('рефрен')) return 'hook';
    if (text.contains('музикален промпт') ||
        text.contains('suno промпт') ||
        text.contains('стил за suno') ||
        text.contains('бийт промпт')) {
      return 'music_prompt';
    }
    if ((text.contains('стегни') ||
            text.contains('подобри') ||
            text.contains('оправи') ||
            text.contains('преработи')) &&
        (text.contains('рим') || text.contains('текст'))) {
      return 'improve';
    }
    return null;
  }

  String _songTitleFromText(String value) {
    final lines = cleanMarkdownForDisplay(value)
        .split('\\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('['))
        .toList();
    if (lines.isEmpty) return 'Iron Chat песен';

    final words = lines.first
        .replaceAll(RegExp(r'^[#>*\\-\\s]+'), '')
        .split(RegExp(r'\\s+'))
        .where((word) => word.isNotEmpty)
        .take(7)
        .join(' ')
        .replaceAll(RegExp(r'[,:;.!?]+$'), '')
        .trim();
    return words.isEmpty ? 'Iron Chat песен' : words;
  }

  Future<void> _saveChatTextAsSong(String sourceText) async {
    final cleanText = cleanMarkdownForDisplay(sourceText).trim();
    if (cleanText.isEmpty) {
      _showMessage('Няма текст за запазване.');
      return;
    }

    final project = SongProject.create(
      title: _songTitleFromText(cleanText),
      lyrics: cleanText,
      musicPrompt: '',
      theme: '',
      style: 'Hard trap',
      mood: 'Тъмно и агресивно',
      rhymeScheme: 'Многосрични рими',
      bpm: 140,
    );
    await widget.store.upsertSong(project);
    await widget.store.loadSongIntoStudio(project);
    if (mounted) {
      _showMessage('Песента е запазена в „Моите песни“.');
    }
  }

  Future<void> _appendAssistantMusicResult(String result) async {
    final cleanResult = result.trim();
    if (cleanResult.isEmpty || !mounted) return;
    final message = ChatMessage(
      text: cleanResult,
      isUser: false,
      createdAt: DateTime.now(),
    );
    setState(() => _messages.add(message));
    await widget.store.replaceChatHistory(_messages);
    _scrollToBottom();
    await _speak(cleanResult);
  }

  Future<void> _runChatMusicAction(String action, String sourceText) async {
    final cleanText = cleanMarkdownForDisplay(sourceText).trim();
    if (cleanText.isEmpty || _isLoading) return;

    if (action == 'studio') {
      await _sendTextToStudio(cleanText);
      return;
    }
    if (action == 'save') {
      await _saveChatTextAsSong(cleanText);
      return;
    }
    if (!widget.store.hasAnyAiProvider) {
      await _openApiKeySheet();
      return;
    }

    final excerpt = cleanText.length > 12000
        ? cleanText.substring(0, 12000)
        : cleanText;
    final instruction = switch (action) {
      'hook' => '''
Напиши силен оригинален български рап припев от 6 до 8 реда за текста по-долу.
Да е лесен за запомняне, ритмичен и подходящ за повторение.
Върни само секция [Припев], без обяснения и без указания в кръгли скоби.

ТЕКСТ:
$excerpt
''',
      'improve' => '''
Преработи целия български рап текст професионално.
Запази смисъла, историята и личния тон, но подобри ритъма, вътрешните и многосричните рими, punchline-ите и слабите повторения.
Върни целия завършен редактиран текст без обяснения и без указания в кръгли скоби.

ОРИГИНАЛ:
$excerpt
''',
      'analyze' => '''
Анализирай следния български рап текст практично и конкретно.
Дай кратки секции: тема и послание, структура, ритъм и flow, рими, най-силни редове, слаби места и точни следващи поправки.
Не пренаписвай целия текст.

ТЕКСТ:
$excerpt
''',
      'music_prompt' => '''
Създай професионален пакет за Suno за текста по-долу.
Върни точно:
STYLE OF MUSIC:
кратък английски промпт за жанр, BPM, барабани, бас, инструменти, нисък естествен мъжки вокал, атмосфера и микс.
EXCLUDE:
кратък английски списък с нежелани елементи.
Не добавяй текст на песента и не използвай имена на известни изпълнители.

ТЕКСТ:
$excerpt
''',
      _ => '',
    };
    if (instruction.isEmpty) return;

    setState(() => _isLoading = true);
    _scrollToBottom();
    try {
      final result = await _gemini.generateRap(
        apiKey: widget.store.apiKey.trim(),
        instruction: instruction,
      );
      await _appendAssistantMusicResult(result);
    } on GeminiException catch (error) {
      if (mounted) await _addLocalNotice(error.message);
    } catch (_) {
      if (mounted) {
        await _addLocalNotice('Неочаквана грешка при музикалната AI команда.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _syncNativeAiSettings() {
''',
)

replace_once(
    chat,
    '''    final apiKey = widget.store.apiKey.trim();
    if (!widget.store.hasAnyAiProvider) {
''',
    '''    final musicCommand = _detectMusicCommand(text);
    if (musicCommand != null) {
      final previous = _lastAssistantMessage();
      _messageController.clear();
      if (previous == null) {
        _showMessage('Първо нека напиша текст, върху който да работя.');
        return;
      }
      await _runChatMusicAction(musicCommand, previous.text);
      return;
    }

    final apiKey = widget.store.apiKey.trim();
    if (!widget.store.hasAnyAiProvider) {
''',
)

replace_once(
    chat,
    '''                return _ChatBubble(
                  message: message,
                  onSendToStudio: !message.isUser && !message.isLocalNotice
                      ? () => _sendTextToStudio(message.text)
                      : null,
                );
''',
    '''                return _ChatBubble(
                  message: message,
                  onSendToStudio: !message.isUser && !message.isLocalNotice
                      ? () => _sendTextToStudio(message.text)
                      : null,
                  onMusicAction: !message.isUser && !message.isLocalNotice
                      ? (action) => _runChatMusicAction(action, message.text)
                      : null,
                );
''',
)

replace_once(
    chat,
    '''class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onSendToStudio;

  const _ChatBubble({
    required this.message,
    this.onSendToStudio,
  });
''',
    '''class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onSendToStudio;
  final ValueChanged<String>? onMusicAction;

  const _ChatBubble({
    required this.message,
    this.onSendToStudio,
    this.onMusicAction,
  });
''',
)

replace_once(
    chat,
    '''                  const SizedBox(width: 3),
                ],
                InkWell(
''',
    '''                  const SizedBox(width: 3),
                ],
                if (onMusicAction != null)
                  PopupMenuButton<String>(
                    tooltip: 'Музикални действия',
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 17,
                      color: ironGreen,
                    ),
                    onSelected: onMusicAction,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'improve',
                        child: Text('Стегни римите'),
                      ),
                      PopupMenuItem(
                        value: 'hook',
                        child: Text('Направи припев'),
                      ),
                      PopupMenuItem(
                        value: 'analyze',
                        child: Text('Анализирай текста'),
                      ),
                      PopupMenuItem(
                        value: 'music_prompt',
                        child: Text('Suno музикален промпт'),
                      ),
                      PopupMenuItem(
                        value: 'save',
                        child: Text('Запази като песен'),
                      ),
                      PopupMenuItem(
                        value: 'studio',
                        child: Text('Отвори в Рап студио'),
                      ),
                    ],
                  ),
                InkWell(
''',
)

replace_once(
    "pubspec.yaml",
    "version: 3.3.5+43\n",
    "version: 3.3.6+44\n",
)

Path("CHANGELOG_V336_CHAT_MUSIC_ACTIONS.md").write_text(
    """# v3.3.6 Chat Music Actions

- Adds a music-action menu to every normal AI reply.
- Supports tightening rhymes, creating a hook, analyzing lyrics and generating a Suno music prompt.
- Saves an AI reply directly as a song in My Songs.
- Keeps one-tap transfer to Rap Studio.
- Understands natural commands about the previous reply, such as “анализирай текста”, “стегни му римите”, “направи му припев” and “запази го като песен”.
- Reuses the existing Gemini → Groq provider chain.
- Preserves v3.3.5 silent notification behavior, native Bulgarian speech and stable signing.
""",
    encoding="utf-8",
)

Path("test/chat_music_actions_test.dart").write_text(
    """import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat exposes practical music actions', () {
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();

    expect(chat, contains("value: 'improve'"));
    expect(chat, contains("value: 'hook'"));
    expect(chat, contains("value: 'analyze'"));
    expect(chat, contains("value: 'music_prompt'"));
    expect(chat, contains("value: 'save'"));
    expect(chat, contains("value: 'studio'"));
    expect(chat, contains('Стегни римите'));
    expect(chat, contains('Направи припев'));
    expect(chat, contains('Анализирай текста'));
    expect(chat, contains('Suno музикален промпт'));
    expect(chat, contains('Запази като песен'));
  });

  test('spoken or typed commands can act on the previous AI reply', () {
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();

    expect(chat, contains('_detectMusicCommand'));
    expect(chat, contains('_lastAssistantMessage()'));
    expect(chat, contains('_runChatMusicAction(musicCommand, previous.text)'));
    expect(chat, contains('_saveChatTextAsSong'));
    expect(chat, contains('widget.store.loadSongIntoStudio(project)'));
    expect(chat, contains('_gemini.generateRap'));
  });
}
""",
    encoding="utf-8",
)
