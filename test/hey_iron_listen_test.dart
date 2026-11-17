import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironmusic420ai/services/hey_iron_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('iron_music_420/hey_iron');
  const events = EventChannel('iron_music_420/hey_iron_events');

  late List<String> calls;
  late bool listening;
  late bool startOk;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'hey_iron_v2_enabled': true,
      'hey_iron_v2_background': false,
    });
    calls = <String>[];
    listening = false;
    startOk = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'status':
          return <String, Object?>{
            'modelReady': true,
            'listening': listening,
          };
        case 'start':
          listening = startOk;
          return <String, Object?>{
            'ok': startOk,
            'error': startOk ? null : 'Микрофонът не можа да бъде стартиран.',
          };
        case 'stop':
        case 'stopEngine':
          listening = false;
          return true;
        case 'testMic':
          return <String, Object?>{
            'ok': true,
            'granted': true,
            'rms': 0.04,
            'peak': 0.05,
          };
        default:
          return true;
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      events,
      MockStreamHandler.inline(onListen: (args, sink) {}),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(events, null);
  });

  test('initialize leaves an enabled session ready, not listening', () async {
    final controller = HeyIronController();
    await controller.initialize();
    expect(controller.enabled, isTrue);
    expect(controller.phase, HeyIronPhase.ready);
    expect(controller.statusLabel, 'Готов • не слуша');
    expect(calls, contains('status'));
    expect(calls, isNot(contains('start')));
  });

  test('handleAppResumed starts listening and the header says слуша', () async {
    final controller = HeyIronController();
    await controller.initialize();
    await controller.handleAppResumed();
    expect(calls, contains('start'));
    expect(controller.phase, HeyIronPhase.listening);
    expect(controller.statusLabel.toLowerCase(), contains('слуша'));
    expect(controller.statusLabel, isNot(contains('не слуша')));
  });

  test('mic test and last-detection debug lines are populated', () async {
    final controller = HeyIronController();
    await controller.initialize();
    expect(controller.lastDetectionLabel, contains('няма'));
    await controller.testMicrophone();
    expect(calls, contains('testMic'));
    expect(controller.micTestMessage, contains('Микрофонът работи'));
    expect(controller.micMeterValue, greaterThan(0));
  });

  test('detected event stores last detection for Settings', () async {
    final controller = HeyIronController();
    await controller.initialize();
    controller.enabled = true;
    controller.handleNativeEventForTest({
      'type': 'detected',
      'keyword': 'HEY_IRON_BG',
    });
    expect(controller.lastDetectedKeyword, 'HEY_IRON_BG');
    expect(controller.lastDetectionLabel, contains('HEY_IRON_BG'));
    expect(controller.lastDetectionAt, isNotNull);
  });

  test('pausing with background listening releases the in-app mic first',
      () async {
    final controller = HeyIronController();
    await controller.initialize();
    controller.backgroundExperimental = true;
    await controller.startListening();
    calls.clear();
    await controller.handleAppPaused();
    expect(calls, ['stopEngine', 'startBackground']);
    expect(controller.phase, HeyIronPhase.listening);
    expect(controller.statusLabel.toLowerCase(), contains('слуша'));
  });

  test('yielding the mic for speech stops Hey Iron until resume', () async {
    final controller = HeyIronController();
    await controller.initialize();
    await controller.startListening();
    calls.clear();
    await controller.yieldMicForSpeech();
    expect(calls, contains('stop'));
    expect(controller.phase, HeyIronPhase.ready);
    await controller.resumeAfterSpeech();
    expect(calls, contains('start'));
    expect(controller.phase, HeyIronPhase.listening);
  });

  test('Android 16 turns experimental background listening off once', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'deviceInfo') {
        return 'realme RMX5051, Android 16 (API 36)';
      }
      if (call.method == 'status') {
        return <String, Object?>{'modelReady': true, 'listening': false};
      }
      if (call.method == 'start') {
        return <String, Object?>{'ok': true, 'error': null};
      }
      return true;
    });
    SharedPreferences.setMockInitialValues({
      'hey_iron_v2_enabled': true,
      'hey_iron_v2_background': true,
    });
    final controller = HeyIronController();
    await controller.initialize();
    expect(controller.androidSdk, 36);
    expect(controller.backgroundExperimental, isFalse);
    expect(
      controller.message,
      contains('Фоновото слушане е изключено на Android 16'),
    );
  });
}
