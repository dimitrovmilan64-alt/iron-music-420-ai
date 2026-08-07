import 'package:flutter/services.dart';

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

class StudioVoiceRequest {
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

  Future<bool> pauseIronVoiceCapture() async {
    try {
      return await _channel.invokeMethod<bool>('pauseIronVoiceCapture') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> resumeIronVoiceCapture() async {
    try {
      await _channel.invokeMethod<bool>('resumeIronVoiceCapture');
    } catch (_) {
      // Voice playback must not affect the text response.
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

  Future<bool?> flashlightState() async {
    try {
      return await _channel.invokeMethod<bool>('execute', {
        'action': 'flash_status',
      });
    } catch (_) {
      return null;
    }
  }

  Future<bool> isYoutubeAutoPlayEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('execute', {
            'action': 'youtube_autoplay_status',
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<AutomationResult> openYoutubeAutoPlaySettings() =>
      execute('youtube_autoplay_settings');

  Future<int?> consumeIronSection() async {
    try {
      return await _channel.invokeMethod<int>('consumeIronSection');
    } catch (_) {
      return null;
    }
  }

  Future<StudioVoiceRequest?> consumeStudioVoiceRequest() async {
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
