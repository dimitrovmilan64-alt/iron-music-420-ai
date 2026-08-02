from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:180]!r}")
    file_path.write_text(text.replace(old, new, 1), encoding="utf-8")


# Native voice: deterministic local actions run before cloud AI.
service = "android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt"
replace_once(
    service,
    """        if (!aiRouter.hasApiKey()) {
""",
    """        val localCommand = LocalVoiceCommandParser.parse(originalCommand)
        if (localCommand != null) {
            val reply = executeLocalVoiceCommand(localCommand)
            speak(reply) {
                continueConversationOrWake(650)
            }
            return
        }

        if (!aiRouter.hasApiKey()) {
""",
)
replace_once(
    service,
    """    private fun executeAiDecision(decision: GeminiVoiceRouter.Decision): String {
""",
    """    private fun executeLocalVoiceCommand(command: LocalVoiceCommand): String {
        return when (command.action) {
            "studio_generate" -> {
                openIronStudioRequest(
                    prompt = command.argument,
                    outputType = command.studioOutputType,
                )
                command.reply.ifBlank { "Отварям Рап студио." }
            }
            "clarify" -> command.reply.ifBlank { "Кажи какво точно да направя." }
            else -> executeAiDecision(
                GeminiVoiceRouter.Decision(
                    action = command.action,
                    argument = command.argument,
                    reply = command.reply,
                ),
            )
        }
    }

    private fun executeAiDecision(decision: GeminiVoiceRouter.Decision): String {
""",
)
replace_once(
    service,
    """    private fun openIronSection(section: Int) {
""",
    """    private fun openIronStudioRequest(prompt: String, outputType: String) {
        launch(
            Intent(this, MainActivity::class.java).apply {
                putExtra("iron_section", 1)
                putExtra("iron_studio_prompt", prompt.trim())
                putExtra("iron_studio_output_type", outputType.trim())
                putExtra("iron_studio_auto_generate", true)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
        )
    }

    private fun openIronSection(section: Int) {
""",
)

# Android -> Flutter bridge for pending Studio requests.
activity = "android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt"
replace_once(
    activity,
    """    private var pendingIronSection: Int? = null
""",
    """    private var pendingIronSection: Int? = null
    private var pendingStudioPrompt = ""
    private var pendingStudioOutputType = ""
    private var pendingStudioAutoGenerate = false
""",
)
replace_once(
    activity,
    """                    "consumeIronSection" -> {
                        result.success(pendingIronSection)
                        pendingIronSection = null
                    }
""",
    """                    "consumeIronSection" -> {
                        result.success(pendingIronSection)
                        pendingIronSection = null
                    }
                    "consumeStudioVoiceRequest" -> {
                        if (pendingStudioPrompt.isBlank()) {
                            result.success(null)
                        } else {
                            result.success(
                                mapOf(
                                    "prompt" to pendingStudioPrompt,
                                    "outputType" to pendingStudioOutputType,
                                    "autoGenerate" to pendingStudioAutoGenerate,
                                ),
                            )
                            pendingStudioPrompt = ""
                            pendingStudioOutputType = ""
                            pendingStudioAutoGenerate = false
                        }
                    }
""",
)
replace_once(
    activity,
    """    private fun captureIronSection(intent: Intent?) {
        val section = intent?.getIntExtra("iron_section", -1) ?: -1
        if (section in 0..4) {
            pendingIronSection = section
        }
    }
""",
    """    private fun captureIronSection(intent: Intent?) {
        val section = intent?.getIntExtra("iron_section", -1) ?: -1
        if (section in 0..4) {
            pendingIronSection = section
        }

        val studioPrompt = intent?.getStringExtra("iron_studio_prompt").orEmpty().trim()
        if (studioPrompt.isNotEmpty()) {
            pendingStudioPrompt = studioPrompt
            pendingStudioOutputType =
                intent?.getStringExtra("iron_studio_output_type").orEmpty().trim()
            pendingStudioAutoGenerate =
                intent?.getBooleanExtra("iron_studio_auto_generate", false) == true
        }
    }
""",
)

# Flutter method-channel model and consumer.
automation = "lib/services/automation_service.dart"
replace_once(
    automation,
    """class AutomationService {
""",
    """class StudioVoiceRequest {
  final String prompt;
  final String outputType;
  final bool autoGenerate;

  const StudioVoiceRequest({
    required this.prompt,
    required this.outputType,
    required this.autoGenerate,
  });
}

class AutomationService {
""",
)
replace_once(
    automation,
    """  Future<AutomationResult> execute(
""",
    """  Future<StudioVoiceRequest?> consumeStudioVoiceRequest() async {
    try {
      final value = await _channel.invokeMethod<dynamic>(
        'consumeStudioVoiceRequest',
      );
      if (value is! Map) return null;
      final prompt = value['prompt']?.toString().trim() ?? '';
      if (prompt.isEmpty) return null;
      return StudioVoiceRequest(
        prompt: prompt,
        outputType: value['outputType']?.toString().trim() ?? '',
        autoGenerate: value['autoGenerate'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<AutomationResult> execute(
""",
)

# Local store carries the one-shot request to the existing Rap Studio.
store = "lib/services/local_store.dart"
replace_once(
    store,
    """  int _studioRevision = 0;
""",
    """  int _studioRevision = 0;
  String _pendingStudioPrompt = '';
  String _pendingStudioOutputType = '';
  bool _pendingStudioAutoGenerate = false;
""",
)
replace_once(
    store,
    """  int get studioRevision => _studioRevision;
""",
    """  int get studioRevision => _studioRevision;
  String get pendingStudioPrompt => _pendingStudioPrompt;
  String get pendingStudioOutputType => _pendingStudioOutputType;
  bool get pendingStudioAutoGenerate => _pendingStudioAutoGenerate;
""",
)
replace_once(
    store,
    """  Future<void> loadSongIntoStudio(SongProject song) async {
""",
    """  Future<void> queueStudioVoiceRequest({
    required String prompt,
    required String outputType,
    required bool autoGenerate,
  }) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) return;

    _activeSongId = '';
    _rapDraft = cleanPrompt;
    _rapResult = '';
    _pendingStudioPrompt = cleanPrompt;
    _pendingStudioOutputType = outputType.trim();
    _pendingStudioAutoGenerate = autoGenerate;
    _studioRevision++;
    await Future.wait([
      _preferences.setString(_rapDraftKey, _rapDraft),
      _preferences.remove(_rapResultKey),
      _preferences.remove(_activeSongIdKey),
    ]);
    notifyListeners();
  }

  void clearPendingStudioVoiceRequest() {
    _pendingStudioPrompt = '';
    _pendingStudioOutputType = '';
    _pendingStudioAutoGenerate = false;
  }

  Future<void> loadSongIntoStudio(SongProject song) async {
""",
)

# Main screen consumes the native request and opens the single Studio page.
main_file = "lib/main.dart"
replace_once(
    main_file,
    """  Future<void> _openPendingSection() async {
    final section = await _automation.consumeIronSection();
    if (section != null) {
      _openSection(section);
    }
  }
""",
    """  Future<void> _openPendingSection() async {
    final studioRequest = await _automation.consumeStudioVoiceRequest();
    if (studioRequest != null) {
      await widget.store.queueStudioVoiceRequest(
        prompt: studioRequest.prompt,
        outputType: studioRequest.outputType,
        autoGenerate: studioRequest.autoGenerate,
      );
      _openSection(1);
      return;
    }

    final section = await _automation.consumeIronSection();
    if (section != null) {
      _openSection(section);
    }
  }
""",
)

# Rap Studio applies the requested output type and starts its existing generator.
studio = "lib/pages/rap_studio_page.dart"
replace_once(
    studio,
    """    widget.store.addListener(_handleStoreChange);
  }
""",
    """    widget.store.addListener(_handleStoreChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyPendingStudioVoiceRequest();
    });
  }
""",
)
replace_once(
    studio,
    """    _restoring = false;
  }

  void _markChanged() {
""",
    """    _restoring = false;
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
""",
)

# Add accented Hey Aaron pronunciations to the offline wake phrase list.
kws = "scripts/prepare_sherpa_kws.sh"
replace_once(
    kws,
    """# Bulgarian-accented, relaxed and compressed variants of „Хей Айрън“.
candidates.extend(
""",
    """# Common recognition variant: „Hey Aaron“ / „Хей Аарън“.
for hey_index, hey in enumerate(lexicon.get("HEY", []), start=1):
    for aaron_index, aaron in enumerate(lexicon.get("AARON", []), start=1):
        candidates.append(
            (f"HEY_AARON_LEX_{hey_index}_{aaron_index}", hey + aaron, 4.8, 0.04)
        )

# Bulgarian-accented, relaxed and compressed variants of „Хей Айрън“.
candidates.extend(
""",
)
replace_once(
    kws,
    """        ("HEY_IRON_NO_H_OW", ["EY1", "AY1", "R", "OW0", "N"], 4.5, 0.04),
""",
    """        ("HEY_IRON_NO_H_OW", ["EY1", "AY1", "R", "OW0", "N"], 4.5, 0.04),
        ("HEY_AARON_BG", ["HH", "EY1", "EH1", "R", "AH0", "N"], 4.6, 0.04),
        ("HEY_AARON_BG_FAST", ["HH", "EY1", "EH1", "R", "N"], 4.5, 0.05),
        ("HEY_AARON_NO_H", ["EY1", "EH1", "R", "AH0", "N"], 4.4, 0.05),
""",
)

replace_once("pubspec.yaml", "version: 3.3.5+43\n", "version: 3.4.0+44\n")

Path("CHANGELOG_V340_SINGLE_CHAT_VOICE_CORE.md").write_text(
    """# v3.4.0 Single Chat + Voice Core

- Starts from the clean v3.3.5 source commit.
- Executes deterministic phone and navigation commands before Gemini/Groq.
- Keeps local commands working when both AI providers are rate-limited.
- Adds Bulgarian and English command variants.
- Adds direct voice flows for rap lyrics, rhymes/punchlines and chorus generation.
- Opens the existing Rap Studio, loads the request and starts its existing generator.
- Adds common “Hey Aaron” pronunciation variants to the offline wake-word model.
- Preserves the silent notification channel, native chat speech, Groq fallback and stable signing.
""",
    encoding="utf-8",
)

Path("test/single_chat_voice_core_test.dart").write_text(
    """import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local commands are routed before cloud AI', () {
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();
    final localIndex = service.indexOf('LocalVoiceCommandParser.parse');
    final apiIndex = service.indexOf('if (!aiRouter.hasApiKey())');

    expect(localIndex, greaterThanOrEqualTo(0));
    expect(apiIndex, greaterThan(localIndex));
    expect(service, contains('executeLocalVoiceCommand'));
    expect(service, contains('openIronStudioRequest'));
  });

  test('parser includes bilingual phone and music commands', () {
    final parser = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/LocalVoiceCommandParser.kt',
    ).readAsStringSync();

    for (final phrase in [
      'отвори чата',
      'open chat',
      'музикален режим',
      'music mode',
      'направи рап текст',
      'дай рими',
      'направи припев',
      'включи фенера',
      'turn on flashlight',
    ]) {
      expect(parser, contains(phrase));
    }
  });

  test('native Studio request reaches the existing Rap Studio generator', () {
    final activity = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt',
    ).readAsStringSync();
    final automation =
        File('lib/services/automation_service.dart').readAsStringSync();
    final store = File('lib/services/local_store.dart').readAsStringSync();
    final studio = File('lib/pages/rap_studio_page.dart').readAsStringSync();

    expect(activity, contains('consumeStudioVoiceRequest'));
    expect(automation, contains('consumeStudioVoiceRequest'));
    expect(store, contains('queueStudioVoiceRequest'));
    expect(studio, contains('_applyPendingStudioVoiceRequest'));
    expect(studio, contains('_generateWithAi()'));
  });

  test('offline wake list contains Hey Aaron variants', () {
    final script = File('scripts/prepare_sherpa_kws.sh').readAsStringSync();
    expect(script, contains('HEY_AARON_LEX'));
    expect(script, contains('HEY_AARON_BG'));
  });
}
""",
    encoding="utf-8",
)
