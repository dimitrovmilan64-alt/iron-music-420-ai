/// Tracks Hey Iron failures and ANR-like stalls, and auto-disables the
/// feature after too many incidents on a weak phone.
class HeyIronWatchdog {
  static const int maxFailures = 3;
  static const Duration stallTimeout = Duration(seconds: 8);
  static const Duration failureWindow = Duration(hours: 24);

  int failureCount;
  DateTime? lastFailureAt;
  bool uncleanShutdown;
  DateTime? lastHeartbeatAt;
  bool sessionOpen;

  HeyIronWatchdog({
    this.failureCount = 0,
    this.lastFailureAt,
    this.uncleanShutdown = false,
    this.lastHeartbeatAt,
    this.sessionOpen = false,
  });

  bool get isTripped {
    if (failureCount < maxFailures) return false;
    final last = lastFailureAt;
    if (last == null) return true;
    return DateTime.now().difference(last) <= failureWindow;
  }

  bool get isStalled {
    if (!sessionOpen) return false;
    final beat = lastHeartbeatAt;
    if (beat == null) return false;
    return DateTime.now().difference(beat) > stallTimeout;
  }

  void markStarted({DateTime? now}) {
    final t = now ?? DateTime.now();
    uncleanShutdown = true;
    sessionOpen = true;
    lastHeartbeatAt = t;
  }

  void markHeartbeat({DateTime? now}) {
    lastHeartbeatAt = now ?? DateTime.now();
  }

  void markCleanStop() {
    uncleanShutdown = false;
    sessionOpen = false;
  }

  void recordFailure({DateTime? now}) {
    final t = now ?? DateTime.now();
    if (lastFailureAt != null &&
        t.difference(lastFailureAt!) > failureWindow) {
      failureCount = 0;
    }
    failureCount += 1;
    lastFailureAt = t;
    sessionOpen = false;
  }

  /// Call on process start. If the previous session did not stop cleanly,
  /// count it as a failure (crash or forced kill).
  void recoverFromPreviousSession({DateTime? now}) {
    if (uncleanShutdown) {
      recordFailure(now: now);
      uncleanShutdown = false;
    }
  }

  void reset() {
    failureCount = 0;
    lastFailureAt = null;
    uncleanShutdown = false;
    lastHeartbeatAt = null;
    sessionOpen = false;
  }

  Map<String, Object?> toMap() => {
        'failureCount': failureCount,
        'lastFailureAt': lastFailureAt?.millisecondsSinceEpoch,
        'uncleanShutdown': uncleanShutdown,
      };

  factory HeyIronWatchdog.fromMap(Map<String, Object?> map) {
    final last = map['lastFailureAt'];
    return HeyIronWatchdog(
      failureCount: (map['failureCount'] as int?) ?? 0,
      lastFailureAt: last is int
          ? DateTime.fromMillisecondsSinceEpoch(last)
          : null,
      uncleanShutdown: (map['uncleanShutdown'] as bool?) ?? false,
    );
  }
}
