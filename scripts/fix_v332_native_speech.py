from pathlib import Path

activity_path = Path('android/app/src/main/kotlin/com/example/ironmusic420ai/MainActivity.kt')
pubspec_path = Path('pubspec.yaml')

activity = activity_path.read_text(encoding='utf-8')
obsolete = '            putExtra(RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, false)\n'
count = activity.count(obsolete)
if count != 1:
    raise RuntimeError(f'obsolete recognizer extra: expected 1 match, found {count}')
activity_path.write_text(activity.replace(obsolete, '', 1), encoding='utf-8')

pubspec = pubspec_path.read_text(encoding='utf-8')
dependency = '  speech_to_text: ^7.4.0\n'
count = pubspec.count(dependency)
if count != 1:
    raise RuntimeError(f'speech_to_text dependency: expected 1 match, found {count}')
pubspec_path.write_text(pubspec.replace(dependency, '', 1), encoding='utf-8')

print('v3.3.2 native speech preflight fixes applied')
