// Behavioural tests for the Hey Iron v2 controller state machine and its
// watchdog, driven through fake native method/event channels. Only guarantees
// that live in Android config (manifest, Kotlin service flags) are checked
// statically, in the clearly-named group at the bottom.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ironmusic420ai/services/hey_iron_controller.dart';
import 'package:ironmusic420ai/services/hey_iron_watchdog.dart';
import 'package:ironmusic420ai/services/iron_voice_flags.dart';

const _method = MethodChannel('iron_music_420/hey_iron');
const _events = EventChannel('iron_music_420/hey_iron_events');
const _prefEnabled = 'hey_iron_v2_enabled';
const _prefWatchdog = 'hey_iron_v2_watchdog';

/// Fake of the Android side (HeyIronBridge) behind the platform channels.
class FakeHeyIronNative {
  bool modelReady = false;

  /// What `downloadModel` does: `true`/`false`, or a [PlatformException] to throw.
  Object downloadOutcome = true;
  PlatformException? startError;
  final List<String> calls = <String>[];
  final List<Object?> startArgs = <Object?>[];
  MockStreamHandlerEventSink? sink;

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    _messenger.setMockMethodCallHandler(_method, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'status':
          return <String, Object?>{'modelReady': modelReady, 'listening': false};
        case 'downloadModel':
          final outcome = downloadOutcome;
          if (outcome is PlatformException) throw outcome;
          modelReady = outcome == true;
          return outcome;
        case 'start':
          startArgs.add(call.arguments);
          if (startError != null) throw startError!;
          return true;
        default:
          return true;
      }
    });
    _messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(onListen: (_, events) => sink = events),
    );
    // Haptics / system click on wake word.
    _messenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  }

  void uninstall() {
    _messenger.setMockMethodCallHandler(_method, null);
    _messenger.setMockStreamHandler(_events, null);
    _messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  }

  Future<void> emit(Map<String, Object?> event) async {
    sink!.success(event);
    await pumpEventQueue();
  }

  int count(String method) => calls.where((c) => c == method).length;
}

Future<HeyIronController> _controller({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final controller = HeyIronController();
  await controller.initialize();
  return controller;
}

Future<String?> _storedWatchdog() async =>
    (await SharedPreferences.getInstance()).getString(_prefWatchdog);

String _watchdogPref(int failures, DateTime? last, {bool unclean = false}) =>
    '$failures|${last?.millisecondsSinceEpoch ?? 0}|${unclean ? 1 : 0}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHeyIronNative native;
  HeyIronController? controller;

  setUp(() {
    native = FakeHeyIronNative()..install();
  });

  tearDown(() async {
    controller?.dispose();
    controller = null;
    native.uninstall();
  });

  group('HeyIronWatchdog', () {
    test('trips after the third failure inside the window', () {
      final watchdog = HeyIronWatchdog();
      final now = DateTime.now();
      watchdog.recordFailure(now: now.subtract(const Duration(minutes: 2)));
      watchdog.recordFailure(now: now.subtract(const Duration(minutes: 1)));
      expect(watchdog.isTripped, isFalse);
      watchdog.recordFailure(now: now);
      expect(watchdog.isTripped, isTrue);
    });

    test('old failures outside the window do not trip it', () {
      final watchdog = HeyIronWatchdog();
      final old = DateTime.now().subtract(const Duration(days: 2));
      watchdog.recordFailure(now: old);
      watchdog.recordFailure(now: old);
      watchdog.recordFailure(now: DateTime.now());
      expect(watchdog.failureCount, 1);
      expect(watchdog.isTripped, isFalse);
    });

    test('round-trips through toMap/fromMap', () {
      final last = DateTime.fromMillisecondsSinceEpoch(1763600000000);
      final copy = HeyIronWatchdog.fromMap(
        HeyIronWatchdog(failureCount: 2, lastFailureAt: last, uncleanShutdown: true)
            .toMap(),
      );
      expect(copy.failureCount, 2);
      expect(copy.lastFailureAt, last);
      expect(copy.uncleanShutdown, isTrue);
    });
  });

  group('HeyIronController state machine', () {
    test('starts off and never touches the mic when disabled', () async {
      controller = await _controller();
      expect(controller!.phase, HeyIronPhase.off);
      expect(controller!.enabled, isFalse);
      expect(native.calls, isNot(contains('start')));
    });

    test('a tripped watchdog on launch blocks Hey Iron and persists "disabled"',
        () async {
      controller = await _controller(prefs: {
        _prefEnabled: true,
        _prefWatchdog: _watchdogPref(3, DateTime.now()),
      });
      expect(controller!.phase, HeyIronPhase.blocked);
      expect(controller!.enabled, isFalse);
      expect((await SharedPreferences.getInstance()).getBool(_prefEnabled), isFalse);
      expect(native.calls, isNot(contains('start')));

      await controller!.setEnabled(true);
      expect(controller!.phase, HeyIronPhase.blocked);
      expect(native.calls, isNot(contains('start')));
    });

    test('an unclean previous session counts as one failure on launch', () async {
      controller = await _controller(prefs: {
        _prefWatchdog: _watchdogPref(0, null, unclean: true),
      });
      expect(controller!.watchdog.failureCount, 1);
      expect(controller!.watchdog.uncleanShutdown, isFalse);
      expect(await _storedWatchdog(), startsWith('1|'));
      expect(await _storedWatchdog(), endsWith('|0'));
    });

    test('enabling downloads the model once, then listens in the foreground only',
        () async {
      controller = await _controller();
      await controller!.setEnabled(true);

      expect(native.count('downloadModel'), 1);
      expect(native.count('start'), 1);
      expect(native.startArgs.single, {'background': false});
      expect(controller!.phase, HeyIronPhase.listening);
      expect(controller!.backgroundExperimental, isFalse);
      // While listening the session is marked open, so a crash is detected later.
      expect(await _storedWatchdog(), endsWith('|1'));
    });

    test('a ready model is not downloaded again', () async {
      native.modelReady = true;
      controller = await _controller();
      await controller!.setEnabled(true);
      expect(native.count('downloadModel'), 0);
      expect(controller!.phase, HeyIronPhase.listening);
    });

    test('a corrupted model download ends in a clear error state, not listening',
        () async {
      native.downloadOutcome = PlatformException(
        code: 'MODEL_INTEGRITY',
        message: 'Изтегленият модел е повреден или подменен (SHA-256 контролната сума не съвпада). Опитай отново.',
      );
      controller = await _controller();
      await controller!.setEnabled(true);

      expect(controller!.phase, HeyIronPhase.error);
      expect(controller!.message, contains('SHA-256'));
      expect(controller!.modelReady, isFalse);
      expect(controller!.watchdog.failureCount, 1);
      expect(native.calls, isNot(contains('start')));
    });

    test('three failed attempts trip the watchdog and switch Hey Iron off', () async {
      native.downloadOutcome = false;
      controller = await _controller();
      await controller!.setEnabled(true);
      await controller!.setEnabled(true);
      expect(controller!.phase, HeyIronPhase.error);
      await controller!.setEnabled(true);

      expect(controller!.phase, HeyIronPhase.blocked);
      expect(controller!.enabled, isFalse);
      expect((await SharedPreferences.getInstance()).getBool(_prefEnabled), isFalse);
      expect(native.calls, isNot(contains('start')));

      await controller!.resetWatchdog();
      expect(controller!.phase, HeyIronPhase.off);
      expect(controller!.watchdog.failureCount, 0);
    });

    test('a native start failure is reported and counted', () async {
      native.modelReady = true;
      native.startError = PlatformException(code: 'MIC', message: 'Микрофонът е зает.');
      controller = await _controller();
      await controller!.setEnabled(true);
      expect(controller!.phase, HeyIronPhase.error);
      expect(controller!.message, 'Микрофонът е зает.');
      expect(controller!.watchdog.failureCount, 1);
    });

    test('disabling stops the engine and records a clean stop', () async {
      native.modelReady = true;
      controller = await _controller();
      await controller!.setEnabled(true);
      await controller!.setEnabled(false);

      expect(native.calls.last, 'stop');
      expect(controller!.phase, HeyIronPhase.off);
      expect(await _storedWatchdog(), endsWith('|0'));
    });

    test('going to background pauses listening unless background mode is opted in',
        () async {
      native.modelReady = true;
      controller = await _controller();
      await controller!.setEnabled(true);

      await controller!.handleAppPaused();
      expect(native.calls.last, 'stop');
      expect(native.calls, isNot(contains('startBackground')));
      expect(controller!.phase, HeyIronPhase.ready);

      await controller!.handleAppResumed();
      expect(controller!.phase, HeyIronPhase.listening);

      await controller!.setBackgroundExperimental(true);
      await controller!.handleAppPaused();
      expect(native.calls.last, 'startBackground');
    });

    test('native events drive progress, wake word and errors', () async {
      native.modelReady = true;
      controller = await _controller();
      var wakes = 0;
      controller!.onWakeWord = () => wakes++;
      await controller!.setEnabled(true);

      await native.emit({'type': 'progress', 'received': 50, 'total': 200});
      expect(controller!.phase, HeyIronPhase.downloading);
      expect(controller!.downloadProgress, closeTo(0.25, 1e-9));

      await native.emit({'type': 'listening'});
      await native.emit({'type': 'detected', 'keyword': 'HEY_IRON_BG'});
      expect(wakes, 1);
      expect(controller!.lastWakeAt, isNotNull);

      await native.emit({'type': 'error', 'message': 'AudioRecord fail'});
      expect(controller!.phase, HeyIronPhase.error);
      expect(controller!.message, 'AudioRecord fail');
      expect(controller!.watchdog.failureCount, 1);
    });

    test('a missed heartbeat is treated as a stall and pauses listening', () async {
      native.modelReady = true;
      controller = await _controller();
      await controller!.setEnabled(true);
      expect(controller!.phase, HeyIronPhase.listening);

      controller!.watchdog.lastHeartbeatAt =
          DateTime.now().subtract(const Duration(minutes: 1));
      // The stall timer polls every 2 seconds.
      await Future<void>.delayed(const Duration(milliseconds: 2300));

      expect(controller!.phase, HeyIronPhase.error);
      expect(controller!.watchdog.failureCount, 1);
      expect(native.calls.last, 'stop');
    });
  });

  group('static Android guarantees (not reachable from Dart tests)', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    String serviceElement(String name) {
      final match = RegExp(
        r'<service\b[^>]*android:name="[^"]*\b' + name + r'"[^>]*>',
        dotAll: true,
      ).firstMatch(manifest);
      expect(match, isNotNull, reason: '$name must be declared in the manifest');
      return match!.group(0)!;
    }

    test('manifest: HeyIronForegroundService stops with the task', () {
      expect(serviceElement('HeyIronForegroundService'),
          contains('android:stopWithTask="true"'));
    });

    test('manifest: Impeller is disabled', () {
      expect(
        RegExp(
          r'android:name="io\.flutter\.embedding\.android\.EnableImpeller"\s+android:value="false"',
        ).hasMatch(manifest),
        isTrue,
      );
    });

    test('kotlin: HeyIronForegroundService never asks to be restarted (no START_STICKY)',
        () {
      final service = File(
        'android/app/src/main/kotlin/com/example/ironmusic420ai/HeyIronForegroundService.kt',
      ).readAsStringSync();
      expect(service, contains('START_NOT_STICKY'));
      expect(RegExp(r'return\s+START_STICKY\b').hasMatch(service), isFalse);
    });

    test('legacy IronVoiceService stays disabled on both sides', () {
      expect(ironVoiceServiceEnabled, isFalse);
      final old = File(
        'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
      ).readAsStringSync();
      expect(RegExp(r'const val SERVICE_ENABLED\s*=\s*false').hasMatch(old), isTrue);
    });

    test('APK bundle ships no KWS model files (downloaded on first enable)', () {
      final assets = Directory('android/app/src/main/assets');
      final bundled = assets.existsSync()
          ? assets
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.onnx'))
              .toList()
          : const <File>[];
      expect(bundled, isEmpty);
    });

    test('bundled keywords.txt is valid sherpa-onnx keyword syntax', () {
      final lines = File('assets/hey_iron/keywords.txt')
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .toList();
      expect(lines, isNotEmpty);
      final syntax = RegExp(r'^[A-Z0-9 ]+ :\d+(\.\d+)? #\d+(\.\d+)? @[A-Z_]+$');
      for (final line in lines) {
        expect(syntax.hasMatch(line), isTrue, reason: line);
      }
      expect(lines.any((l) => l.endsWith('@HEY_IRON_BG')), isTrue);
    });
  });
}
