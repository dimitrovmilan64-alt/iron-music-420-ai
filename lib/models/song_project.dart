class SongProject {
  final String id;
  final String title;
  final String lyrics;
  final String musicPrompt;
  final String excludePrompt;
  final String theme;
  final String keywords;
  final String style;
  final String mood;
  final String rhymeScheme;
  final String outputType;
  final int bpm;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SongProject({
    required this.id,
    required this.title,
    required this.lyrics,
    required this.musicPrompt,
    required this.excludePrompt,
    required this.theme,
    required this.keywords,
    required this.style,
    required this.mood,
    required this.rhymeScheme,
    required this.outputType,
    required this.bpm,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SongProject.create({
    required String title,
    required String lyrics,
    required String musicPrompt,
    String excludePrompt = '',
    required String theme,
    String keywords = '',
    required String style,
    required String mood,
    required String rhymeScheme,
    String outputType = 'Цяла песен',
    required int bpm,
  }) {
    final now = DateTime.now();
    return SongProject(
      id: now.microsecondsSinceEpoch.toString(),
      title: title.trim().isEmpty ? 'Нова песен' : title.trim(),
      lyrics: lyrics.trim(),
      musicPrompt: musicPrompt.trim(),
      excludePrompt: excludePrompt.trim(),
      theme: theme.trim(),
      keywords: keywords.trim(),
      style: style.trim(),
      mood: mood.trim(),
      rhymeScheme: rhymeScheme.trim(),
      outputType: outputType.trim().isEmpty ? 'Цяла песен' : outputType.trim(),
      bpm: bpm.clamp(60, 220).toInt(),
      createdAt: now,
      updatedAt: now,
    );
  }

  SongProject copyWith({
    String? title,
    String? lyrics,
    String? musicPrompt,
    String? excludePrompt,
    String? theme,
    String? keywords,
    String? style,
    String? mood,
    String? rhymeScheme,
    String? outputType,
    int? bpm,
    DateTime? updatedAt,
  }) {
    return SongProject(
      id: id,
      title: title ?? this.title,
      lyrics: lyrics ?? this.lyrics,
      musicPrompt: musicPrompt ?? this.musicPrompt,
      excludePrompt: excludePrompt ?? this.excludePrompt,
      theme: theme ?? this.theme,
      keywords: keywords ?? this.keywords,
      style: style ?? this.style,
      mood: mood ?? this.mood,
      rhymeScheme: rhymeScheme ?? this.rhymeScheme,
      outputType: outputType ?? this.outputType,
      bpm: bpm ?? this.bpm,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'lyrics': lyrics,
        'musicPrompt': musicPrompt,
        'excludePrompt': excludePrompt,
        'theme': theme,
        'keywords': keywords,
        'style': style,
        'mood': mood,
        'rhymeScheme': rhymeScheme,
        'outputType': outputType,
        'bpm': bpm,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SongProject.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final parsedBpm = int.tryParse(json['bpm']?.toString() ?? '') ?? 140;
    return SongProject(
      id: (json['id']?.toString().trim().isNotEmpty ?? false)
          ? json['id'].toString()
          : now.microsecondsSinceEpoch.toString(),
      title: json['title']?.toString().trim().isNotEmpty == true
          ? json['title'].toString().trim()
          : 'Нова песен',
      lyrics: json['lyrics']?.toString() ?? '',
      musicPrompt: json['musicPrompt']?.toString() ?? '',
      excludePrompt: json['excludePrompt']?.toString() ?? '',
      theme: json['theme']?.toString() ?? '',
      keywords: json['keywords']?.toString() ?? '',
      style: json['style']?.toString() ?? 'Hard trap',
      mood: json['mood']?.toString() ?? 'Тъмно и агресивно',
      rhymeScheme: json['rhymeScheme']?.toString() ?? 'Многосрични рими',
      outputType: json['outputType']?.toString() ?? 'Цяла песен',
      bpm: parsedBpm.clamp(60, 220).toInt(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
    );
  }

  String get sunoPackageText {
    final buffer = StringBuffer();

    if (lyrics.trim().isNotEmpty) {
      buffer
        ..writeln('LYRICS')
        ..writeln('------')
        ..writeln(lyrics.trim())
        ..writeln();
    }

    if (musicPrompt.trim().isNotEmpty) {
      buffer
        ..writeln('STYLE OF MUSIC')
        ..writeln('--------------')
        ..writeln(musicPrompt.trim())
        ..writeln();
    }

    if (excludePrompt.trim().isNotEmpty) {
      buffer
        ..writeln('EXCLUDE')
        ..writeln('-------')
        ..writeln(excludePrompt.trim())
        ..writeln();
    }

    return buffer.toString().trim();
  }

  String get exportText {
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln(
        List<String>.filled(title.length.clamp(4, 40).toInt(), '=').join(),
      )
      ..writeln()
      ..writeln('Стил: $style')
      ..writeln('Настроение: $mood')
      ..writeln('BPM: $bpm')
      ..writeln('Рими: $rhymeScheme')
      ..writeln('Тип: $outputType');

    if (theme.trim().isNotEmpty) buffer.writeln('Тема: $theme');
    if (keywords.trim().isNotEmpty) buffer.writeln('Ключови думи: $keywords');
    buffer.writeln();

    if (lyrics.trim().isNotEmpty) {
      buffer
        ..writeln('ТЕКСТ ЗА SUNO')
        ..writeln('--------------')
        ..writeln(lyrics.trim())
        ..writeln();
    }

    if (musicPrompt.trim().isNotEmpty) {
      buffer
        ..writeln('STYLE OF MUSIC')
        ..writeln('--------------')
        ..writeln(musicPrompt.trim())
        ..writeln();
    }

    if (excludePrompt.trim().isNotEmpty) {
      buffer
        ..writeln('EXCLUDE')
        ..writeln('-------')
        ..writeln(excludePrompt.trim())
        ..writeln();
    }

    buffer.writeln('Създадено с Iron Music 420 AI v2.6.2');
    return buffer.toString().trim();
  }
}
