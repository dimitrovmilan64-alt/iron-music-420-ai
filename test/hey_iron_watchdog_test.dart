import 'package:flutter_test/flutter_test.dart';
import 'package:ironmusic420ai/services/hey_iron_watchdog.dart';

void main() {
  test('three failures inside the window trip the watchdog', () {
    final watchdog = HeyIronWatchdog();
    final t0 = DateTime(2026, 11, 13, 20);
    watchdog.recordFailure(now: t0);
    watchdog.recordFailure(now: t0.add(const Duration(minutes: 5)));
    expect(watchdog.isTripped, isFalse);
    watchdog.recordFailure(now: t0.add(const Duration(minutes: 10)));
    expect(watchdog.failureCount, 3);
    expect(watchdog.isTripped, isTrue);
  });

  test('an unclean previous session counts as a failure', () {
    final watchdog = HeyIronWatchdog(uncleanShutdown: true);
    watchdog.recoverFromPreviousSession(now: DateTime(2026, 11, 13, 21));
    expect(watchdog.failureCount, 1);
    expect(watchdog.uncleanShutdown, isFalse);
  });

  test('a missed heartbeat is treated as a stall', () {
    final watchdog = HeyIronWatchdog();
    final start = DateTime.now();
    watchdog.markStarted(now: start);
    expect(watchdog.isStalled, isFalse);
    watchdog.lastHeartbeatAt = start.subtract(const Duration(seconds: 9));
    expect(watchdog.isStalled, isTrue);
    watchdog.markCleanStop();
    expect(watchdog.isStalled, isFalse);
  });

  test('reset clears a tripped watchdog', () {
    final watchdog = HeyIronWatchdog(failureCount: 3, lastFailureAt: DateTime.now());
    expect(watchdog.isTripped, isTrue);
    watchdog.reset();
    expect(watchdog.isTripped, isFalse);
    expect(watchdog.failureCount, 0);
  });
}
