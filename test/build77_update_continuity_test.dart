import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('build 77 remains an update of the installed Build 76 app', () {
    final gradle =
        File('android/app/build.gradle.kts').readAsStringSync();
    final workflow =
        File('.github/workflows/android-build.yml').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('version: 3.4.0+77'));
    expect(
      gradle,
      contains('applicationId = "com.example.ironmusic420ai"'),
    );
    expect(gradle, contains('signingConfigs.getByName("ironTest")'));
    expect(
      workflow,
      contains('flutter build apk --debug --target-platform android-arm64'),
    );
    expect(
      workflow,
      contains('build/app/outputs/flutter-apk/app-debug.apk'),
    );
  });
}
