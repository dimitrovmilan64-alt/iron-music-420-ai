from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:120]!r}")
    file_path.write_text(text.replace(old, new, 1), encoding="utf-8")


# Keep the foreground service alive. Pause only its wake-word audio resources.
service = "android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt"
replace_once(
    service,
    '        const val ACTION_STOP = "com.example.ironmusic420ai.STOP_IRON_VOICE"\n',
    '        const val ACTION_STOP = "com.example.ironmusic420ai.STOP_IRON_VOICE"\n'
    '        const val ACTION_PAUSE_WAKE = "com.example.ironmusic420ai.PAUSE_IRON_WAKE"\n'
    '        const val ACTION_RESUME_WAKE = "com.example.ironmusic420ai.RESUME_IRON_WAKE"\n',
)
replace_once(
    service,
    '    private var ignoreNextRecognitionError = false\n\n    @Volatile\n    private var wakeWordActive = false\n',
    '    private var ignoreNextRecognitionError = false\n\n'
    '    @Volatile\n    private var pausedForChatSpeech = false\n\n'
    '    @Volatile\n    private var wakeWordActive = false\n',
)
replace_once(
    service,
    '''    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (
''',
    '''    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_PAUSE_WAKE -> {
                pauseForChatSpeech()
                return START_STICKY
            }
            ACTION_RESUME_WAKE -> {
                resumeAfterChatSpeech()
                return START_STICKY
            }
        }

        if (
''',
)
replace_once(
    service,
    '''    private fun initializeRecognizer() {
''',
    '''    private fun pauseForChatSpeech() {
        if (pausedForChatSpeech) return
        pausedForChatSpeech = true
        handler.removeCallbacks(beginWakeWordListening)
        handler.removeCallbacks(beginSpeechRecognition)
        handler.removeCallbacks(finalizePendingCommand)
        handler.removeCallbacks(recognitionTimeout)
        pendingCommandParts.clear()
        afterSpeech = null
        isAiProcessing = false
        if (isListening) {
            ignoreNextRecognitionError = true
            try {
                recognizer?.cancel()
            } catch (_: Exception) {
                // The recognizer may already be stopping.
            }
        }
        isListening = false
        if (isSpeaking) {
            try {
                textToSpeech?.stop()
            } catch (_: Exception) {
                // TTS may already be complete.
            }
        }
        isSpeaking = false
        voiceState = VoiceState.WAITING_FOR_WAKE
        stopWakeWordListening()
        updateNotification("Iron е активен • диктовка в приложението")
    }

    private fun resumeAfterChatSpeech() {
        if (!pausedForChatSpeech) return
        pausedForChatSpeech = false
        if (!isRunning) return
        voiceState = VoiceState.WAITING_FOR_WAKE
        updateNotification("Iron е готов • кажи „Hey Iron“")
        scheduleWakeWordListening(650)
    }

    private fun initializeRecognizer() {
''',
)
replace_once(
    service,
    '''            isRunning &&
            !isSpeaking &&
''',
    '''            isRunning &&
            !pausedForChatSpeech &&
            !isSpeaking &&
''',
)
replace_once(
    service,
    '''            !isRunning ||
            isSpeaking ||
''',
    '''            !isRunning ||
            pausedForChatSpeech ||
            isSpeaking ||
''',
)
replace_once(
    service,
    '''                            detected &&
                            isRunning &&
                            !isSpeaking &&
''',
    '''                            detected &&
                            isRunning &&
                            !pausedForChatSpeech &&
                            !isSpeaking &&
''',
)
replace_once(
    service,
    '''                        } else if (isRunning) {
                            scheduleWakeWordListening(800)
''',
    '''                        } else if (isRunning && !pausedForChatSpeech) {
                            scheduleWakeWordListening(800)
''',
)

# MainActivity must signal pause/resume instead of destroying/recreating the service.
activity = "android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt"
replace_once(
    activity,
    '''        restoreIronVoiceAfterChatSpeech = IronVoiceService.isRunning
        if (restoreIronVoiceAfterChatSpeech) {
            stopService(
                Intent(this, IronVoiceService::class.java).apply {
                    action = IronVoiceService.ACTION_STOP
                },
            )
        }

        val releaseDelay = if (restoreIronVoiceAfterChatSpeech) 950L else 120L
''',
    '''        restoreIronVoiceAfterChatSpeech = IronVoiceService.isRunning
        if (restoreIronVoiceAfterChatSpeech) {
            startService(
                Intent(this, IronVoiceService::class.java).apply {
                    action = IronVoiceService.ACTION_PAUSE_WAKE
                },
            )
        }

        val releaseDelay = if (restoreIronVoiceAfterChatSpeech) 550L else 120L
''',
)
replace_once(
    activity,
    '''                    ContextCompat.startForegroundService(
                        this,
                        Intent(this, IronVoiceService::class.java).apply {
                            action = IronVoiceService.ACTION_START
                        },
                    )
                },
                350L,
''',
    '''                    startService(
                        Intent(this, IronVoiceService::class.java).apply {
                            action = IronVoiceService.ACTION_RESUME_WAKE
                        },
                    )
                },
                250L,
''',
)

# Make Groq the built-in backup provider.
replace_once(
    "lib/services/ai_provider_config.dart",
    "  static const defaultBackupBaseUrl = 'https://api.openai.com/v1';\n  static const defaultBackupModel = 'gpt-4.1-mini';\n",
    "  static const defaultBackupBaseUrl = 'https://api.groq.com/openai/v1';\n  static const defaultBackupModel = 'openai/gpt-oss-20b';\n",
)
replace_once(
    "android/app/src/main/kotlin/com/example/ironmusic420ai/GeminiVoiceRouter.kt",
    '        const val DEFAULT_BACKUP_BASE_URL = "https://api.openai.com/v1"\n        const val DEFAULT_BACKUP_MODEL = "gpt-4.1-mini"\n',
    '        const val DEFAULT_BACKUP_BASE_URL = "https://api.groq.com/openai/v1"\n        const val DEFAULT_BACKUP_MODEL = "openai/gpt-oss-20b"\n',
)

chat = "lib/pages/chat_page.dart"
replace_once(
    chat,
    "import '../services/automation_service.dart';\n",
    "import '../services/ai_provider_config.dart';\nimport '../services/automation_service.dart';\n",
)
replace_once(
    chat,
    '''    final backupBaseUrl = _backupBaseUrlController.text.trim();
    final backupModel = _backupModelController.text.trim();
''',
    '''    final backupBaseUrl = backupKey.isEmpty
        ? _backupBaseUrlController.text.trim()
        : AiProviderConfig.defaultBackupBaseUrl;
    final backupModel = backupKey.isEmpty
        ? _backupModelController.text.trim()
        : AiProviderConfig.defaultBackupModel;
''',
)
replace_once(
    chat,
    "                    'Iron използва Gemini първо. При лимит или недостъпност автоматично преминава към резервния OpenAI-съвместим доставчик. Ключовете се пазят само локално на телефона.',\n",
    "                    'Iron използва Gemini първо. При лимит или недостъпност автоматично преминава към Groq. Ключовете се пазят само локално на телефона.',\n",
)
replace_once(
    chat,
    "                    '2. Резервен · OpenAI-съвместим',\n",
    "                    '2. Резервен доставчик · Groq',\n",
)
replace_once(
    chat,
    "                    'По подразбиране е OpenAI. Адресът и моделът могат да се сменят за друг съвместим доставчик.',\n",
    "                    'Постави само Groq API ключа. Адресът и моделът се настройват автоматично.',\n",
)
replace_once(
    chat,
    "                      labelText: 'Резервен API ключ',\n                      hintText: 'sk-...',\n",
    "                      labelText: 'Groq API ключ',\n                      hintText: 'gsk_...',\n",
)
replace_once(
    chat,
    '''                  const SizedBox(height: 12),
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
''',
    '''                  const SizedBox(height: 12),
                  const Container(
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
''',
)
replace_once(
    chat,
    "    _showMessage('AI доставчиците са запазени локално на телефона.');\n",
    "    _showMessage('Gemini и Groq са запазени локално на телефона.');\n",
)
replace_once(
    chat,
    "    _showMessage('Резервният AI ключ е премахнат.');\n",
    "    _showMessage('Groq ключът е премахнат.');\n",
)

replace_once(
    "pubspec.yaml",
    "version: 3.3.3+41\n",
    "version: 3.3.4+42\n",
)

Path("CHANGELOG_V334_STABLE_VOICE_GROQ.md").write_text(
    """# v3.3.4 Stable Voice + Groq\n\n"
    "- Keeps the foreground Hey Iron service alive during chat dictation.\n"
    "- Pauses and resumes only wake-word audio resources.\n"
    "- Prevents notification/service restart loops and excess CPU use.\n"
    "- Makes Groq the built-in backup provider.\n"
    "- Groq endpoint and model are automatic; the user enters only the key.\n"
    "- Preserves the stable APK signing certificate introduced in v3.3.3.\n"
    """,
    encoding="utf-8",
)

Path("test/native_voice_pause_groq_test.dart").write_text(
    """import 'dart:io';\n\n"
    "import 'package:flutter_test/flutter_test.dart';\n\n"
    "void main() {\n"
    "  test('chat dictation pauses wake audio without restarting service', () {\n"
    "    final activity = File('android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt').readAsStringSync();\n"
    "    final service = File('android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt').readAsStringSync();\n"
    "    expect(activity, contains('ACTION_PAUSE_WAKE'));\n"
    "    expect(activity, contains('ACTION_RESUME_WAKE'));\n"
    "    expect(service, contains('pausedForChatSpeech'));\n"
    "    expect(service, contains('pauseForChatSpeech()'));\n"
    "    expect(service, contains('resumeAfterChatSpeech()'));\n"
    "  });\n\n"
    "  test('Groq is the automatic backup provider', () {\n"
    "    final config = File('lib/services/ai_provider_config.dart').readAsStringSync();\n"
    "    final chat = File('lib/pages/chat_page.dart').readAsStringSync();\n"
    "    expect(config, contains('https://api.groq.com/openai/v1'));\n"
    "    expect(config, contains('openai/gpt-oss-20b'));\n"
    "    expect(chat, contains('Groq API ключ'));\n"
    "  });\n"
    "}\n"
    """,
    encoding="utf-8",
)
