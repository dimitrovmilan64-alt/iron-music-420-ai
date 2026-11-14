import 'package:flutter_test/flutter_test.dart';
import 'package:ironmusic420ai/utils/lyric_sections.dart';

void main() {
  test('parses labeled lyric sections and maps tags to Bulgarian', () {
    const lyrics = '''
Intro line

[Verse 1]
Първи куплет тук

[Chorus]
Ето припева

[Bridge]
Бридж текст
''';
    final sections = parseLyricSections(lyrics);
    expect(sections.map((s) => s.label).toList(), [
      'Текст',
      'Куплет',
      'Припев',
      'Бридж',
    ]);
    expect(sections[1].body, 'Първи куплет тук');
    expect(sections[2].body, 'Ето припева');
  });

  test('returns a single text section when there are no tags', () {
    final sections = parseLyricSections('само текст');
    expect(sections, hasLength(1));
    expect(sections.single.label, 'Текст');
    expect(sections.single.body, 'само текст');
  });

  test('maps pre-chorus before chorus', () {
    expect(bulgarianSectionLabel('Pre-Chorus'), 'Предприпев');
    expect(bulgarianSectionLabel('HOOK'), 'Припев');
    expect(bulgarianSectionLabel('Outro'), 'Аутро');
  });
}
