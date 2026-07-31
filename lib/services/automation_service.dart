import 'package:flutter/services.dart';

class AutomationResult {
  final bool success;
  final String message;

  const AutomationResult(this.success, this.message);
}

class AutomationService {
  static const MethodChannel _channel =
      MethodChannel('iron_music_420/automations');

  Future<void> syncGeminiApiKey(String apiKey) async {
    try {
      await _channel.invokeMethod<bool>('syncGeminiApiKey', {
        'apiKey': apiKey.trim(),
      });
    } catch (_) {
      // The chat remains usable even if native voice sync is unavailable.
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
          false, 'Възникна проблем при изпълнението.');
    }
  }
}
