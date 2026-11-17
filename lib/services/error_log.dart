import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_info.dart';

class AppErrorEvent {
  final DateTime at;
  final String source;
  final String message;
  final int? statusCode;

  const AppErrorEvent({
    required this.at,
    required this.source,
    required this.message,
    this.statusCode,
  });
}

/// In-memory ring buffer of recent app errors. Never stores API keys.
class AppErrorLog {
  AppErrorLog._();

  static final AppErrorLog instance = AppErrorLog._();

  static const int capacity = 30;

  final List<AppErrorEvent> _events = <AppErrorEvent>[];

  List<AppErrorEvent> get events => List.unmodifiable(_events);

  void clear() => _events.clear();

  void record({
    required String source,
    required String message,
    int? statusCode,
    DateTime? at,
  }) {
    _events.add(
      AppErrorEvent(
        at: at ?? DateTime.now(),
        source: source.trim().isEmpty ? 'app' : source.trim(),
        message: redact(message),
        statusCode: statusCode,
      ),
    );
    if (_events.length > capacity) {
      _events.removeRange(0, _events.length - capacity);
    }
  }

  static final _secretPatterns = <RegExp>[
    RegExp(r'AIza[0-9A-Za-z_\-]{10,}'),
    RegExp(r'gsk_[A-Za-z0-9]{8,}'),
    RegExp(r'sk-[A-Za-z0-9]{8,}'),
    RegExp(r'(api[_-]?key|secret|token|authorization|bearer)\s*[:=]\s*\S+',
        caseSensitive: false),
    RegExp(r'(key|token)=([^\s&]+)', caseSensitive: false),
  ];

  static String redact(String input) {
    var text = input;
    for (final pattern in _secretPatterns) {
      text = text.replaceAll(pattern, '[редактирано]');
    }
    return text;
  }

  static bool looksLikeSecret(String input) {
    return input != redact(input);
  }

  String buildReport({
    required String versionLabel,
    required String deviceInfo,
    required Map<String, String> settings,
  }) {
    final buffer = StringBuffer()
      ..writeln('Iron Music 420 AI — доклад за проблем')
      ..writeln('Версия: ${redact(versionLabel)}')
      ..writeln('Устройство: ${redact(deviceInfo)}')
      ..writeln(
          'Лог на Хей Айрън: Android/data/com.example.ironmusic420ai/files/iron_debug.log')
      ..writeln('Време: ${_format(DateTime.now())}')
      ..writeln()
      ..writeln('Настройки (без ключове):');
    if (settings.isEmpty) {
      buffer.writeln('- (няма)');
    } else {
      for (final entry in settings.entries) {
        buffer.writeln('- ${redact(entry.key)}: ${redact(entry.value)}');
      }
    }
    buffer
      ..writeln()
      ..writeln('Последни грешки:');
    if (_events.isEmpty) {
      buffer.writeln('- Няма записани грешки в тази сесия.');
    } else {
      for (final event in _events.reversed) {
        final code =
            event.statusCode == null ? '' : ' HTTP ${event.statusCode}';
        buffer.writeln(
          '- ${_format(event.at)} [${event.source}]$code: ${event.message}',
        );
      }
    }
    return buffer.toString().trim();
  }

  Future<String> copyAndShare({
    required String deviceInfo,
    required Map<String, String> settings,
  }) async {
    final report = buildReport(
      versionLabel: AppInfo.versionLabel,
      deviceInfo: deviceInfo,
      settings: settings,
    );
    await Clipboard.setData(ClipboardData(text: report));
    await Share.share(report, subject: 'Iron Music — доклад за проблем');
    return report;
  }

  static String _format(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

bool isOfflineError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('os error: ') && text.contains('errno = ') ||
      text.contains('clientexception') && text.contains('connection');
}
