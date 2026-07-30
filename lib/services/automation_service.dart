import 'package:flutter/services.dart';

class AutomationResult {
  final bool success;
  final String message;

  const AutomationResult(this.success, this.message);
}

class AutomationService {
  static const MethodChannel _channel =
      MethodChannel('iron_music_420/automations');

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
      return const AutomationResult(false, 'Възникна проблем при изпълнението.');
    }
  }
}
