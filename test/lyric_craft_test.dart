import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironmusic420ai/models/song_project.dart';
import 'package:ironmusic420ai/services/gemini_service.dart';
import 'package:ironmusic420ai/services/lyric_craft.dart';

void main() {
  test('defaults to Bulgarian unless the seed is clearly English', () {
    expect(LyricCraft.detectLanguage(), LyricLanguage.bulgarian);
    expect(
      LyricCraft.detectLanguage(theme: 'нощта на гарата', material: ''),
      LyricLanguage.bulgarian,
    );
    expect(
      LyricCraft.detectLanguage(
        title: 'Last bus',
        material: 'A 3 a.m. call from the old block.',
      ),
      LyricLanguage.english,
    );
  });

  test('rhymeTail uses the last stressed vowel and ending', () {
    expect(LyricCraft.rhymeTail('камион'), 'он');
    expect(LyricCraft.rhymeTail('картон'), 'он');
    expect(LyricCraft.rhymeTail('двор'), 'ор');
    expect(LyricCraft.rhymeTail('хор'), 'ор');
    expect(LyricCraft.rhymeTail('пиша'), 'иша');
    expect(LyricCraft.rhymeTail('диша'), 'иша');
    expect(LyricCraft.rhymeTail('night'), 'ight');
    expect(LyricCraft.rhymeTail('light'), 'ight');
  });

  test('rhymeScore rewards rich rhymes and rejects last-letter matches', () {
    expect(LyricCraft.rhymeScore('камион', 'картон'), greaterThanOrEqualTo(2));
    expect(LyricCraft.rhymeScore('пиша', 'диша'), greaterThanOrEqualTo(2));
    expect(LyricCraft.rhymeScore('night', 'light'), greaterThanOrEqualTo(2));
    expect(LyricCraft.rhymeScore('град', 'стол'), 0);
    expect(LyricCraft.rhymeScore('закон', 'бетон'), greaterThanOrEqualTo(2));
  });

  test('grammatical verb-ending pairs are weak, not main rhymes', () {
    expect(LyricCraft.isGrammaticalRhyme('искам', 'чакам'), isTrue);
    expect(LyricCraft.rhymeScore('искам', 'чакам'), lessThan(2));
    expect(LyricCraft.isGrammaticalRhyme('камион', 'картон'), isFalse);
  });

  test('analyzeLyrics flags weak, cliche and uneven pairs', () {
    const weak = '''
[Куплет 1]
Аз искам пак да ставам
И после пак да давам
В джоба пази старото сърце
И търси изход в празното небе
Носи същата дълбока болка
''';
    final report = LyricCraft.analyzeLyricsRhymeQuality(weak);
    expect(report.needsRewrite, isTrue);
    expect(report.weakPairs, isNotEmpty);
    expect(report.clicheEndWords, containsAll(['сърце', 'небе', 'болка']));

    const strong = '''
[Куплет 1]
На двора под навеса чака стар камион
Ключът в дланта, а в ъгъла спичка и картон
Съседът пуска радио през пукнатия двор
Аз броя парите за билета до късен хор
[Припев]
Не ме търси на този номер, сменен е кодът
Вратата вече помни друг, не стария входът
''';
    final good = LyricCraft.analyzeLyricsRhymeQuality(strong);
    expect(good.weakPairs, isEmpty);
    expect(good.clicheEndWords, isEmpty);
  });

  test('system prompt and song instruction require arc, scheme and hook', () {
    final prompt = LyricCraft.buildSystemPrompt(LyricLanguage.bulgarian);
    expect(prompt, contains('Основният език е български'));
    expect(prompt, contains('ударена гласна'));
    expect(prompt, contains('граматически рими'));
    expect(prompt, contains('сърце/небе'));
    expect(prompt, contains('Всеки куплет движи историята'));
    expect(prompt, contains('Припевът е силна'));

    final instruction = LyricCraft.buildSongInstruction(
      language: LyricLanguage.bulgarian,
      style: 'Hard trap',
      mood: 'Тъмно и агресивно',
      bpm: 140,
      title: 'Последният автобус',
      theme: 'връщане в квартала',
      material: 'Ключът вече не става.',
      storyAngle: 'ключ, който вече не отваря същата врата',
      rhymeScheme: 'AABB',
      recentSongs: '- Старата стълба: дълг към приятел',
    );
    expect(instruction, contains('AABB'));
    expect(instruction, contains('Не повтаряй сюжета'));
    expect(instruction, contains('Старата стълба'));
    expect(instruction, contains('ключ, който вече не отваря'));
    expect(instruction, contains('силна кука'));
  });

  test('revision instruction marks weak rhyme pairs', () {
    final report = LyricCraft.analyzeLyricsRhymeQuality('''
[Куплет 1]
Аз пак само искам
И вече не те чакам
''');
    final revision = LyricCraft.buildRevisionInstruction(
      draft: 'черновик',
      language: LyricLanguage.bulgarian,
      report: report,
      originalInstruction: 'Напиши песен',
    );
    expect(revision, contains('искам / чакам'));
    expect(revision, contains('граматическа'));
    expect(revision, contains('Маркирай всяка двойка'));
  });

  test('recentSongsSummary lists titles and themes', () {
    final now = DateTime(2026, 11, 14);
    final songs = [
      SongProject.create(
        title: 'Старата стълба',
        lyrics: 'текст',
        musicPrompt: 'trap',
        theme: 'дълг към приятел',
        style: 'Hard trap',
        mood: 'Тъмно',
        rhymeScheme: 'AABB',
        bpm: 140,
      ),
    ];
    // createdAt is now, ignore unused
    expect(now.year, 2026);
    final summary = LyricCraft.recentSongsSummary(songs);
    expect(summary, contains('Старата стълба'));
    expect(summary, contains('дълг към приятел'));
  });

  test('story angles and schemes are deterministic with a seed', () {
    final angle = LyricCraft.pickStoryAngle(
      LyricLanguage.bulgarian,
      Random(4),
    );
    expect(LyricCraft.storyAngles, contains(angle));
    expect(
      {'AABB', 'ABAB'},
      contains(LyricCraft.pickRhymeScheme(Random(1))),
    );
  });

  test('lyric model lists prefer official free-tier flash models', () {
    expect(GeminiService.lyricPreferredModels.first, 'gemini-3.8-flash');
    expect(
      GeminiService.lyricPreferredModels,
      isNot(contains('gemini-3.1-pro-preview')),
    );
    expect(GeminiService.lyricBackupModels.first, 'openai/gpt-oss-120b');
    expect(
      GeminiService.lyricBackupModels,
      isNot(contains('llama-3.3-70b-versatile')),
    );
    expect(GeminiService.lyricCallTimeout, const Duration(seconds: 18));
  });

  test('chat lyric intent detects rap, chorus and verse requests', () {
    expect(
      LyricCraft.isLyricRequest(
        'Направи ми един рап припев да е със мрачно настроение',
      ),
      isTrue,
    );
    expect(
      LyricCraft.isShortLyricRequest(
        'Направи ми един рап припев да е със мрачно настроение',
      ),
      isTrue,
    );
    expect(LyricCraft.isLyricRequest('Какво време е утре?'), isFalse);
    expect(LyricCraft.isShortLyricRequest('Напиши ми цяла песен'), isFalse);
    expect(LyricCraft.isLyricRequest('Напиши ми цяла песен'), isTrue);
  });

  test('Milan\'s weak chat chorus fails the rhyme check', () {
    const weak = '''
Припев (мрачно настроение)
Блъсна светлина, но я не виждам,
Сянката в сърцето ми е пламък.
Със звънища на тъга, стъпвам в тъмно,
Когато всичко се смина, аз останах сам.

Тази нощ не се събужда,
Душата ми се превръща в кристална къща.
Вятърът шепне, но аз не слушам,
Въпросът е: "Къде е свободата, където?"
''';
    final report = LyricCraft.analyzeLyricsRhymeQuality(weak);
    expect(report.needsRewrite, isTrue);
    expect(LyricCraft.rhymeScore('виждам', 'тъмно'), 0);
    expect(LyricCraft.rhymeScore('пламък', 'сам'), 0);
    expect(LyricCraft.rhymeScore('събужда', 'къща'), 0);
    expect(LyricCraft.rhymeScore('слушам', 'където'), 0);
    final ends =
        report.pairs.map((pair) => '${pair.left}/${pair.right}').toList();
    expect(ends, contains('виждам/пламък'));
    expect(report.weakPairs.length, greaterThanOrEqualTo(3));
  });

  test('a well-rhymed Bulgarian chorus passes the rhyme check', () {
    const strong = '''
[Припев]
Лампата мига над пукнатия двор
В стъклото сече жълт и празен хор
Не връщам обаждането в този час
Ключът не пасва вече на нашия глас
''';
    final report = LyricCraft.analyzeLyricsRhymeQuality(strong);
    expect(report.weakPairs, isEmpty);
    expect(report.needsRewrite, isFalse);
    expect(LyricCraft.rhymeScore('двор', 'хор'), greaterThanOrEqualTo(2));
    expect(LyricCraft.rhymeScore('час', 'глас'), greaterThanOrEqualTo(2));
  });
}
