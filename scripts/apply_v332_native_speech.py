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
chat_path = root / 'lib/pages/chat_page.dart'
automation_path = root / 'lib/services/automation_service.dart'
activity_path = root / 'android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt'
pubspec_path = root / 'pubspec.yaml'
changelog_path = root / 'CHANGELOG_V332_NATIVE_SPEECH.md'

# Dart bridge for native Android speech recognition.
automation_path.write_text(r'''import 'package:flutter/services.dart';

class AutomationResult {
  final bool success;
  final String message;

  const AutomationResult(this.success, this.message);
}

class NativeSpeechResult {
  final bool success;
  final String text;
  final String message;

  const NativeSpeechResult({
    required this.success,
    this.text = '',
    this.message = '',
  });
}

class AutomationService {
  static const MethodChannel _channel =
      MethodChannel('iron_music_420/automations');
  static bool _nativeHandlerInstalled = false;
  static void Function(String text)? _nativeSpeechPartialListener;

  AutomationService() {
    _installNativeHandler();
  }

  static void _installNativeHandler() {
    if (_nativeHandlerInstalled) return;
    _nativeHandlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'chatSpeechPartial') {
        final arguments = call.arguments;
        if (arguments is Map) {
          final text = arguments['text']?.toString().trim() ?? '';
          if (text.isNotEmpty) _nativeSpeechPartialListener?.call(text);
        }
      }
    });
  }

  void setNativeSpeechPartialListener(void Function(String text)? listener) {
    _nativeSpeechPartialListener = listener;
  }

  Future<NativeSpeechResult> startNativeSpeechRecognition() async {
    try {
      final text = await _channel.invokeMethod<String>(
        'startChatSpeechRecognition',
      );
      return NativeSpeechResult(
        success: true,
        text: text?.trim() ?? '',
      );
    } on PlatformException catch (error) {
      if (error.code == 'CHAT_SPEECH_CANCELLED') {
        return const NativeSpeechResult(success: false);
      }
      return NativeSpeechResult(
        success: false,
        message: error.message ??
            'Гласовото разпознаване не можа да стартира.',
      );
    } catch (_) {
      return const NativeSpeechResult(
        success: false,
        message: 'Възникна проблем с гласовото разпознаване.',
      );
    }
  }

  Future<void> stopNativeSpeechRecognition() async {
    try {
      await _channel.invokeMethod<bool>('stopChatSpeechRecognition');
    } catch (_) {
      // The pending recognition request will return its own final state.
    }
  }

  Future<void> cancelNativeSpeechRecognition() async {
    try {
      await _channel.invokeMethod<bool>('cancelChatSpeechRecognition');
    } catch (_) {
      // Safe during page disposal and typed-message submission.
    }
  }

  Future<void> syncGeminiApiKey(String apiKey) async {
    try {
      await _channel.invokeMethod<bool>('syncGeminiApiKey', {
        'apiKey': apiKey.trim(),
      });
    } catch (_) {
      // The chat remains usable even if native voice sync is unavailable.
    }
  }

  Future<void> syncAiProviderSettings({
    required String geminiApiKey,
    required String backupApiKey,
    required String backupBaseUrl,
    required String backupModel,
  }) async {
    try {
      await _channel.invokeMethod<bool>('syncAiProviderSettings', {
        'geminiApiKey': geminiApiKey.trim(),
        'backupApiKey': backupApiKey.trim(),
        'backupBaseUrl': backupBaseUrl.trim(),
        'backupModel': backupModel.trim(),
      });
    } catch (_) {
      // Flutter chat and studio remain usable even if native sync is unavailable.
    }
  }

  Future<bool> isIronVoiceActive() async {
    try {
      final state = await _channel.invokeMethod<String>('execute', {
        'action': 'iron_voice_status',
      });
      return state == 'active';
    } catch (_) {
      return false;
    }
  }

  Future<int?> consumeIronSection() async {
    try {
      return await _channel.invokeMethod<int>('consumeIronSection');
    } catch (_) {
      return null;
    }
  }

  Future<AutomationResult> execute(
    String action, {
    Map<String, dynamic> arguments = const <String, dynamic>{},
  }) async {
    try {
      final message = await _channel.invokeMethod<String>('execute', {
        'action': action,
        ...arguments,
      });
      return AutomationResult(true, message ?? 'Командата е изпълнена.');
    } on PlatformException catch (error) {
      return AutomationResult(
        false,
        error.message ?? 'Командата не може да бъде изпълнена.',
      );
    } catch (_) {
      return const AutomationResult(
        false,
        'Възникна проблем при изпълнението.',
      );
    }
  }
}
''', encoding='utf-8')

# Replace Flutter speech_to_text flow with the native MethodChannel flow.
chat = chat_path.read_text(encoding='utf-8')
chat = replace_once(
    chat,
    "import 'package:speech_to_text/speech_to_text.dart' as stt;\n",
    '',
    'remove speech_to_text import',
)
chat = replace_once(
    chat,
    "import '../services/speech_error_policy.dart';\n",
    '',
    'remove speech policy import',
)
chat = replace_once(
    chat,
    "  final stt.SpeechToText _speechToText = stt.SpeechToText();\n",
    '',
    'remove speech plugin field',
)
for field in [
    "  bool _speechAvailable = false;\n",
    "  bool _speechSendTriggered = false;\n",
    "  bool _speechHeard = false;\n",
    "  bool _speechRetryScheduled = false;\n",
    "  int _speechTimeoutRetryCount = 0;\n",
    "  String _bulgarianLocale = 'bg_BG';\n",
]:
    chat = replace_once(chat, field, '', f'remove obsolete field {field.strip()}')

chat = replace_once(
    chat,
    """    _configureBulgarianVoice();
    _prepareSpeechRecognition();
""",
    """    _configureBulgarianVoice();
    _automation.setNativeSpeechPartialListener((recognized) {
      if (!mounted || !_isListening) return;
      setState(() {
        _messageController.text = recognized;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
      });
    });
""",
    'install native speech listener',
)
chat = replace_once(
    chat,
    """    _flutterTts.stop();
    _speechToText.stop();
    _gemini.dispose();
""",
    """    _flutterTts.stop();
    _automation.setNativeSpeechPartialListener(null);
    _automation.cancelNativeSpeechRecognition();
    _gemini.dispose();
""",
    'dispose native speech',
)
chat = replace_between(
    chat,
    '  Future<void> _prepareSpeechRecognition() async {',
    '  Future<void> _speak(String text) async {',
    '',
    'remove Flutter speech preparation',
)

native_toggle = r'''  Future<void> _toggleListening() async {
    if (_isLoading) return;

    if (_isListening) {
      await _automation.stopNativeSpeechRecognition();
      return;
    }

    await _flutterTts.stop();
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;

    setState(() => _isListening = true);
    final result = await _automation.startNativeSpeechRecognition();
    if (!mounted) return;

    setState(() => _isListening = false);
    if (!result.success) {
      if (result.message.trim().isNotEmpty) {
        _showMessage(result.message.trim());
      }
      return;
    }

    final recognized = result.text.trim();
    if (recognized.isEmpty) {
      _showMessage('Не чух думи. Натисни микрофона и говори след сигнала.');
      return;
    }

    setState(() {
      _messageController.text = recognized;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
    });
    await _sendMessage();
  }

'''
chat = replace_between(
    chat,
    '  Future<void> _sendRecognizedSpeech() async {',
    '  Future<void> _syncNativeAiSettings() {',
    native_toggle,
    'replace Flutter speech interaction',
)
chat = replace_once(
    chat,
    """    await _speechToText.stop();

    final apiKey = widget.store.apiKey.trim();
""",
    """    if (_isListening) {
      await _automation.cancelNativeSpeechRecognition();
      if (mounted) setState(() => _isListening = false);
    }

    final apiKey = widget.store.apiKey.trim();
""",
    'cancel native speech before typed send',
)
chat_path.write_text(chat, encoding='utf-8')

# Add native Android SpeechRecognizer owned by MainActivity.
activity = activity_path.read_text(encoding='utf-8')
activity = replace_once(
    activity,
    """import android.os.Build
import android.provider.AlarmClock
import android.provider.Settings
import android.speech.SpeechRecognizer
""",
    """import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.AlarmClock
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
""",
    'native speech imports',
)
activity = replace_once(
    activity,
    """    private var pendingVoiceResult: MethodChannel.Result? = null
    private var pendingIronSection: Int? = null
""",
    """    private var pendingVoiceResult: MethodChannel.Result? = null
    private var pendingIronSection: Int? = null
    private var automationChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var chatSpeechRecognizer: SpeechRecognizer? = null
    private var pendingChatSpeechResult: MethodChannel.Result? = null
    private var chatSpeechLastPartial = ""
    private var chatSpeechStopRequested = false
    private var restoreIronVoiceAfterChatSpeech = false
    private val chatSpeechTimeout = Runnable {
        finishChatSpeech(
            errorCode = "CHAT_SPEECH_TIMEOUT",
            errorMessage = "Не чух реч навреме. Натисни микрофона и говори след сигнала.",
        )
    }
""",
    'native speech fields',
)
activity = replace_once(
    activity,
    """        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
""",
    """        automationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        automationChannel?.setMethodCallHandler { call, result ->
""",
    'store method channel',
)
activity = replace_once(
    activity,
    """                    "syncAiProviderSettings" -> {
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
    """                    "syncAiProviderSettings" -> {
                        syncAiProviderSettings(
                            geminiApiKey = call.argument<String>("geminiApiKey").orEmpty(),
                            backupApiKey = call.argument<String>("backupApiKey").orEmpty(),
                            backupBaseUrl = call.argument<String>("backupBaseUrl").orEmpty(),
                            backupModel = call.argument<String>("backupModel").orEmpty(),
                            result = result,
                        )
                    }
                    "startChatSpeechRecognition" -> {
                        startChatSpeechRecognition(result)
                    }
                    "stopChatSpeechRecognition" -> {
                        stopChatSpeechRecognition(result)
                    }
                    "cancelChatSpeechRecognition" -> {
                        cancelChatSpeechRecognition(result)
                    }
                    else -> result.notImplemented()
""",
    'native speech method channel routes',
)

native_methods = r'''    private fun startChatSpeechRecognition(result: MethodChannel.Result) {
        if (pendingChatSpeechResult != null) {
            result.error(
                "CHAT_SPEECH_BUSY",
                "Микрофонът вече слуша.",
                null,
            )
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error(
                "CHAT_SPEECH_UNAVAILABLE",
                "На телефона няма активна Android услуга за разпознаване на реч.",
                null,
            )
            return
        }

        pendingChatSpeechResult = result
        if (
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                4203,
            )
            return
        }
        prepareChatSpeechRecognition()
    }

    private fun prepareChatSpeechRecognition() {
        restoreIronVoiceAfterChatSpeech = IronVoiceService.isRunning
        if (restoreIronVoiceAfterChatSpeech) {
            stopService(
                Intent(this, IronVoiceService::class.java).apply {
                    action = IronVoiceService.ACTION_STOP
                },
            )
        }

        val releaseDelay = if (restoreIronVoiceAfterChatSpeech) 950L else 120L
        mainHandler.postDelayed({ launchChatSpeechRecognizer() }, releaseDelay)
    }

    private fun launchChatSpeechRecognizer() {
        if (pendingChatSpeechResult == null || isFinishing || isDestroyed) {
            finishChatSpeech(
                errorCode = "CHAT_SPEECH_CANCELLED",
                errorMessage = "Гласовото разпознаване беше прекратено.",
            )
            return
        }

        chatSpeechLastPartial = ""
        chatSpeechStopRequested = false
        val recognizer = SpeechRecognizer.createSpeechRecognizer(this)
        chatSpeechRecognizer = recognizer
        recognizer.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                automationChannel?.invokeMethod(
                    "chatSpeechStatus",
                    mapOf("status" to "ready"),
                )
            }

            override fun onBeginningOfSpeech() {
                automationChannel?.invokeMethod(
                    "chatSpeechStatus",
                    mapOf("status" to "speaking"),
                )
            }

            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() = Unit

            override fun onError(error: Int) {
                if (
                    chatSpeechStopRequested &&
                    chatSpeechLastPartial.isNotBlank()
                ) {
                    finishChatSpeech(text = chatSpeechLastPartial)
                    return
                }

                val errorCode: String
                val message: String
                when (error) {
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
                    SpeechRecognizer.ERROR_NO_MATCH -> {
                        errorCode = "CHAT_SPEECH_NO_MATCH"
                        message = "Не чух ясни думи. Натисни микрофона и говори след сигнала."
                    }
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> {
                        errorCode = "CHAT_SPEECH_BUSY"
                        message = "Микрофонът още се освобождава. Опитай отново след секунда."
                    }
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                        errorCode = "CHAT_SPEECH_PERMISSION"
                        message = "Разреши достъп до микрофона за Iron Music 420 AI."
                    }
                    SpeechRecognizer.ERROR_NETWORK,
                    SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                    SpeechRecognizer.ERROR_SERVER -> {
                        errorCode = "CHAT_SPEECH_NETWORK"
                        message = "Android разпознаването на реч няма връзка. Провери Google Speech Services и интернета."
                    }
                    SpeechRecognizer.ERROR_AUDIO -> {
                        errorCode = "CHAT_SPEECH_AUDIO"
                        message = "Android не успя да отвори микрофона."
                    }
                    SpeechRecognizer.ERROR_CLIENT -> {
                        errorCode = if (chatSpeechStopRequested) {
                            "CHAT_SPEECH_CANCELLED"
                        } else {
                            "CHAT_SPEECH_CLIENT"
                        }
                        message = if (chatSpeechStopRequested) {
                            "Гласовото разпознаване беше прекратено."
                        } else {
                            "Android прекрати гласовото разпознаване."
                        }
                    }
                    else -> {
                        errorCode = "CHAT_SPEECH_ERROR"
                        message = "Гласовото разпознаване върна грешка $error."
                    }
                }
                finishChatSpeech(
                    errorCode = errorCode,
                    errorMessage = message,
                )
            }

            override fun onResults(results: Bundle?) {
                val text = bestRecognitionText(results)
                    .ifBlank { chatSpeechLastPartial }
                if (text.isBlank()) {
                    finishChatSpeech(
                        errorCode = "CHAT_SPEECH_NO_MATCH",
                        errorMessage = "Не чух ясни думи. Натисни микрофона и говори след сигнала.",
                    )
                } else {
                    finishChatSpeech(text = text)
                }
            }

            override fun onPartialResults(partialResults: Bundle?) {
                val text = bestRecognitionText(partialResults)
                if (text.isBlank()) return
                chatSpeechLastPartial = text
                automationChannel?.invokeMethod(
                    "chatSpeechPartial",
                    mapOf("text" to text),
                )
            }

            override fun onEvent(eventType: Int, params: Bundle?) = Unit
        })

        val recognitionIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "bg-BG")
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "bg-BG")
            putExtra(RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, false)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS,
                1_200L,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                2_500L,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                4_000L,
            )
        }

        try {
            recognizer.startListening(recognitionIntent)
            mainHandler.postDelayed(chatSpeechTimeout, 45_000L)
        } catch (error: Exception) {
            finishChatSpeech(
                errorCode = "CHAT_SPEECH_START_ERROR",
                errorMessage = error.localizedMessage
                    ?: "Android не успя да стартира микрофона.",
            )
        }
    }

    private fun bestRecognitionText(results: Bundle?): String {
        return results
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            .orEmpty()
            .trim()
    }

    private fun stopChatSpeechRecognition(result: MethodChannel.Result) {
        val recognizer = chatSpeechRecognizer
        if (recognizer == null || pendingChatSpeechResult == null) {
            result.success(false)
            return
        }
        chatSpeechStopRequested = true
        try {
            recognizer.stopListening()
            result.success(true)
        } catch (error: Exception) {
            result.error(
                "CHAT_SPEECH_STOP_ERROR",
                error.localizedMessage ?: "Микрофонът не можа да бъде спрян.",
                null,
            )
        }
    }

    private fun cancelChatSpeechRecognition(result: MethodChannel.Result) {
        if (pendingChatSpeechResult == null) {
            result.success(false)
            return
        }
        chatSpeechStopRequested = true
        try {
            chatSpeechRecognizer?.cancel()
        } catch (_: Exception) {
            // Recognizer may already have stopped.
        }
        finishChatSpeech(
            errorCode = "CHAT_SPEECH_CANCELLED",
            errorMessage = "Гласовото разпознаване беше прекратено.",
        )
        result.success(true)
    }

    private fun finishChatSpeech(
        text: String? = null,
        errorCode: String? = null,
        errorMessage: String? = null,
    ) {
        val pendingResult = pendingChatSpeechResult ?: return
        pendingChatSpeechResult = null
        mainHandler.removeCallbacks(chatSpeechTimeout)

        val recognizer = chatSpeechRecognizer
        chatSpeechRecognizer = null
        try {
            recognizer?.cancel()
        } catch (_: Exception) {
            // Recognition may already be complete.
        }
        try {
            recognizer?.destroy()
        } catch (_: Exception) {
            // Recognition may already be destroyed.
        }

        if (errorCode == null) {
            pendingResult.success(text.orEmpty().trim())
        } else {
            pendingResult.error(errorCode, errorMessage, null)
        }
        automationChannel?.invokeMethod(
            "chatSpeechStatus",
            mapOf("status" to "done"),
        )

        val shouldRestore = restoreIronVoiceAfterChatSpeech
        restoreIronVoiceAfterChatSpeech = false
        chatSpeechLastPartial = ""
        chatSpeechStopRequested = false
        if (shouldRestore &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            mainHandler.postDelayed(
                {
                    ContextCompat.startForegroundService(
                        this,
                        Intent(this, IronVoiceService::class.java).apply {
                            action = IronVoiceService.ACTION_START
                        },
                    )
                },
                350L,
            )
        }
    }

'''
activity = replace_once(
    activity,
    '    private fun syncGeminiApiKey(\n',
    native_methods + '    private fun syncGeminiApiKey(\n',
    'insert native speech methods',
)
activity = replace_once(
    activity,
    """            4202 -> {
                val result = pendingVoiceResult ?: return
                pendingVoiceResult = null
                if (
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    try {
                        launchIronVoiceService(result)
                    } catch (error: Exception) {
                        result.error("IRON_VOICE_ERROR", error.localizedMessage, null)
                    }
                } else {
                    result.error(
                        "MICROPHONE_PERMISSION",
                        "Разреши микрофона, за да работи „Hey Iron“.",
                        null
                    )
                }
            }
""",
    """            4202 -> {
                val result = pendingVoiceResult ?: return
                pendingVoiceResult = null
                if (
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    try {
                        launchIronVoiceService(result)
                    } catch (error: Exception) {
                        result.error("IRON_VOICE_ERROR", error.localizedMessage, null)
                    }
                } else {
                    result.error(
                        "MICROPHONE_PERMISSION",
                        "Разреши микрофона, за да работи „Hey Iron“.",
                        null
                    )
                }
            }
            4203 -> {
                if (
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO,
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    prepareChatSpeechRecognition()
                } else {
                    finishChatSpeech(
                        errorCode = "CHAT_SPEECH_PERMISSION",
                        errorMessage = "Разреши достъп до микрофона за Iron Music 420 AI.",
                    )
                }
            }
""",
    'chat speech permission result',
)
activity_path.write_text(activity, encoding='utf-8')

# Version and changelog.
pubspec = pubspec_path.read_text(encoding='utf-8')
pubspec = replace_once(
    pubspec,
    'version: 3.3.1+39',
    'version: 3.3.2+40',
    'version bump',
)
pubspec_path.write_text(pubspec, encoding='utf-8')

changelog_path.write_text('''# Iron Music 420 AI v3.3.2

- Replaces the AI chat microphone path with Android's native `SpeechRecognizer` using Bulgarian `bg-BG`.
- Stops the background Hey Iron service before chat dictation so its `AudioRecord` releases the microphone.
- Returns partial and final recognized text to Flutter through the existing MethodChannel.
- Restarts Hey Iron automatically after recognition, cancellation, timeout, or error when it was previously active.
- Removes the chat dependency on the Flutter `speech_to_text` runtime path.
- Gemini/Groq fallback, local commands, wake-word assets, UI, and the action allow-list are unchanged.
- Version: `3.3.2+40`.
''', encoding='utf-8')

print('v3.3.2 native Android speech migration applied successfully')
