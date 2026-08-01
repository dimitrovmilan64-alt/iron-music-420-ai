from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)


def replace_between(
    text: str,
    start_marker: str,
    end_marker: str,
    replacement: str,
    label: str,
) -> str:
    start = text.find(start_marker)
    if start < 0:
        raise RuntimeError(f'{label}: start marker not found')
    end = text.find(end_marker, start)
    if end < 0:
        raise RuntimeError(f'{label}: end marker not found')
    return text[:start] + replacement + text[end:]


root = Path('.')
local_store_path = root / 'lib/services/local_store.dart'
main_path = root / 'lib/main.dart'
chat_path = root / 'lib/pages/chat_page.dart'
rap_path = root / 'lib/pages/rap_studio_page.dart'
main_activity_path = root / 'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt'
voice_service_path = root / 'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt'
pubspec_path = root / 'pubspec.yaml'
layout_test_path = root / 'test/chat_layout_test.dart'
changelog_path = root / 'CHANGELOG_V330_PROVIDER_FALLBACK.md'

# LocalStore: persist and expose backup provider settings.
local_store = local_store_path.read_text(encoding='utf-8')
local_store = replace_once(
    local_store,
    "import '../models/song_project.dart';\n",
    "import '../models/song_project.dart';\nimport 'ai_provider_config.dart';\n",
    'local store config import',
)
local_store = replace_once(
    local_store,
    "  static const _apiKeyKey = 'gemini_api_key';\n",
    """  static const _apiKeyKey = 'gemini_api_key';
  static const _backupApiKeyKey = 'backup_api_key';
  static const _backupBaseUrlKey = 'backup_base_url';
  static const _backupModelKey = 'backup_model';
""",
    'local store provider keys',
)
local_store = replace_once(
    local_store,
    "  String _apiKey = '';\n",
    """  String _apiKey = '';
  String _backupApiKey = '';
  String _backupBaseUrl = AiProviderConfig.defaultBackupBaseUrl;
  String _backupModel = AiProviderConfig.defaultBackupModel;
""",
    'local store provider fields',
)
local_store = replace_once(
    local_store,
    "    _apiKey = _preferences.getString(_apiKeyKey) ?? '';\n",
    """    _apiKey = _preferences.getString(_apiKeyKey) ?? '';
    _backupApiKey = _preferences.getString(_backupApiKeyKey) ?? '';
    _backupBaseUrl = AiProviderConfig.normalizeBaseUrl(
      _preferences.getString(_backupBaseUrlKey) ??
          AiProviderConfig.defaultBackupBaseUrl,
    );
    _backupModel = (_preferences.getString(_backupModelKey) ??
            AiProviderConfig.defaultBackupModel)
        .trim();
    if (_backupModel.isEmpty) {
      _backupModel = AiProviderConfig.defaultBackupModel;
    }
""",
    'local store provider initialization',
)
local_store = replace_once(
    local_store,
    """    if (_activeSongId.isNotEmpty &&
        !_songProjects.any((song) => song.id == _activeSongId)) {
      _activeSongId = '';
      await _preferences.remove(_activeSongIdKey);
    }
  }

  String get apiKey => _apiKey;
""",
    """    if (_activeSongId.isNotEmpty &&
        !_songProjects.any((song) => song.id == _activeSongId)) {
      _activeSongId = '';
      await _preferences.remove(_activeSongIdKey);
    }

    _syncAiProviderConfig();
  }

  String get apiKey => _apiKey;
""",
    'local store initialize config sync',
)
local_store = replace_once(
    local_store,
    """  String get apiKey => _apiKey;
  bool get hasApiKey => _apiKey.trim().isNotEmpty;
  bool get voiceRepliesEnabled => _voiceRepliesEnabled;
""",
    """  String get apiKey => _apiKey;
  bool get hasApiKey => _apiKey.trim().isNotEmpty;
  String get backupApiKey => _backupApiKey;
  String get backupBaseUrl => _backupBaseUrl;
  String get backupModel => _backupModel;
  bool get hasBackupProvider => _backupApiKey.trim().isNotEmpty;
  bool get hasAnyAiProvider => hasApiKey || hasBackupProvider;
  bool get voiceRepliesEnabled => _voiceRepliesEnabled;
""",
    'local store provider getters',
)
local_store = replace_once(
    local_store,
    """  Future<void> setVoiceRepliesEnabled(bool value) async {
""",
    """  Future<void> setBackupProvider({
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    _backupApiKey = apiKey.trim();
    _backupBaseUrl = AiProviderConfig.normalizeBaseUrl(baseUrl);
    _backupModel = model.trim().isEmpty
        ? AiProviderConfig.defaultBackupModel
        : model.trim();

    await Future.wait([
      if (_backupApiKey.isEmpty)
        _preferences.remove(_backupApiKeyKey)
      else
        _preferences.setString(_backupApiKeyKey, _backupApiKey),
      _preferences.setString(_backupBaseUrlKey, _backupBaseUrl),
      _preferences.setString(_backupModelKey, _backupModel),
    ]);
    _syncAiProviderConfig();
    notifyListeners();
  }

  void _syncAiProviderConfig() {
    AiProviderConfig.update(
      backupApiKey: _backupApiKey,
      backupBaseUrl: _backupBaseUrl,
      backupModel: _backupModel,
    );
  }

  Future<void> setVoiceRepliesEnabled(bool value) async {
""",
    'local store backup setter',
)
local_store_path.write_text(local_store, encoding='utf-8')

# Startup: sync both providers to the native wake-word service.
main = main_path.read_text(encoding='utf-8')
main = replace_once(
    main,
    '  await AutomationService().syncGeminiApiKey(store.apiKey);',
    """  await AutomationService().syncAiProviderSettings(
    geminiApiKey: store.apiKey,
    backupApiKey: store.backupApiKey,
    backupBaseUrl: store.backupBaseUrl,
    backupModel: store.backupModel,
  );""",
    'startup provider sync',
)
main_path.write_text(main, encoding='utf-8')

# Chat: controllers, provider sheet and any-provider checks.
chat = chat_path.read_text(encoding='utf-8')
chat = replace_once(
    chat,
    """  static const _welcomeText =
      'Готов съм. Запази Gemini API ключа и ме попитай на български.';
""",
    """  static const _welcomeText =
      'Готов съм. Добави поне един AI доставчик и ме попитай на български.';
""",
    'chat welcome text',
)
chat = replace_once(
    chat,
    """  final TextEditingController _messageController = TextEditingController();
  late final TextEditingController _apiKeyController;
""",
    """  final TextEditingController _messageController = TextEditingController();
  late final TextEditingController _apiKeyController;
  late final TextEditingController _backupApiKeyController;
  late final TextEditingController _backupBaseUrlController;
  late final TextEditingController _backupModelController;
""",
    'chat provider controllers',
)
chat = replace_once(
    chat,
    """    _apiKeyController = TextEditingController(text: widget.store.apiKey);
    _messages = List<ChatMessage>.from(widget.store.chatHistory);
""",
    """    _apiKeyController = TextEditingController(text: widget.store.apiKey);
    _backupApiKeyController =
        TextEditingController(text: widget.store.backupApiKey);
    _backupBaseUrlController =
        TextEditingController(text: widget.store.backupBaseUrl);
    _backupModelController =
        TextEditingController(text: widget.store.backupModel);
    _messages = List<ChatMessage>.from(widget.store.chatHistory);
""",
    'chat provider controller initialization',
)
chat = replace_once(
    chat,
    """    _messageController.dispose();
    _apiKeyController.dispose();
    _scrollController.dispose();
""",
    """    _messageController.dispose();
    _apiKeyController.dispose();
    _backupApiKeyController.dispose();
    _backupBaseUrlController.dispose();
    _backupModelController.dispose();
    _scrollController.dispose();
""",
    'chat provider controller disposal',
)
provider_methods = r'''  Future<void> _syncNativeAiSettings() {
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

'''
chat = replace_between(
    chat,
    '  Future<bool> _saveApiKey() async {',
    '  Future<void> _sendMessage() async {',
    provider_methods,
    'chat provider save methods',
)
chat = replace_once(
    chat,
    """    final typedKey = _apiKeyController.text.trim();
    if (typedKey.isNotEmpty && typedKey != widget.store.apiKey) {
      await widget.store.setApiKey(typedKey);
      await _automation.syncGeminiApiKey(typedKey);
      _gemini.resetModel();
    }

    final apiKey = widget.store.apiKey.trim();
    if (apiKey.isEmpty) {
      await _openApiKeySheet();
      return;
    }
""",
    """    final apiKey = widget.store.apiKey.trim();
    if (!widget.store.hasAnyAiProvider) {
      await _openApiKeySheet();
      return;
    }
""",
    'chat any-provider send guard',
)
provider_sheet = r'''  Future<void> _openApiKeySheet() async {
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

'''
chat = replace_between(
    chat,
    '  Future<void> _openApiKeySheet() async {',
    '  Widget _roundAction({',
    provider_sheet,
    'chat provider sheet',
)
chat = replace_once(
    chat,
    """                        widget.store.hasApiKey
                            ? 'Личен AI асистент'
                            : 'Добави Gemini ключ от менюто',
""",
    """                        widget.store.hasAnyAiProvider
                            ? 'Личен AI асистент'
                            : 'Добави AI доставчик от менюто',
""",
    'chat header provider state',
)
chat = replace_once(
    chat,
    """                  tooltip: 'Gemini API ключ',
                  active: widget.store.hasApiKey,
""",
    """                  tooltip: 'AI доставчици',
                  active: widget.store.hasAnyAiProvider,
""",
    'chat provider action button',
)
chat = replace_once(
    chat,
    """                    const PopupMenuItem(
                      value: 'api',
                      child: Text('API ключ'),
                    ),
""",
    """                    const PopupMenuItem(
                      value: 'api',
                      child: Text('AI доставчици'),
                    ),
""",
    'chat provider menu item',
)
chat_path.write_text(chat, encoding='utf-8')

# Rap Studio: allow the backup provider to work without a Gemini key.
rap = rap_path.read_text(encoding='utf-8')
old_guard = """    final apiKey = widget.store.apiKey.trim();
    if (apiKey.isEmpty) {
      _showMessage('Първо запази Gemini API ключа в раздел „Чат“.');
      return;
    }
"""
new_guard = """    final apiKey = widget.store.apiKey.trim();
    if (!widget.store.hasAnyAiProvider) {
      _showMessage('Първо добави Gemini или резервен AI доставчик в раздел „AI“.');
      return;
    }
"""
count = rap.count(old_guard)
if count != 4:
    raise RuntimeError(f'rap provider guards: expected 4 matches, found {count}')
rap = rap.replace(old_guard, new_guard)
rap_path.write_text(rap, encoding='utf-8')

# Android bridge: persist both providers for the foreground wake-word service.
activity = main_activity_path.read_text(encoding='utf-8')
activity = replace_once(
    activity,
    """                    "syncGeminiApiKey" -> {
                        syncGeminiApiKey(
                            call.argument<String>("apiKey").orEmpty(),
                            result,
                        )
                    }
                    else -> result.notImplemented()
""",
    """                    "syncGeminiApiKey" -> {
                        syncGeminiApiKey(
                            call.argument<String>("apiKey").orEmpty(),
                            result,
                        )
                    }
                    "syncAiProviderSettings" -> {
                        syncAiProviderSettings(
                            geminiApiKey = call.argument<String>("geminiApiKey").orEmpty(),
                            backupApiKey = call.argument<String>("backupApiKey").orEmpty(),
                            backupBaseUrl = call.argument<String>("backupBaseUrl").orEmpty(),
                            backupModel = call.argument<String>("backupModel").orEmpty(),
                            result = result,
                        )
                    }
                    else -> result.notImplemented()
""",
    'native provider method channel',
)
native_sync_method = r'''    private fun syncAiProviderSettings(
        geminiApiKey: String,
        backupApiKey: String,
        backupBaseUrl: String,
        backupModel: String,
        result: MethodChannel.Result,
    ) {
        val editor = getSharedPreferences(
            GeminiVoiceRouter.PREFS_NAME,
            Context.MODE_PRIVATE,
        ).edit()

        val cleanGeminiKey = geminiApiKey.trim()
        val cleanBackupKey = backupApiKey.trim()
        val cleanBaseUrl = backupBaseUrl.trim().ifBlank {
            GeminiVoiceRouter.DEFAULT_BACKUP_BASE_URL
        }
        val cleanModel = backupModel.trim().ifBlank {
            GeminiVoiceRouter.DEFAULT_BACKUP_MODEL
        }

        if (cleanGeminiKey.isEmpty()) {
            editor.remove(GeminiVoiceRouter.KEY_GEMINI_API_KEY)
        } else {
            editor.putString(GeminiVoiceRouter.KEY_GEMINI_API_KEY, cleanGeminiKey)
        }
        if (cleanBackupKey.isEmpty()) {
            editor.remove(GeminiVoiceRouter.KEY_BACKUP_API_KEY)
        } else {
            editor.putString(GeminiVoiceRouter.KEY_BACKUP_API_KEY, cleanBackupKey)
        }
        editor.putString(GeminiVoiceRouter.KEY_BACKUP_BASE_URL, cleanBaseUrl)
        editor.putString(GeminiVoiceRouter.KEY_BACKUP_MODEL, cleanModel)
        editor.apply()
        result.success(true)
    }

'''
activity = replace_once(
    activity,
    '    override fun onNewIntent(intent: Intent) {\n',
    native_sync_method + '    override fun onNewIntent(intent: Intent) {\n',
    'native provider sync method',
)
main_activity_path.write_text(activity, encoding='utf-8')

# Local voice messages must describe both provider options.
voice = voice_service_path.read_text(encoding='utf-8')
voice = voice.replace(
    'За свободния AI режим отвори приложението и запази Gemini API ключа.',
    'За свободния AI режим отвори приложението и добави Gemini или резервен AI ключ.',
)
voice_service_path.write_text(voice, encoding='utf-8')

# Version and layout test.
pubspec = pubspec_path.read_text(encoding='utf-8')
pubspec = replace_once(
    pubspec,
    'version: 3.2.0+37',
    'version: 3.3.0+38',
    'version bump',
)
pubspec_path.write_text(pubspec, encoding='utf-8')

layout_test = layout_test_path.read_text(encoding='utf-8')
layout_test = layout_test.replace(
    "find.byTooltip('Gemini API ключ')",
    "find.byTooltip('AI доставчици')",
)
layout_test = layout_test.replace(
    "expect(find.text('Gemini API ключ'), findsOneWidget);",
    "expect(find.text('AI доставчици'), findsOneWidget);",
)
layout_test = layout_test.replace(
    "expect(find.text('Запази ключа'), findsOneWidget);",
    "expect(find.text('Запази AI доставчиците'), findsOneWidget);",
)
layout_test_path.write_text(layout_test, encoding='utf-8')

changelog_path.write_text('''# Iron Music 420 AI v3.3.0

- Gemini remains the primary AI provider.
- A configurable OpenAI-compatible backup provider is added.
- Gemini quota, authentication, network, and server failures trigger automatic fallback.
- The same provider chain is used by AI chat, Rap Studio, and the native Hey Iron voice router.
- If both cloud providers fail, native voice commands still use the existing local command parser.
- Provider keys, endpoint, and model are stored locally and synchronized to the Android foreground service.
- Added automated tests for Gemini 429 fallback and the small-screen provider sheet.
- Wake-word assets and the Android action allow-list are unchanged.
- Version: 3.3.0+38.
''', encoding='utf-8')

print('v3.3.0 provider fallback applied successfully')
