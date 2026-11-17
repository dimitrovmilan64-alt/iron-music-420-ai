import 'dart:math';

enum LyricLanguage { bulgarian, english }

class RhymePairReport {
  final String left;
  final String right;
  final int score;
  final String reason;

  const RhymePairReport({
    required this.left,
    required this.right,
    required this.score,
    required this.reason,
  });

  bool get isWeak => score < 2;
}

class LyricRhymeReport {
  final List<RhymePairReport> pairs;
  final List<String> clicheEndWords;
  final List<String> unevenLines;
  final List<String> repeatedEndWords;

  const LyricRhymeReport({
    required this.pairs,
    required this.clicheEndWords,
    required this.unevenLines,
    required this.repeatedEndWords,
  });

  List<RhymePairReport> get weakPairs =>
      pairs.where((pair) => pair.isWeak).toList();

  bool get needsRewrite =>
      weakPairs.isNotEmpty ||
      clicheEndWords.isNotEmpty ||
      unevenLines.isNotEmpty ||
      repeatedEndWords.isNotEmpty;
}

enum RhymeStrength { strong, ok, weak }

class AnnotatedLyricLine {
  final int index;
  final String text;
  final bool isSectionTag;
  final bool isBlank;
  final RhymeStrength? strength;
  final int? partnerIndex;
  final String? reason;

  const AnnotatedLyricLine({
    required this.index,
    required this.text,
    this.isSectionTag = false,
    this.isBlank = false,
    this.strength,
    this.partnerIndex,
    this.reason,
  });

  AnnotatedLyricLine copyWith({
    RhymeStrength? strength,
    int? partnerIndex,
    String? reason,
  }) {
    return AnnotatedLyricLine(
      index: index,
      text: text,
      isSectionTag: isSectionTag,
      isBlank: isBlank,
      strength: strength ?? this.strength,
      partnerIndex: partnerIndex ?? this.partnerIndex,
      reason: reason ?? this.reason,
    );
  }
}

class LyricCraft {
  static const storyAngles = <String>[
    'една конкретна нощ и едно решение, взето прекалено късно',
    'обаждане в 3 сутринта, което променя плановете',
    'връщане в квартала след години и ключ, който вече не става',
    'дълг, който най-накрая се плаща, но не с пари',
    'приятел, който изчезна без обяснение',
    'първата сериозна заплата и какво остана от нея в края на месеца',
    'майка, която чака на перона с торба в ръка',
    'сделка, която се обърна в една стая без прозорци',
    'запис, който никой не пусна, и човекът, който го пази',
    'последен автобус, една станция преди дома',
    'съобщение, оставено на прочетено',
    'работна смяна след смяна и една цигара на покрива',
  ];

  static const englishStoryAngles = <String>[
    'a 3 a.m. phone call that changes the plan',
    'coming back to the block with a key that no longer fits',
    'a debt paid, but not with money',
    'a friend who vanished without a reason',
    'first real paycheck and what was left at the end of the month',
    'a deal that turned in a room with no windows',
    'the last bus, one stop before home',
  ];

  static const clicheEndWords = <String>{
    'сърце',
    'сърцето',
    'небе',
    'небето',
    'болка',
    'болката',
    'любов',
    'любовта',
    'душа',
    'душата',
    'сълзи',
    'сълзите',
    'мечта',
    'мечтите',
    'свобода',
    'мрак',
    'прах',
    'бетон',
    'закон',
    'борба',
    'страх',
    'страха',
    'нощта',
    'самота',
    'огън',
    'лед',
    'heart',
    'pain',
    'sky',
    'love',
    'soul',
    'tears',
    'night',
    'fight',
    'light',
  };

  static const grammaticalSuffixes = <String>[
    'ам',
    'ям',
    'ем',
    'им',
    'ат',
    'ят',
    'аш',
    'яш',
    'иш',
    'аме',
    'яме',
    'ате',
    'ях',
    'ах',
    'их',
    'ия',
    'ията',
    'ове',
    'еве',
    'ене',
    'ане',
    'остта',
    'ността',
    'ing',
    'tion',
    'ness',
    'ally',
  ];

  static const _bgVowels = 'аеиоуъюяaeiouy';

  static LyricLanguage detectLanguage({
    String theme = '',
    String material = '',
    String title = '',
  }) {
    final blob = '$theme\n$material\n$title';
    if (RegExp(r'[\u0400-\u04FF]').hasMatch(blob)) {
      return LyricLanguage.bulgarian;
    }
    final latin = RegExp(r'[A-Za-z]').hasMatch(blob);
    final cyrillic = RegExp(r'[\u0400-\u04FF]').hasMatch(blob);
    if (latin && !cyrillic && blob.trim().length >= 8) {
      return LyricLanguage.english;
    }
    return LyricLanguage.bulgarian;
  }

  static final _lyricIntent = RegExp(
    r'припев|предприпев|куплет|рап\b|бридж|аутро|интро|рими|рима\b|'
    r'текст(а|ът)? (за |на )?(песен|рап)|напиши( ми)? (текст|песен)|'
    r'\b(hook|chorus|verse|lyrics|bridge|outro|intro)\b|'
    r'punchline|барове|\bbars\b',
    caseSensitive: false,
  );

  static final _shortLyricIntent = RegExp(
    r'припев|предприпев|куплет|бридж|хук|\b(hook|chorus|verse|bridge)\b',
    caseSensitive: false,
  );

  static final _fullSongIntent = RegExp(
    r'цял[ао](та)? песен|цялата рап|full song|напиши( ми)? (една |цяла )?песен',
    caseSensitive: false,
  );

  static final _sectionHeading = RegExp(
    r'^(припев|предприпев|куплет|интро|бридж|аутро|финален припев|'
    r'hook|chorus|verse|bridge|intro|outro)(\s*\(.*\))?$',
    caseSensitive: false,
  );

  static bool isLyricRequest(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return _lyricIntent.hasMatch(trimmed) || _fullSongIntent.hasMatch(trimmed);
  }

  static bool isShortLyricRequest(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (_fullSongIntent.hasMatch(trimmed) &&
        !_shortLyricIntent.hasMatch(trimmed)) {
      return false;
    }
    return _shortLyricIntent.hasMatch(trimmed);
  }

  static String buildChatLyricInstruction({
    required String userRequest,
    required LyricLanguage language,
    String recentContext = '',
    String recentSongs = '',
  }) {
    final short = isShortLyricRequest(userRequest);
    const scheme = 'AABB';
    final contextBlock = recentContext.trim().isEmpty
        ? ''
        : (language == LyricLanguage.english
            ? 'Recent conversation context:\n$recentContext\n'
            : 'Контекст от разговора:\n$recentContext\n');
    final recentBlock = recentSongs.trim().isEmpty
        ? ''
        : (language == LyricLanguage.english
            ? 'Do not repeat the plot, hook or central image of these earlier songs:\n$recentSongs\n'
            : 'Не повтаряй сюжета, куката или централния образ на тези по-ранни песни:\n$recentSongs\n');
    if (language == LyricLanguage.english) {
      final shape = short
          ? 'only a finished chorus (8 lines)'
          : 'a finished original rap song';
      return 'Write $shape in English.\n'
          'Rhyme scheme: $scheme. End-rhymes must rhyme by stressed vowel + '
          'following consonants, not the last letter alone. Keep paired lines '
          'close in syllable count. Concrete images matching the requested mood. '
          'No stock heart/sky/pain pairs.\n'
          'User request:\n$userRequest\n'
          '$contextBlock'
          '$recentBlock'
          'Return only singable lyrics with square section tags. '
          'No parenthetical stage directions and no intro explanation.\n';
    }
    final shape = short
        ? 'само завършен припев от 8 реда'
        : 'завършена оригинална българска рап песен';
    return 'Напиши $shape.\n'
        'Римна схема: $scheme. Крайните рими да се римуват по ударена гласна '
        'и следващите съгласни, не само по последната буква. Двойките редове '
        'да са близки по брой срички.\n'
        'Конкретни образи според поисканото настроение. Без изтъркани двойки '
        'сърце/небе/болка и без граматически рими като -ам/-ам.\n'
        'Заявка на потребителя:\n$userRequest\n'
        '$contextBlock'
        '$recentBlock'
        'Върни само текста за пеене с квадратни секционни етикети като [Chorus] и [Verse]. '
        'Без обяснения и без указания в кръгли скоби.\n';
  }

  static String buildWeakLinesInstruction({
    required String draft,
    required LyricLanguage language,
    required LyricRhymeReport report,
    required String originalInstruction,
  }) {
    final weak = report.weakPairs
        .map((pair) => '- ${pair.left} / ${pair.right}: ${pair.reason}')
        .join('\n');
    final weakBlock = weak.isEmpty ? '- няма маркирани' : weak;
    if (language == LyricLanguage.english) {
      return 'Rewrite ONLY the weakly rhymed lines in this draft. '
          'Keep strong lines and the story.\n'
          'Weak pairs:\n${weak.isEmpty ? '- none flagged' : weak}\n'
          'Original request:\n$originalInstruction\n\n'
          'DRAFT:\n$draft\n\n'
          'Return only the full improved lyrics with section tags.\n';
    }
    return 'Пренапиши САМО редовете със слаби рими в този черновик. '
        'Запази силните редове и историята.\n'
        'Слаби двойки:\n$weakBlock\n'
        'Първоначална задача:\n$originalInstruction\n\n'
        'ЧЕРНОВИК:\n$draft\n\n'
        'Върни само целия подобрен текст със секционни етикети.\n';
  }

  static String pickStoryAngle(LyricLanguage language, [Random? random]) {
    final source =
        language == LyricLanguage.english ? englishStoryAngles : storyAngles;
    final index = (random ?? Random()).nextInt(source.length);
    return source[index];
  }

  static String pickRhymeScheme([Random? random]) {
    return ((random ?? Random()).nextBool()) ? 'AABB' : 'ABAB';
  }

  static String normalizeWord(String raw) {
    return raw
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^a-zа-яіїґєъьюя]+'), '');
  }

  static bool _isVowel(String char) {
    return char.isNotEmpty && _bgVowels.contains(char);
  }

  /// Rhyme tail from the last stressed vowel (final vowel, or penultimate
  /// vowel when the word ends in a vowel — a feminine rhyme).
  static String rhymeTail(String raw) {
    final word = normalizeWord(raw);
    if (word.isEmpty) return '';
    var lastVowel = -1;
    for (var i = word.length - 1; i >= 0; i--) {
      if (_isVowel(word[i])) {
        lastVowel = i;
        break;
      }
    }
    if (lastVowel < 0) return word;
    if (_isVowel(word[word.length - 1]) && lastVowel == word.length - 1) {
      for (var i = lastVowel - 1; i >= 0; i--) {
        if (_isVowel(word[i])) {
          return word.substring(i);
        }
      }
    }
    return word.substring(lastVowel);
  }

  static int syllableCount(String line) {
    final word = normalizeWord(line);
    var count = 0;
    var prevVowel = false;
    for (var i = 0; i < word.length; i++) {
      final vowel = _isVowel(word[i]);
      if (vowel && !prevVowel) count++;
      prevVowel = vowel;
    }
    return count;
  }

  static bool isGrammaticalRhyme(String left, String right) {
    final a = normalizeWord(left);
    final b = normalizeWord(right);
    if (a.isEmpty || b.isEmpty || a == b) return false;
    for (final suffix in grammaticalSuffixes) {
      if (suffix.length < 2) continue;
      if (a.endsWith(suffix) && b.endsWith(suffix)) {
        final stemA = a.substring(0, a.length - suffix.length);
        final stemB = b.substring(0, b.length - suffix.length);
        if (rhymeTail(stemA) != rhymeTail(stemB)) {
          return true;
        }
      }
    }
    return false;
  }

  /// 0 = no rhyme, 1 = weak/lazy/grammatical, 2 = acceptable, 3 = rich.
  static int rhymeScore(String left, String right) {
    final a = normalizeWord(left);
    final b = normalizeWord(right);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final tailA = rhymeTail(a);
    final tailB = rhymeTail(b);
    if (tailA.isEmpty || tailB.isEmpty) return 0;
    if (isGrammaticalRhyme(a, b) && tailA == tailB) return 1;
    if (tailA == tailB) {
      // A tail of only a vowel (no following consonants) is too weak.
      if (tailA.length < 2) return 1;
      if (tailA.length >= 3) return 3;
      return 2;
    }
    // Same last letter or a lone shared vowel is not a rhyme.
    return 0;
  }

  static String endWord(String line) {
    final cleaned =
        line.trim().replaceAll(RegExp(r'[«»„“”"\.,!?;:()\[\]…]'), '');
    if (cleaned.isEmpty) return '';
    return cleaned.split(RegExp(r'\s+')).last;
  }

  static LyricRhymeReport analyzeLyricsRhymeQuality(
    String lyrics, {
    String scheme = 'AABB',
  }) {
    return analyzeLyrics(lyrics, scheme: scheme);
  }

  static LyricRhymeReport analyzeLyrics(
    String lyrics, {
    String scheme = 'AABB',
  }) {
    final pairs = <RhymePairReport>[];
    final cliches = <String>[];
    final uneven = <String>[];
    final seenEnds = <String, int>{};

    final sections =
        lyrics.replaceAll('\r\n', '\n').split(RegExp(r'\n(?=\s*\[)'));
    for (final section in sections) {
      final lines = section
          .split('\n')
          .map((line) => line.trim())
          .where((line) =>
              line.isNotEmpty &&
              !RegExp(r'^\[[^\]]+\]$').hasMatch(line) &&
              !_sectionHeading.hasMatch(line))
          .toList();
      if (lines.length < 2) continue;

      final indexes = <(int, int)>[];
      if (scheme == 'ABAB') {
        for (var i = 0; i + 3 < lines.length; i += 4) {
          indexes.add((i, i + 2));
          indexes.add((i + 1, i + 3));
        }
        if (lines.length >= 2 && lines.length % 4 != 0) {
          // Remainder: pair last two if needed.
        }
      } else {
        for (var i = 0; i + 1 < lines.length; i += 2) {
          indexes.add((i, i + 1));
        }
      }

      for (final pair in indexes) {
        final left = endWord(lines[pair.$1]);
        final right = endWord(lines[pair.$2]);
        final score = rhymeScore(left, right);
        var reason = 'богата рима';
        if (score == 0) {
          reason = 'не се римуват по ударение и окончание';
        } else if (normalizeWord(left) == normalizeWord(right)) {
          reason = 'повтаря се същата дума';
        } else if (score == 1) {
          reason = isGrammaticalRhyme(left, right)
              ? 'граматическа рима (едно и също окончание)'
              : 'слаба/мързелива рима';
        } else if (score == 2) {
          reason = 'приемлива рима';
        }
        pairs.add(
          RhymePairReport(
              left: left, right: right, score: score, reason: reason),
        );

        final syllablesLeft = syllableCount(lines[pair.$1]);
        final syllablesRight = syllableCount(lines[pair.$2]);
        if ((syllablesLeft - syllablesRight).abs() > 2 &&
            syllablesLeft > 0 &&
            syllablesRight > 0) {
          uneven.add(
            '"${lines[pair.$1]}" ($syllablesLeft) / "${lines[pair.$2]}" ($syllablesRight)',
          );
        }
      }

      for (final line in lines) {
        final word = normalizeWord(endWord(line));
        if (word.isEmpty) continue;
        seenEnds[word] = (seenEnds[word] ?? 0) + 1;
        if (clicheEndWords.contains(word)) {
          cliches.add(word);
        }
      }
    }

    final repeated = seenEnds.entries
        .where((entry) => entry.value > 1)
        .map((entry) => entry.key)
        .toList();

    return LyricRhymeReport(
      pairs: pairs,
      clicheEndWords: cliches.toSet().toList(),
      unevenLines: uneven,
      repeatedEndWords: repeated,
    );
  }

  static String buildSystemPrompt(LyricLanguage language) {
    if (language == LyricLanguage.english) {
      return '''
You are Iron Rap Writer — a professional original rap lyricist.
Write concrete, vivid, conversational English. Use the user's facts, images and tone; do not invent a biography, crimes, prison or street authority that were not provided.
Default language is English only when the user's material is clearly English. Otherwise write Bulgarian.

STORY ARC (mandatory):
- Each verse must move the story forward with a new event, image or concrete detail.
- Do not restate the previous verse's idea with different words.
- The chorus is a strong, memorable hook — one central phrase, singable, not a summary of the verses.
- The bridge brings a twist or a shift in point of view.
- Intro sets a scene; outro closes the story, it does not repeat the first verse.

RHYME (mandatory, this is the top priority):
- State a rhyme scheme per section (AABB or ABAB) and keep it.
- End-rhymes must actually rhyme by stressed vowel + ending, not just the last letter.
- Prefer rich and multisyllabic rhymes, plus internal rhymes.
- Do not use the same end-word twice as the rhyme.
- Do not lean on grammatical rhymes (same verb/noun ending) as the main rhyme.
- Paired lines should have a similar syllable count so they can be sung.
- Avoid lazy cliche rhyme words (heart/pain/sky/love/soul/night/fight) unless the image is truly fresh and not used as a stock pair.

Return only the finished lyrics with section tags like [Verse 1], [Chorus], [Bridge]. No director notes in parentheses. No mid-line cutoffs.
''';
    }

    return '''
Ти си Iron Rap Writer — професионален автор на оригинален български рап.
Пишеш сурово, естествено и конкретно. Използваш речника, фактите, образите и личния тон от материала на потребителя. Не измисляш биография, престъпления, затвор, наркотици или уличен авторитет, ако не са подадени.
Основният език е български. Пиши на английски само ако материалът на потребителя е явно на английски.

СЮЖЕТНА ДЪГА (задължително):
- Всеки куплет движи историята напред с ново събитие, образ или конкретен детайл.
- Забранено е да повтаряш идеята на предишния куплет с други думи.
- Припевът е силна, запомняща се кука — една централна фраза, лесна за пеене, не резюме на куплетите.
- Бриджът носи обрат или смяна на гледната точка.
- Интрото поставя сцена; аутрото затваря историята, не повтаря първия куплет.

РИМА (задължително, това е най-важният приоритет):
- За всяка секция заяви схема AABB или ABAB и я спази.
- Крайните рими трябва да се римуват по ударена гласна и окончание, не само по последната буква.
- Предпочитай богати и многосрични рими, плюс вътрешни рими.
- Не повтаряй една и съща крайна дума като рима.
- Не разчитай на граматически рими (едни и същи глаголни/именни окончания като -ам/-ам, -ия/-ия, -ене/-ене) като основна рима.
- Двойките редове да имат близък брой срички, за да се пеят лесно.
- Избягвай изтъркани крайни думи и двойки като сърце/небе, болка/любов, мрак/прах, бетон/закон, страх/нощта/самота, освен ако образът е наистина свеж и не е използвана като шаблонна двойка.
- Римувай смисъл, не само последната дума. Не чупи граматиката и не обръщай словореда само заради рима.

Връщаш само готовия текст със секции като [Intro], [Verse 1], [Chorus], [Verse 2], [Bridge], [Final Chorus], [Outro]. Без режисьорски указания в кръгли скоби. Не прекъсвай ред по средата.
''';
  }

  static String buildSongInstruction({
    required LyricLanguage language,
    required String style,
    required String mood,
    required int bpm,
    required String title,
    required String theme,
    required String material,
    required String storyAngle,
    required String rhymeScheme,
    String recentSongs = '',
  }) {
    final recentBlock = recentSongs.trim().isEmpty
        ? ''
        : language == LyricLanguage.english
            ? '''
Do not repeat the plot, hook or central image of these earlier songs:
$recentSongs
'''
            : '''
Не повтаряй сюжета, куката или централния образ на тези по-ранни песни:
$recentSongs
''';

    if (language == LyricLanguage.english) {
      return '''
Write a finished original rap song in English.
Structure: [Intro], [Verse 1], [Chorus], [Verse 2], [Bridge], [Final Chorus], [Outro].
Style: $style.
Mood: $mood.
Tempo: $bpm BPM.
Vocal: deep natural male voice.
Story angle for this song (use it, do not ignore it): $storyAngle.
Rhyme scheme: $rhymeScheme in verses and chorus. End-rhymes must rhyme by stress and ending. Keep paired lines close in syllable count. The chorus must be a strong hook.
${_titleTheme(title, theme, english: true)}
User material:
${material.trim().isEmpty ? 'No draft text. Build the song from the theme, angle and settings.' : material}
$recentBlock
Return only singable lyrics with square section tags. No parenthetical stage directions.
''';
    }

    return '''
Напиши завършена оригинална българска рап песен.
Структура: [Intro], [Verse 1], [Chorus], [Verse 2], [Bridge], [Final Chorus], [Outro].
Стил: $style.
Настроение: $mood.
Темпо: $bpm BPM.
Вокал: нисък плътен естествен мъжки глас.
Сюжетен ъгъл за тази песен (използвай го, не го игнорирай): $storyAngle.
Римна схема: $rhymeScheme в куплетите и припева. Крайните рими да се римуват по ударение и окончание. Двойките редове да са близки по брой срички. Припевът да е силна кука — една фраза, която се помни от първо слушане.
${_titleTheme(title, theme, english: false)}
Материал от потребителя:
${material.trim().isEmpty ? 'Няма готов текст. Създай песента от темата, ъгъла и настройките.' : material}
$recentBlock
Върни само текста за пеене с квадратни секционни етикети. Без указания в кръгли скоби.
''';
  }

  static String _titleTheme(String title, String theme,
      {required bool english}) {
    final cleanTitle = title.trim();
    final cleanTheme = theme.trim();
    if (english) {
      return 'Title: ${cleanTitle.isEmpty ? 'invent a fitting one' : cleanTitle}\n'
          'Theme: ${cleanTheme.isEmpty ? 'draw the theme from the material and story angle' : cleanTheme}';
    }
    return 'Заглавие: ${cleanTitle.isEmpty ? 'измисли подходящо' : cleanTitle}\n'
        'Тема: ${cleanTheme.isEmpty ? 'изведи темата от материала и сюжетния ъгъл' : cleanTheme}';
  }

  static String buildRevisionInstruction({
    required String draft,
    required LyricLanguage language,
    required LyricRhymeReport report,
    required String originalInstruction,
  }) {
    final weak = report.weakPairs
        .map((pair) => '- ${pair.left} / ${pair.right}: ${pair.reason}')
        .join('\n');
    final cliches = report.clicheEndWords.isEmpty
        ? ''
        : (language == LyricLanguage.english
            ? 'Cliche end-words to replace: ${report.clicheEndWords.join(', ')}.\n'
            : 'Изтъркани крайни думи за замяна: ${report.clicheEndWords.join(', ')}.\n');
    final uneven = report.unevenLines.isEmpty
        ? ''
        : (language == LyricLanguage.english
            ? 'Uneven syllable pairs:\n${report.unevenLines.join('\n')}\n'
            : 'Двойки с неравномерен брой срички:\n${report.unevenLines.join('\n')}\n');
    final repeated = report.repeatedEndWords.isEmpty
        ? ''
        : (language == LyricLanguage.english
            ? 'Repeated end-words: ${report.repeatedEndWords.join(', ')}.\n'
            : 'Повторени крайни думи: ${report.repeatedEndWords.join(', ')}.\n');

    if (language == LyricLanguage.english) {
      return '''
Revise this rap draft. Keep the story, facts and tone. Do not invent a new biography.
This is a rhyme-and-arc quality pass — the top priority.

1) Mark every end-rhyme pair in your head (or briefly in thinking) and rewrite any pair that does not rhyme by stressed vowel + ending, is a grammatical rhyme, repeats the same word, or is a stock cliche pair.
2) Each verse must add a new event or image; if a verse restates the previous one, rewrite it so the story moves.
3) Make the chorus a stronger, more singable hook.
4) Keep or tighten the syllable count of paired lines.
$cliches$uneven$repeated
Weak pairs found by an automatic check:
${weak.isEmpty ? '- none flagged, still hunt for richer rhymes and a stronger hook' : weak}

Original request:
$originalInstruction

DRAFT:
$draft

Return only the improved lyrics with section tags. No explanations.
''';
    }

    return '''
Преработи този черновик на рап песен. Запази историята, фактите и тона. Не измисляй нова биография.
Това е проход за качество на римите и сюжета — най-важният приоритет.

1) Маркирай всяка двойка крайни рими и пренапиши всяка, която не се римува по ударена гласна и окончание, е граматическа рима, повтаря същата дума или е шаблонна двойка (сърце/небе, болка/любов и подобни).
2) Всеки куплет трябва да добавя ново събитие или образ; ако куплет повтаря предишния с други думи, пренапиши го, за да върви историята напред.
3) Направи припева по-силна и по-лесна за пеене кука.
4) Изравни броя срички в римните двойки.
$cliches$uneven$repeated
Слаби двойки, открити от автоматична проверка:
${weak.isEmpty ? '- няма маркирани, все пак търси по-богати рими и по-силна кука' : weak}

Първоначална задача:
$originalInstruction

ЧЕРНОВИК:
$draft

Върни само подобрения текст със секционни етикети. Без обяснения.
''';
  }

  static String recentSongsSummary(Iterable<dynamic> songs, {int limit = 8}) {
    final lines = <String>[];
    for (final song in songs.take(limit)) {
      final title = (song.title as String?)?.trim() ?? '';
      final theme = (song.theme as String?)?.trim() ?? '';
      final mood = (song.mood as String?)?.trim() ?? '';
      final style = (song.style as String?)?.trim() ?? '';
      if (title.isEmpty && theme.isEmpty && mood.isEmpty && style.isEmpty) {
        continue;
      }
      final extras = <String>[
        if (theme.isNotEmpty) theme,
        if (mood.isNotEmpty) mood,
        if (style.isNotEmpty) style,
      ];
      final label = title.isEmpty ? 'без заглавие' : title;
      lines.add(extras.isEmpty ? '- $label' : '- $label: ${extras.join(', ')}');
    }
    return lines.join('\n');
  }

  static bool isSectionTagLine(String line) {
    final trimmed = line.trim();
    return trimmed.isNotEmpty &&
        (RegExp(r'^\[[^\]]+\]$').hasMatch(trimmed) ||
            _sectionHeading.hasMatch(trimmed));
  }

  static List<String> splitLyricLines(String lyrics) {
    return lyrics.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  }

  static List<AnnotatedLyricLine> annotateLines(
    String lyrics, {
    String scheme = 'AABB',
  }) {
    final raw = splitLyricLines(lyrics);
    final annotations = <AnnotatedLyricLine>[
      for (var i = 0; i < raw.length; i++)
        AnnotatedLyricLine(
          index: i,
          text: raw[i],
          isSectionTag: isSectionTagLine(raw[i]),
          isBlank: raw[i].trim().isEmpty,
        ),
    ];

    var current = <int>[];
    void flush() {
      _markPairs(annotations, current, scheme);
      current = <int>[];
    }

    for (final line in annotations) {
      if (line.isSectionTag) {
        flush();
        continue;
      }
      if (line.isBlank) continue;
      current.add(line.index);
    }
    flush();
    return annotations;
  }

  static void _markPairs(
    List<AnnotatedLyricLine> annotations,
    List<int> indexes,
    String scheme,
  ) {
    if (indexes.length < 2) return;
    final pairs = <(int, int)>[];
    if (scheme == 'ABAB') {
      for (var i = 0; i + 3 < indexes.length; i += 4) {
        pairs.add((indexes[i], indexes[i + 2]));
        pairs.add((indexes[i + 1], indexes[i + 3]));
      }
    } else {
      for (var i = 0; i + 1 < indexes.length; i += 2) {
        pairs.add((indexes[i], indexes[i + 1]));
      }
    }
    for (final pair in pairs) {
      final left = annotations[pair.$1];
      final right = annotations[pair.$2];
      final score = rhymeScore(endWord(left.text), endWord(right.text));
      final strength = score >= 3
          ? RhymeStrength.strong
          : score >= 2
              ? RhymeStrength.ok
              : RhymeStrength.weak;
      var reason = 'богата рима';
      if (score == 0) {
        reason = 'не се римуват по ударение и окончание';
      } else if (normalizeWord(endWord(left.text)) ==
          normalizeWord(endWord(right.text))) {
        reason = 'повтаря се същата дума';
      } else if (score == 1) {
        reason = isGrammaticalRhyme(endWord(left.text), endWord(right.text))
            ? 'граматическа рима (едно и също окончание)'
            : 'слаба/мързелива рима';
      } else if (score == 2) {
        reason = 'приемлива рима';
      }
      annotations[pair.$1] = left.copyWith(
        strength: strength,
        partnerIndex: pair.$2,
        reason: reason,
      );
      annotations[pair.$2] = right.copyWith(
        strength: strength,
        partnerIndex: pair.$1,
        reason: reason,
      );
    }
  }

  static String replaceLineAt(String lyrics, int lineIndex, String newLine) {
    final lines = splitLyricLines(lyrics);
    if (lineIndex < 0 || lineIndex >= lines.length) return lyrics;
    lines[lineIndex] = newLine.trim();
    return lines.join('\n');
  }

  static bool isValidLineRewrite({
    required String originalLyrics,
    required int lineIndex,
    required String newLine,
    String scheme = 'AABB',
  }) {
    final cleaned = newLine.trim();
    if (cleaned.isEmpty || isSectionTagLine(cleaned)) return false;
    final updated = replaceLineAt(originalLyrics, lineIndex, cleaned);
    final annotated = annotateLines(updated, scheme: scheme);
    if (lineIndex < 0 || lineIndex >= annotated.length) return false;
    final line = annotated[lineIndex];
    if (line.partnerIndex == null) return true;
    return line.strength == RhymeStrength.ok ||
        line.strength == RhymeStrength.strong;
  }

  static String buildLineRewriteInstruction({
    required String lyrics,
    required int lineIndex,
    required String rhymeScheme,
    required LyricLanguage language,
  }) {
    final lines = splitLyricLines(lyrics);
    final current = (lineIndex >= 0 && lineIndex < lines.length)
        ? lines[lineIndex].trim()
        : '';
    final annotated = annotateLines(lyrics, scheme: rhymeScheme);
    final partner = (lineIndex >= 0 && lineIndex < annotated.length)
        ? annotated[lineIndex].partnerIndex
        : null;
    final partnerText =
        partner != null && partner >= 0 && partner < lines.length
            ? lines[partner].trim()
            : '';
    if (language == LyricLanguage.english) {
      final partnerBlock =
          partnerText.isEmpty ? '' : 'It must rhyme with:\n$partnerText\n';
      return 'Rewrite only this one lyric line. Keep the same meaning, '
          'rhyme scheme $rhymeScheme and syllable count.\n'
          'Line to replace:\n$current\n'
          '$partnerBlock'
          'Full lyrics for context:\n$lyrics\n'
          'Return only the replacement line, no tags and no quotes.';
    }
    final partnerBlock =
        partnerText.isEmpty ? '' : 'Трябва да се римува с:\n$partnerText\n';
    return 'Препиши само този един ред. Запази смисъла, римната схема '
        '$rhymeScheme и броя срички.\n'
        'Ред за замяна:\n$current\n'
        '$partnerBlock'
        'Цялата песен за контекст:\n$lyrics\n'
        'Върни само новия ред, без етикети и без кавички.';
  }

  static String toSunoTag(String raw) {
    final t = raw.toLowerCase().trim();
    final number = RegExp(r'(\d+)').firstMatch(t)?.group(1);
    String base;
    if (t.contains('pre-chorus') ||
        t.contains('prechorus') ||
        t.contains('предприпев')) {
      base = 'Pre-Chorus';
    } else if (t.contains('final chorus') || t.contains('финален')) {
      base = 'Final Chorus';
    } else if (t.contains('chorus') ||
        t.contains('припев') ||
        t.contains('hook')) {
      base = 'Chorus';
    } else if (t.contains('verse') || t.contains('куплет')) {
      base = 'Verse';
    } else if (t.contains('bridge') || t.contains('бридж')) {
      base = 'Bridge';
    } else if (t.contains('intro') || t.contains('интро')) {
      base = 'Intro';
    } else if (t.contains('outro') || t.contains('аутро')) {
      base = 'Outro';
    } else {
      return raw.trim();
    }
    if (number != null &&
        base != 'Final Chorus' &&
        base != 'Intro' &&
        base != 'Outro' &&
        base != 'Pre-Chorus') {
      return '$base $number';
    }
    return base;
  }

  static String normalizeSunoTags(String lyrics) {
    return lyrics.replaceAllMapped(RegExp(r'\[([^\]]+)\]'), (match) {
      return '[${toSunoTag(match.group(1)!)}]';
    });
  }

  static String buildSunoStylePrompt({
    required String style,
    required String mood,
    required int bpm,
    String vocal = 'deep natural male rap vocal',
    String instruments =
        'tight drums, clean modern mix, controlled low end, reserved autotune',
  }) {
    return 'Genre: $style\n'
        'Tempo: $bpm BPM\n'
        'Vocal: $vocal\n'
        'Mood: $mood\n'
        'Instruments: $instruments';
  }

  static String buildSunoPackage({
    required String lyrics,
    required String stylePrompt,
    String exclude = '',
  }) {
    final buffer = StringBuffer()
      ..writeln('/* Style */')
      ..writeln(stylePrompt.trim())
      ..writeln()
      ..writeln('/* Lyrics */')
      ..writeln(normalizeSunoTags(lyrics).trim());
    if (exclude.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('/* Exclude */')
        ..writeln(exclude.trim());
    }
    return buffer.toString().trim();
  }
}
