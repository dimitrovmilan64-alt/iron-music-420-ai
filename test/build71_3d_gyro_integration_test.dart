import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('build 71 uses the exact single leaf with gyroscope depth', () {
    final common = File('lib/ui/common_widgets.dart').readAsStringSync();

    expect(common, contains("package:sensors_plus/sensors_plus.dart"));
    expect(common, contains('class CannabisCore extends StatefulWidget'));
    expect(common, contains('gyroscopeEventStream('));
    expect(common, contains('..setEntry(3, 2, 0.0019)'));
    expect(common, contains('..rotateX(_tiltX + idleTiltX)'));
    expect(common, contains('..rotateY(_tiltY + idleTiltY)'));
    expect(
      RegExp('assets/images/hud_core_exact\\.png').allMatches(common).length,
      1,
    );
  });

  test('build 71 keeps gyro UI on the build 70 application base', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();
    final studioEntry =
        File('lib/pages/rap_studio_page.dart').readAsStringSync();
    final studio = File('lib/pages/rap_studio_page_v2.dart').readAsStringSync();

    expect(pubspec, contains('version: 3.4.0+73'));
    expect(pubspec, contains('sensors_plus: ^6.1.2'));
    expect(chat, contains('CannabisCore(progress: progress, size: size)'));
    expect(chat, contains("'IRON MUSIC'"));
    expect(studioEntry, contains("export 'rap_studio_page_v2.dart'"));
    expect(studio, contains("'Направи припев'"));
    expect(studio, contains("'Copy Suno пакет'"));
  });
}
