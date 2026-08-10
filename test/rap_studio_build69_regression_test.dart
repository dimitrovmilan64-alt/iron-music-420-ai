import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('build 69 Suno prompt is driven by the current song state', () {
    final rap = File('lib/pages/rap_studio_page.dart').readAsStringSync();

    expect(rap, contains('String _tempoDescriptor()'));
    expect(rap, contains('String _structureDescriptor()'));
    expect(rap, contains('String _vocalDescriptor()'));
    expect(rap, contains(r"'song concept: $concept'"));
    expect(rap, contains(r"'lyrical imagery: $keywords'"));
    expect(rap, contains('_refreshSunoFields({bool force = false})'));
    expect(rap, contains('_refreshSunoFields(force: true);'));
  });

  test('build 69 preserves manual Suno edits while auto fields stay live', () {
    final rap = File('lib/pages/rap_studio_page.dart').readAsStringSync();

    expect(rap, contains("String _lastAutoMusicPrompt = '';"));
    expect(rap, contains("String _lastAutoExcludePrompt = '';"));
    expect(rap, contains('currentMusic == _lastAutoMusicPrompt.trim()'));
    expect(rap, contains('currentExclude == _lastAutoExcludePrompt.trim()'));
    expect(rap, contains('_updatingAutoSunoFields'));
  });

  test('build 69 AI tools visibly update lyrics and Suno style', () {
    final rap = File('lib/pages/rap_studio_page.dart').readAsStringSync();

    expect(rap, contains('AI върна празен резултат. Опитай отново.'));
    expect(rap, contains(r"'$actionName — готово. Suno Style е обновен.'"));
    expect(rap, contains('final beforeLyrics = _currentLyrics;'));
    expect(rap, contains('final changed = _currentLyrics != beforeLyrics;'));
  });

  test('hook generation accepts theme-only projects', () {
    final rap = File('lib/pages/rap_studio_page.dart').readAsStringSync();

    expect(rap, contains('if (current.isEmpty && theme.isEmpty)'));
    expect(rap, contains('final hookContext = current.isNotEmpty'));
    expect(rap, contains(r'$hookContext'));
  });

  test('build number is 69 after the CI patch is applied', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 3.4.0+69'));
  });
}
