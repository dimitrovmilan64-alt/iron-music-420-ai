class LyricSection {
  final String tag;
  final String label;
  final String body;

  const LyricSection({
    required this.tag,
    required this.label,
    required this.body,
  });
}

String bulgarianSectionLabel(String tag) {
  final t = tag.toLowerCase();
  if (t.contains('pre-chorus') ||
      t.contains('prechorus') ||
      t.contains('предприпев')) {
    return 'Предприпев';
  }
  if (t.contains('chorus') || t.contains('припев') || t.contains('hook')) {
    return 'Припев';
  }
  if (t.contains('verse') || t.contains('куплет')) {
    return 'Куплет';
  }
  if (t.contains('bridge') || t.contains('бридж')) {
    return 'Бридж';
  }
  if (t.contains('intro') || t.contains('интро')) {
    return 'Интро';
  }
  if (t.contains('outro') || t.contains('аутро') || t.contains('end')) {
    return 'Аутро';
  }
  return tag.trim().isEmpty ? 'Текст' : tag.trim();
}

List<LyricSection> parseLyricSections(String text) {
  final source = text.replaceAll('\r\n', '\n');
  final re = RegExp(r'^\[([^\]]+)\]\s*$', multiLine: true);
  final matches = re.allMatches(source).toList();
  if (matches.isEmpty) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return const <LyricSection>[];
    return [
      LyricSection(tag: 'Текст', label: 'Текст', body: trimmed),
    ];
  }

  final sections = <LyricSection>[];
  if (matches.first.start > 0) {
    final preamble = source.substring(0, matches.first.start).trim();
    if (preamble.isNotEmpty) {
      sections.add(
        LyricSection(tag: 'Текст', label: 'Текст', body: preamble),
      );
    }
  }
  for (var i = 0; i < matches.length; i++) {
    final tag = matches[i].group(1)!.trim();
    final start = matches[i].end;
    final end = i + 1 < matches.length ? matches[i + 1].start : source.length;
    sections.add(
      LyricSection(
        tag: tag,
        label: bulgarianSectionLabel(tag),
        body: source.substring(start, end).trim(),
      ),
    );
  }
  return sections;
}
