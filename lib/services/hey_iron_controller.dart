import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const MethodChannel _channel = MethodChannel('iron_music_420/hey_iron');
  static const EventChannel _events =
      EventChannel('iron_music_420/hey_iron_events');
  static const String modelLabel = 'sherpa-onnx-kws-zipformer-zh-en-3M';
  static const int modelBytes = 32885699;

  static const _prefEnabled = 'hey_iron_v2_enabled';
  static const _prefBackground = 'hey_iron_v2_background';
  static const _prefWatchdog = 'hey_iron_v2_watchdog';

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
        return 'Грешка';
      case HeyIronPhase.blocked:
        return 'Спрян автоматично (защита на телефона)';
    }
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
          ? 'Моделът е готов. Слушането започва, когато екранът е активен.'
          : 'Трябва да се изтегли офлайн модел (${formatSize(modelBytes)}).';
      phase = modelReady ? HeyIronPhase.ready : HeyIronPhase.off;
    } else {
      phase = HeyIronPhase.off;
      message = '„Хей Айрън“ е изключен. Работи само докато приложението е отворено.';
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
        await _channel.invokeMethod('startBackground');
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
    message =
        'Изтегляне на офлайн модела (${formatSize(modelBytes)}). Нужен е интернет само сега.';
    notifyListeners();
    try {
      final ok = await _channel.invokeMethod<bool>('downloadModel');
      modelReady = ok == true;
      if (!modelReady) {
        await _fail('Изтеглянето на модела не успя.');
        return false;
      }
      phase = HeyIronPhase.ready;
      message = 'Моделът е готов.';
      notifyListeners();
      return true;
    } on PlatformException catch (error) {
      await _fail(error.message ?? 'Изтеглянето на модела не успя.');
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
      await _channel.invokeMethod('start', {
        'background': backgroundExperimental,
      });
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
    _stallTimer?.cancel();
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    if (clean) {
      watchdog.markCleanStop();
      await _persistWatchdog();
    }
  }

  Future<void> _fail(String reason) async {
    _stallTimer?.cancel();
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
      if (watchdog.isStalled) {
        await _fail(
          'Слушането спря да отговаря (подозрение за забиване). Функцията е поставена на пауза.',
        );
      }
    });
  }

  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type']?.toString();
    switch (type) {
      case 'progress':
        final received = (event['received'] as num?)?.toDouble() ?? 0;
        final total = (event['total'] as num?)?.toDouble() ?? modelBytes.toDouble();
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
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
        onWakeWord?.call();
        notifyListeners();
        break;
      case 'listening':
        phase = HeyIronPhase.listening;
        notifyListeners();
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

  @override
  void dispose() {
    _stallTimer?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }
}
