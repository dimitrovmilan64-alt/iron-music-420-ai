from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly 1 match, found {count}")
    return text.replace(old, new, 1)


root = Path('.')
chat_path = root / 'lib/pages/chat_page.dart'
main_path = root / 'lib/main.dart'
pubspec_path = root / 'pubspec.yaml'
workflow_path = root / '.github/workflows/android-build.yml'
test_path = root / 'test/chat_layout_test.dart'
changelog_path = root / 'CHANGELOG_V320_CLEAN_UI.md'

chat = chat_path.read_text(encoding='utf-8')

chat = replace_once(
    chat,
    """class ChatPage extends StatefulWidget {
  final LocalStore store;

  const ChatPage({super.key, required this.store});
""",
    """class ChatPage extends StatefulWidget {
  final LocalStore store;
  final VoidCallback? onOpenTools;

  const ChatPage({
    super.key,
    required this.store,
    this.onOpenTools,
  });
""",
    'ChatPage constructor',
)
chat = replace_once(
    chat,
    'class _ChatPageState extends State<ChatPage> {',
    'class _ChatPageState extends State<ChatPage>\n    with SingleTickerProviderStateMixin {',
    'animation mixin',
)
chat = replace_once(
    chat,
    """  final AutomationService _automation = AutomationService();

  late List<ChatMessage> _messages;
""",
    """  final AutomationService _automation = AutomationService();
  late final AnimationController _coreController;

  late List<ChatMessage> _messages;
""",
    'animation controller field',
)
chat = replace_once(chat, '  bool _showApiBox = false;\n', '', 'remove inline API state')
chat = replace_once(
    chat,
    """  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: widget.store.apiKey);
    _showApiBox = !widget.store.hasApiKey;
""",
    """  void initState() {
    super.initState();
    _coreController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _apiKeyController = TextEditingController(text: widget.store.apiKey);
""",
    'initialize core animation',
)
chat = replace_once(
    chat,
    """  void dispose() {
    _flutterTts.stop();
""",
    """  void dispose() {
    _coreController.dispose();
    _flutterTts.stop();
""",
    'dispose core animation',
)

save_start = chat.index('  Future<void> _saveApiKey() async {')
send_start = chat.index('  Future<void> _sendMessage() async {', save_start)
new_key_methods = r'''  Future<bool> _saveApiKey() async {
    final value = _apiKeyController.text.trim();
    if (value.isEmpty) {
      _showMessage('Постави Gemini API ключ.');
      return false;
    }

    await widget.store.setApiKey(value);
    await _automation.syncGeminiApiKey(value);
    _gemini.resetModel();
    if (!mounted) return false;
    setState(() {});
    _showMessage('API ключът е запазен локално на телефона.');
    return true;
  }

  Future<void> _clearApiKey() async {
    _apiKeyController.clear();
    await widget.store.setApiKey('');
    await _automation.syncGeminiApiKey('');
    _gemini.resetModel();
    if (!mounted) return;
    setState(() {});
    _showMessage('API ключът е премахнат.');
  }

'''
chat = chat[:save_start] + new_key_methods + chat[send_start:]
chat = replace_once(
    chat,
    """    if (apiKey.isEmpty) {
      setState(() => _showApiBox = true);
      _showMessage('Първо постави и запази Gemini API ключа.');
      return;
    }
""",
    """    if (apiKey.isEmpty) {
      await _openApiKeySheet();
      return;
    }
""",
    'missing API key flow',
)
chat = replace_once(
    chat,
    """  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }
""",
    """  void _showMessage(String text) {
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
""",
    'floating messages',
)

ui_start = chat.index('  Widget _buildApiSection() {')
ui_end = chat.index('\n}\n\nclass _ChatBubble', ui_start)
new_ui = r'''  Future<void> _openApiKeySheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    _apiKeyController.text = widget.store.apiKey;

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
                      Icon(Icons.key_rounded, color: ironGreen),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Gemini API ключ',
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
                    'Ключът се пази само локално на телефона и не се записва в GitHub.',
                    style: TextStyle(color: Colors.white60, height: 1.35),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _apiKeyController,
                    autofocus: !widget.store.hasApiKey,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) async {
                      final saved = await _saveApiKey();
                      if (saved && sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'API ключ',
                      hintText: 'AIza...',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () async {
                      final saved = await _saveApiKey();
                      if (saved && sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                    },
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Запази ключа'),
                  ),
                  if (widget.store.hasApiKey) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _clearApiKey();
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Премахни ключа'),
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
                  tooltip: 'Gemini API ключ',
                  active: widget.store.hasApiKey,
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
                        widget.store.hasApiKey
                            ? 'Личен AI асистент'
                            : 'Добави Gemini ключ от менюто',
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
                      child: Text('API ключ'),
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
'''
chat = chat[:ui_start] + new_ui + chat[ui_end:]
chat = replace_once(
    chat,
    '        constraints: const BoxConstraints(maxWidth: 340),',
    '        constraints: BoxConstraints(\n          maxWidth: MediaQuery.sizeOf(context).width * 0.84,\n        ),',
    'responsive chat bubbles',
)

if '_showApiBox' in chat:
    raise RuntimeError('inline API state still present')
if '_buildApiSection' in chat:
    raise RuntimeError('inline API section still present')
if 'height: showLargeCore' in chat:
    raise RuntimeError('fixed core height unexpectedly present')
chat_path.write_text(chat, encoding='utf-8')

main = main_path.read_text(encoding='utf-8')
main = replace_once(main, "import 'pages/home_page.dart';\n", '', 'remove home import')
nav_start = main.index('  static const _navItems = <IronNavItem>[')
nav_end = main.index('\n  @override\n  void initState()', nav_start)
main = main[:nav_start] + r'''  static const _navItems = <IronNavItem>[
    IronNavItem(
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome_rounded,
      label: 'AI',
    ),
    IronNavItem(
      icon: Icons.mic_external_on_outlined,
      selectedIcon: Icons.mic_external_on,
      label: 'Студио',
    ),
    IronNavItem(
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music,
      label: 'Песни',
    ),
  ];
''' + main[nav_end:]
old_pages = r'''    _pages = [
      HomePage(store: widget.store, onOpenSection: _openSection),
      RapStudioPage(store: widget.store),
      SongsPage(store: widget.store, onOpenStudio: () => _openSection(1)),
      ChatPage(store: widget.store),
      CommandsPage(store: widget.store, onOpenSection: _openSection),
    ];
'''
new_pages = r'''    _pages = [
      ChatPage(
        store: widget.store,
        onOpenTools: () => _openSection(4),
      ),
      RapStudioPage(store: widget.store),
      SongsPage(store: widget.store, onOpenStudio: () => _openSection(1)),
      CommandsPage(store: widget.store, onOpenSection: _openSection),
    ];
'''
main = replace_once(main, old_pages, new_pages, 'clean page stack')
main = replace_once(
    main,
    r'''  void _openSection(int index) {
    if (!mounted || index < 0 || index >= _pages.length) return;
    setState(() => _currentIndex = index);
  }
''',
    r'''  void _openSection(int legacyIndex) {
    if (!mounted) return;

    int targetIndex;
    switch (legacyIndex) {
      case 0:
      case 3:
        targetIndex = 0;
        break;
      case 1:
        targetIndex = 1;
        break;
      case 2:
        targetIndex = 2;
        break;
      case 4:
        targetIndex = 3;
        break;
      default:
        return;
    }

    setState(() => _currentIndex = targetIndex);
  }
''',
    'legacy section mapping',
)
main = replace_once(
    main,
    '        selectedIndex: _currentIndex,',
    '        selectedIndex: _currentIndex < _navItems.length ? _currentIndex : 0,',
    'hidden tools navigation state',
)
main_path.write_text(main, encoding='utf-8')

pubspec = pubspec_path.read_text(encoding='utf-8')
pubspec = replace_once(pubspec, 'version: 3.0.0+33', 'version: 3.2.0+37', 'version bump')
pubspec_path.write_text(pubspec, encoding='utf-8')

workflow = workflow_path.read_text(encoding='utf-8')
workflow = replace_once(
    workflow,
    """      - name: Get Flutter packages
        run: flutter pub get

      - name: Build arm64 debug APK
""",
    """      - name: Get Flutter packages
        run: flutter pub get

      - name: Analyze clean UI
        run: flutter analyze --no-fatal-warnings --no-fatal-infos lib/main.dart lib/pages/chat_page.dart

      - name: Test small-screen layout
        run: flutter test test/chat_layout_test.dart

      - name: Build arm64 debug APK
""",
    'CI quality gates',
)
workflow = workflow.replace(
    'name: iron-music-420-ai-v3.0.0-ai-voice-mode',
    'name: iron-music-420-ai-v3.2.0-clean-ui',
)
workflow_path.write_text(workflow, encoding='utf-8')

test_path.parent.mkdir(parents=True, exist_ok=True)
test_path.write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ironmusic420ai/pages/chat_page.dart';
import 'package:ironmusic420ai/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chat and API sheet do not overflow on a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = LocalStore();
    await store.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(body: ChatPage(store: store)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Настройки'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('API ключ'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Gemini API ключ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
''', encoding='utf-8')

changelog_path.write_text('''# Iron Music 420 AI v3.2.0

- Изградено от заключения стабилен v3.0 commit, без v3.1 кръпки.
- AI чатът е първият и основен екран.
- Видимата навигация е AI, Студио и Песни.
- Централното Iron листо е бутон за микрофона и няма фиксиран контейнер.
- При отворена клавиатура централният визуален блок се прибира автоматично.
- Gemini API ключът е само в scrollable modal bottom sheet.
- Добавен е widget test за малък екран и API прозореца.
- Гласовата услуга, wake-word двигателят и Android действията от v3.0 не са променяни.
- Версия: 3.2.0+37.
''', encoding='utf-8')

print('v3.2.0 clean UI applied successfully')
