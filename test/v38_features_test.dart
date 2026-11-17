import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironmusic420ai/app_info.dart';
import 'package:ironmusic420ai/models/song_project.dart';
import 'package:ironmusic420ai/services/error_log.dart';
import 'package:ironmusic420ai/services/local_store.dart';
import 'package:ironmusic420ai/services/lyric_craft.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<LocalStore> _store() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  final store = LocalStore();
  await store.initialize();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('song history persists theme, mood and drafts', () async {
    final store = await _store();
    final song = SongProject.create(
      title: 'Гарата',
      lyrics: '[Chorus]\nНа двора чака стар камион\nВ ъгъла спичка и картон',
      musicPrompt: 'Genre: Hard trap',
      theme: 'нощна гара',
      style: 'Hard trap',
      mood: 'Тъмно и агресивно',
      rhymeScheme: 'AABB',
      bpm: 140,
    );
    await store.upsertSong(song);
    expect(store.songProjects, hasLength(1));
    expect(store.songProjects.first.theme, 'нощна гара');
    expect(store.songProjects.first.isDraft, isFalse);

    final draft = SongProject.create(
      title: 'Чернова от чата',
      lyrics: '',
      musicPrompt: '',
      theme: 'без интернет',
      style: 'Hard trap',
      mood: 'Спокойно и дълбоко',
      rhymeScheme: 'AABB',
      bpm: 140,
      isDraft: true,
    );
    await store.upsertSong(draft);
    expect(store.songProjects, hasLength(2));
    expect(store.songProjects.any((item) => item.isDraft), isTrue);
    expect(draft.exportText, contains('Статус: чернова'));

    final restored = SongProject.fromJson(draft.toJson());
    expect(restored.isDraft, isTrue);

    final summary = LyricCraft.recentSongsSummary(store.songProjects);
    expect(summary, contains('нощна гара'));
    expect(summary, contains('Тъмно и агресивно'));
    expect(summary, contains('Hard trap'));
  });

  test('line rewrite keeps the pair rhyme constraint', () {
    const lyrics = '''
[Verse 1]
На двора под навеса чака стар камион
Ключът в дланта, а в ъгъла спичка и картон
''';
    final annotated = LyricCraft.annotateLines(lyrics);
    final firstLine = annotated.indexWhere(
      (line) => line.text.contains('камион'),
    );
    expect(firstLine, greaterThan(0));
    expect(annotated[firstLine].strength, isNot(RhymeStrength.weak));
    expect(annotated[firstLine].partnerIndex, isNotNull);

    expect(
      LyricCraft.isValidLineRewrite(
        originalLyrics: lyrics,
        lineIndex: firstLine,
        newLine: 'Гледам часовника на стената',
      ),
      isFalse,
    );
    expect(
      LyricCraft.isValidLineRewrite(
        originalLyrics: lyrics,
        lineIndex: firstLine,
        newLine: 'На двора пак ръждясва стар камион',
      ),
      isTrue,
    );

    final instruction = LyricCraft.buildLineRewriteInstruction(
      lyrics: lyrics,
      lineIndex: firstLine,
      rhymeScheme: 'AABB',
      language: LyricLanguage.bulgarian,
    );
    expect(instruction, contains('камион'));
    expect(instruction, contains('картон'));
    expect(instruction, contains('AABB'));
  });

  test('problem report redacts API keys and records HTTP codes', () {
    final log = AppErrorLog.instance;
    log.clear();
    const key = 'AIzaSyDummyTestKeyValue1234567890';
    const groq = 'gsk_abcdefghijklmnopqrstuvwxyz123456';
    log.record(
      source: 'Gemini',
      message: 'Request failed for key=$key',
      statusCode: 429,
    );
    log.record(source: 'Groq', message: 'auth $groq failed');
    expect(AppErrorLog.redact('Bearer $key'), contains('[редактирано]'));
    expect(AppErrorLog.redact(key), isNot(contains('AIza')));
    expect(AppErrorLog.redact(groq), isNot(contains('gsk_')));

    final report = log.buildReport(
      versionLabel: AppInfo.versionLabel,
      deviceInfo: 'Realme, Android 15',
      settings: {'Gemini ключ': key, 'Хей Айрън': 'включен'},
    );
    expect(report, contains('доклад за проблем'));
    expect(report, contains('HTTP 429'));
    expect(report, contains('Gemini'));
    expect(report, isNot(contains(key)));
    expect(report, isNot(contains(groq)));
    expect(report, contains('[редактирано]'));
    expect(report, contains('Хей Айрън'));
  });

  test('offline errors can be saved as drafts', () async {
    expect(
      isOfflineError(Exception('SocketException: Failed host lookup')),
      isTrue,
    );
    expect(isOfflineError(Exception('HTTP 429')), isFalse);

    final store = await _store();
    final draft = SongProject.create(
      title: 'Чернова',
      lyrics: 'първи ред',
      musicPrompt: '',
      theme: 'нощна смяна',
      style: 'Hard trap',
      mood: 'Тъмно и агресивно',
      rhymeScheme: 'AABB',
      bpm: 140,
      isDraft: true,
    );
    await store.upsertSong(draft);
    expect(store.songProjects.single.isDraft, isTrue);
    expect(store.songProjects.single.theme, 'нощна смяна');
  });

  test('Suno tags and style prompt are normalized for copy-all', () {
    const lyrics = '[Куплет 1]\nред\n[Припев]\nкука';
    expect(LyricCraft.normalizeSunoTags(lyrics), contains('[Verse 1]'));
    expect(LyricCraft.normalizeSunoTags(lyrics), contains('[Chorus]'));
    final style = LyricCraft.buildSunoStylePrompt(
      style: 'Hard trap',
      mood: 'dark and aggressive',
      bpm: 140,
    );
    expect(style, contains('Genre: Hard trap'));
    expect(style, contains('Tempo: 140 BPM'));
    expect(style, contains('Vocal:'));
    expect(style, contains('Mood:'));
    expect(style, contains('Instruments:'));
    final pack = LyricCraft.buildSunoPackage(
      lyrics: lyrics,
      stylePrompt: style,
    );
    expect(pack, contains('/* Style */'));
    expect(pack, contains('/* Lyrics */'));
    expect(pack, contains('[Verse 1]'));
  });
}
