import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'error_log.dart';
import 'hey_iron_watchdog.dart';

enum HeyIronPhase {
  off,
  downloading,
  ready,
  listening,
  error,
  blocked,
}

class HeyIronController extends ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('iron_music_420/hey_iron');
  static const EventChannel _events =
      EventChannel('iron_music_420/hey_iron_events');
  static const String modelLabel = 'sherpa-onnx-kws-zipformer-zh-en-3M';
  static const int modelBytes = 32885699;

  static const _prefEnabled = 'hey_iron_v2_enabled';
  static const _prefBackground = 'hey_iron_v2_background';
  static const _prefWatchdog = 'hey_iron_v2_watchdog';
  static const _prefBackgroundApi36Off = 'hey_iron_v2_background_api36_off';

  HeyIronWatchdog watchdog = HeyIronWatchdog();
  HeyIronPhase phase = HeyIronPhase.off;
  String message = '„Хей Айрън“ е изключен.';
  double downloadProgress = 0;
  bool enabled = false;
  bool backgroundExperimental = false;
  bool modelReady = false;
  StreamSubscription<dynamic>? _eventsSub;
  Timer? _stallTimer;
  VoidCallback? onWakeWord;
  DateTime? lastWakeAt;
  DateTime? lastDetectionAt;
  String? lastDetectedKeyword;
  double micLevel = 0;
  String micTestMessage = '';
  bool micTestBusy = false;
  bool _stopping = false;
  bool _holdingMicForSpeech = false;
  bool _restartingAfterStall = false;
  DateTime? _lastMicNotifyAt;
  int? androidSdk;

  String get statusLabel {
    switch (phase) {
      case HeyIronPhase.off:
        return 'Изключен';
      case HeyIronPhase.downloading:
        final pct = (downloadProgress * 100).clamp(0, 100).round();
        return 'Изтегляне $pct%';
      case HeyIronPhase.ready:
        return 'Готов • не слуша';
      case HeyIronPhase.listening:
        return backgroundExperimental
            ? 'Слуша (и на заден план, експериментално)'
            : 'Слуша, докато приложението е отворено';
      case HeyIronPhase.error:
        final detail = _shortError(message);
        return detail.isEmpty ? 'Хей Айрън: грешка' : 'Хей Айрън: $detail';
      case HeyIronPhase.blocked:
        return 'Спрян автоматично (защита на телефона)';
    }
  }

  /// 0-1 meter driven by live RMS, or the last mic test.
  double get micMeterValue => (micLevel / 0.08).clamp(0.0, 1.0);

  String get micLevelLabel {
    if (micLevel <= 0 && phase != HeyIronPhase.listening) {
      return 'Ниво на микрофона: няма сигнал';
    }
    final pct = (micMeterValue * 100).round();
    return 'Ниво на микрофона: $pct%';
  }

  String get lastDetectionLabel {
    final at = lastDetectionAt ?? lastWakeAt;
    final keyword = lastDetectedKeyword;
    if (at == null && (keyword == null || keyword.isEmpty)) {
      return 'Последно разпознаване: няма';
    }
    final label = (keyword == null || keyword.isEmpty) ? 'Хей Айрън' : keyword;
    final time = at == null ? '' : _formatClock(at);
    return time.isEmpty
        ? 'Последно разпознаване: $label'
        : 'Последно разпознаване: $label • $time';
  }

  static String formatSize(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_prefEnabled) ?? false;
    backgroundExperimental = prefs.getBool(_prefBackground) ?? false;
    final raw = prefs.getString(_prefWatchdog);
    if (raw != null && raw.isNotEmpty) {
      try {
        final parts = raw.split('|');
        watchdog = HeyIronWatchdog(
          failureCount: int.tryParse(parts.elementAt(0)) ?? 0,
          lastFailureAt: int.tryParse(parts.elementAt(1)) != null &&
                  (int.tryParse(parts.elementAt(1)) ?? 0) > 0
              ? DateTime.fromMillisecondsSinceEpoch(int.parse(parts[1]))
              : null,
          uncleanShutdown: parts.length > 2 && parts[2] == '1',
        );
      } catch (_) {
        watchdog = HeyIronWatchdog();
      }
    }
    watchdog.recoverFromPreviousSession();
    await _persistWatchdog();
    await _refreshAndroidSdk();
    final backgroundDisabledNotice =
        await _maybeDisableBackgroundOnApi36(prefs);

    _eventsSub ??= _events.receiveBroadcastStream().listen(_onNativeEvent);

    if (watchdog.isTripped) {
      enabled = false;
      phase = HeyIronPhase.blocked;
      message =
          '„Хей Айрън“ беше спрян автоматично, защото заби или се срина няколко пъти. Можеш да го включиш отново внимателно от Настройки.';
      await prefs.setBool(_prefEnabled, false);
      notifyListeners();
      return;
    }

    try {
      final info = await _channel.invokeMethod<Map<Object?, Object?>>('status');
      modelReady = info?['modelReady'] == true;
    } catch (_) {
      modelReady = false;
    }

    if (enabled) {
      message = modelReady
          ? 'Моделът е готов. Слушането ще започне веднага щом екранът е активен.'
          : 'Подготвям вградения офлайн модел.';
      phase = modelReady ? HeyIronPhase.ready : HeyIronPhase.off;
    } else {
      phase = HeyIronPhase.off;
      message =
          '„Хей Айрън“ е изключен. Работи само докато приложението е отворено.';
    }
    if (backgroundDisabledNotice != null) {
      message = backgroundDisabledNotice;
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (value && watchdog.isTripped) {
      phase = HeyIronPhase.blocked;
      message =
          'Защитата е все още активна. Нужен е ръчен ресет на защитата в Настройки.';
      notifyListeners();
      return;
    }
    enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, value);
    if (!value) {
      await stopListening(clean: true);
      phase = HeyIronPhase.off;
      message = '„Хей Айрън“ е изключен.';
      notifyListeners();
      return;
    }
    final ready = await _ensureModel();
    if (!ready) return;
    await startListening();
  }

  Future<void> setBackgroundExperimental(bool value) async {
    backgroundExperimental = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBackground, value);
    try {
      await _channel.invokeMethod('setBackground', {'enabled': value});
    } catch (_) {}
    if (enabled && phase == HeyIronPhase.listening) {
      await startListening();
    }
    notifyListeners();
  }

  Future<void> resetWatchdog() async {
    watchdog.reset();
    await _persistWatchdog();
    if (phase == HeyIronPhase.blocked) {
      phase = HeyIronPhase.off;
      message = 'Защитата е нулирана. Можеш да включиш „Хей Айрън“ отново.';
    }
    notifyListeners();
  }

  Future<void> handleAppResumed() async {
    if (!enabled || watchdog.isTripped) return;
    if (phase == HeyIronPhase.downloading) return;
    final ready = await _ensureModel(autoStart: false);
    if (ready) await startListening();
  }

  Future<void> handleAppPaused() async {
    if (!enabled) return;
    if (backgroundExperimental) {
      try {
        // Release the in-app AudioRecord before the service takes the mic.
        await _channel.invokeMethod('stopEngine');
        await _channel.invokeMethod('startBackground');
        phase = HeyIronPhase.listening;
        message = 'Слуша на заден план (експериментално).';
        notifyListeners();
      } catch (error) {
        await _fail('Фоновият режим не можа да стартира: $error');
      }
      return;
    }
    await stopListening(clean: true);
    if (enabled && modelReady) {
      phase = HeyIronPhase.ready;
      message = 'На пауза, докато приложението е на заден план.';
      notifyListeners();
    }
  }

  Map<String, dynamic> _asResult(dynamic value) {
    if (value is Map) {
      return {
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
    }
    if (value == true) return const {'ok': true};
    return const {'ok': false};
  }

  bool get isModelLoadError {
    final lower = message.toLowerCase();
    return lower.contains('модел') ||
        lower.contains('файл') ||
        lower.contains('вграден');
  }

  Future<bool> _ensureModel({bool autoStart = true}) async {
    try {
      final info = await _channel.invokeMethod<Map<Object?, Object?>>('status');
      modelReady = info?['modelReady'] == true;
    } catch (_) {
      modelReady = false;
    }
    if (modelReady) return true;

    phase = HeyIronPhase.downloading;
    downloadProgress = 0;
    message = 'Подготвям офлайн модела за „Хей Айрън“…';
    notifyListeners();
    try {
      final result = _asResult(await _channel.invokeMethod('prepareModel'));
      modelReady = result['ok'] == true;
      if (!modelReady) {
        await _fail(
          result['error']?.toString() ?? 'Моделът не можа да се подготви.',
        );
        return false;
      }
      phase = HeyIronPhase.ready;
      message = result['source'] == 'download'
          ? 'Моделът е изтеглен и е готов.'
          : 'Моделът е готов.';
      notifyListeners();
      return true;
    } on PlatformException catch (error) {
      await _fail(error.message ?? 'Моделът не можа да се подготви.');
      return false;
    }
  }

  Future<void> startListening() async {
    if (!enabled || watchdog.isTripped) return;
    if (!modelReady) {
      final ready = await _ensureModel();
      if (!ready) return;
    }
    try {
      watchdog.markStarted();
      await _persistWatchdog();
      final result = _asResult(
        await _channel.invokeMethod('start', {
          'background': backgroundExperimental,
        }),
      );
      if (result['ok'] != true) {
        await _fail(
          result['error']?.toString() ?? 'Слушането не можа да стартира.',
        );
        return;
      }
      phase = HeyIronPhase.listening;
      message = backgroundExperimental
          ? 'Слуша за „Хей Айрън“. Фоновият режим е експериментален и може да натовари слаби телефони.'
          : 'Слуша за „Хей Айрън“, докато приложението е отворено.';
      _armStallTimer();
      notifyListeners();
    } on PlatformException catch (error) {
      await _fail(error.message ?? 'Слушането не можа да стартира.');
    }
  }

  Future<void> stopListening({bool clean = false}) async {
    _stopping = true;
    _stallTimer?.cancel();
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    micLevel = 0;
    if (clean) {
      watchdog.markCleanStop();
      await _persistWatchdog();
    } else if (enabled && modelReady && phase == HeyIronPhase.listening) {
      phase = HeyIronPhase.ready;
    }
    _stopping = false;
    notifyListeners();
  }

  Future<void> testMicrophone() async {
    if (micTestBusy) return;
    micTestBusy = true;
    micTestMessage = 'Тествам микрофона…';
    notifyListeners();
    try {
      final result = _asResult(await _channel.invokeMethod('testMic'));
      final rms = (result['rms'] as num?)?.toDouble() ?? 0;
      final peak = (result['peak'] as num?)?.toDouble() ?? rms;
      micLevel = peak > 0 ? peak : rms;
      if (result['ok'] == true) {
        if (micLevel <= 0.001) {
          micTestMessage =
              'Микрофонът работи, но почти няма звук. Кажи нещо и натисни отново.';
        } else {
          final pct = ((micLevel / 0.08).clamp(0, 1) * 100).round();
          micTestMessage = 'Микрофонът работи. Ниво: $pct%.';
        }
      } else {
        micTestMessage =
            result['error']?.toString() ?? 'Тестът на микрофона не успя.';
      }
    } on PlatformException catch (error) {
      micTestMessage = error.message ?? 'Тестът на микрофона не успя.';
    } catch (error) {
      micTestMessage = 'Тестът на микрофона не успя: $error';
    } finally {
      micTestBusy = false;
      notifyListeners();
    }
  }

  Future<void> _fail(String reason) async {
    _stallTimer?.cancel();
    AppErrorLog.instance.record(source: 'Хей Айрън', message: reason);
    watchdog.recordFailure();
    await _persistWatchdog();
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    if (watchdog.isTripped) {
      enabled = false;
      phase = HeyIronPhase.blocked;
      message =
          '„Хей Айрън“ беше спрян автоматично след повторни сривове или забивания. $reason';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefEnabled, false);
    } else {
      phase = HeyIronPhase.error;
      message = reason;
    }
    notifyListeners();
  }

  void _armStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_holdingMicForSpeech || _restartingAfterStall || _stopping) {
        return;
      }
      if (watchdog.canAutoRestartOnStall) {
        watchdog.markStallRestart();
        await _persistWatchdog();
        await _restartAfterStall();
        return;
      }
      if (watchdog.isStalled) {
        await _fail(
          'Слушането спря да отговаря (подозрение за забиване). Функцията е поставена на пауза.',
        );
      }
    });
  }

  Future<void> _restartAfterStall() async {
    if (_restartingAfterStall) return;
    _restartingAfterStall = true;
    message = 'Слушането засече забиване. Рестартирам микрофона още веднъж…';
    notifyListeners();
    try {
      await _channel.invokeMethod('stop');
      if (!enabled || watchdog.isTripped) return;
      await startListening();
    } catch (error) {
      await _fail('Слушането не можа да се рестартира: $error');
    } finally {
      _restartingAfterStall = false;
    }
  }

  Future<void> yieldMicForSpeech() async {
    _holdingMicForSpeech = true;
    _stallTimer?.cancel();
    watchdog.markCleanStop();
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    micLevel = 0;
    if (enabled && modelReady) {
      phase = HeyIronPhase.ready;
      message = 'Отстъпвам микрофона за разпознаване на реч.';
    }
    notifyListeners();
  }

  Future<void> resumeAfterSpeech() async {
    _holdingMicForSpeech = false;
    if (!enabled || watchdog.isTripped) return;
    await startListening();
  }

  Future<void> _refreshAndroidSdk() async {
    try {
      final info = await _channel.invokeMethod<String>('deviceInfo');
      final match = RegExp(r'API\s+(\d+)').firstMatch(info ?? '');
      if (match != null) {
        androidSdk = int.tryParse(match.group(1)!);
      }
    } catch (_) {
      // Tests and older bridges may not implement deviceInfo.
    }
  }

  Future<String?> _maybeDisableBackgroundOnApi36(
    SharedPreferences prefs,
  ) async {
    final sdk = androidSdk ?? 0;
    if (sdk < 36) return null;
    if (prefs.getBool(_prefBackgroundApi36Off) == true) return null;
    await prefs.setBool(_prefBackgroundApi36Off, true);
    if (!backgroundExperimental) return null;
    backgroundExperimental = false;
    await prefs.setBool(_prefBackground, false);
    try {
      await _channel.invokeMethod('setBackground', {'enabled': false});
    } catch (_) {}
    return 'Фоновото слушане е изключено на Android 16, защото микрофонът се блокира. „Хей Айрън“ работи, докато приложението е отворено.';
  }

  @visibleForTesting
  void handleNativeEventForTest(dynamic event) => _onNativeEvent(event);

  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type']?.toString();
    switch (type) {
      case 'progress':
        final received = (event['received'] as num?)?.toDouble() ?? 0;
        final total =
            (event['total'] as num?)?.toDouble() ?? modelBytes.toDouble();
        downloadProgress = total <= 0 ? 0 : (received / total).clamp(0, 1);
        phase = HeyIronPhase.downloading;
        message =
            'Изтегляне ${(downloadProgress * 100).round()}% от ${formatSize(total.round())}…';
        notifyListeners();
        break;
      case 'heartbeat':
        watchdog.markHeartbeat();
        break;
      case 'detected':
        watchdog.markHeartbeat();
        lastWakeAt = DateTime.now();
        lastDetectionAt = lastWakeAt;
        lastDetectedKeyword = event['keyword']?.toString();
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
        onWakeWord?.call();
        notifyListeners();
        break;
      case 'micLevel':
        final rms = (event['rms'] as num?)?.toDouble() ?? 0;
        micLevel = rms;
        final now = DateTime.now();
        final last = _lastMicNotifyAt;
        if (last == null || now.difference(last).inMilliseconds >= 200) {
          _lastMicNotifyAt = now;
          notifyListeners();
        }
        break;
      case 'listening':
        phase = HeyIronPhase.listening;
        message = backgroundExperimental
            ? 'Слуша за „Хей Айрън“. Фоновият режим е експериментален и може да натовари слаби телефони.'
            : 'Слуша за „Хей Айрън“, докато приложението е отворено.';
        notifyListeners();
        break;
      case 'stopped':
        micLevel = 0;
        if (!_stopping &&
            enabled &&
            phase == HeyIronPhase.listening &&
            !backgroundExperimental) {
          phase = HeyIronPhase.ready;
          message = 'Слушането спря.';
          notifyListeners();
        }
        break;
      case 'error':
        unawaited(_fail(event['message']?.toString() ?? 'Неизвестна грешка.'));
        break;
    }
  }

  Future<void> _persistWatchdog() async {
    final prefs = await SharedPreferences.getInstance();
    final last = watchdog.lastFailureAt?.millisecondsSinceEpoch ?? 0;
    await prefs.setString(
      _prefWatchdog,
      '${watchdog.failureCount}|$last|${watchdog.uncleanShutdown ? 1 : 0}',
    );
  }

  String _formatClock(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _shortError(String value) {
    var trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final newlineAt = trimmed.indexOf('\n');
    if (newlineAt >= 0) {
      trimmed = trimmed.substring(0, newlineAt).trim();
    }
    final periodAt = trimmed.indexOf('.');
    if (periodAt > 0) {
      trimmed = trimmed.substring(0, periodAt).trim();
    }
    if (trimmed.length <= 48) return trimmed;
    return '${trimmed.substring(0, 45)}…';
  }

  bool _recovering = false;

  /// Clears a sticky error and retries listening once, if still enabled.
  Future<void> recoverFromTransientError() async {
    if (_recovering) return;
    if (!enabled || watchdog.isTripped) return;
    if (phase != HeyIronPhase.error) return;
    if (isModelLoadError) return;
    _recovering = true;
    try {
      await startListening();
    } finally {
      _recovering = false;
    }
  }

  /// User-initiated retry: reinstall the bundled model and start listening.
  Future<void> retrySetup() async {
    if (watchdog.isTripped) {
      await resetWatchdog();
    }
    enabled = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, true);
    modelReady = false;
    phase = HeyIronPhase.off;
    message = 'Подготвям модела отново…';
    notifyListeners();
    final ready = await _ensureModel();
    if (!ready) return;
    await startListening();
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }
}
