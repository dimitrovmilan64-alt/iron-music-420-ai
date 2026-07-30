import 'package:flutter_test/flutter_test.dart';
import 'package:ironmusic420ai/models/chat_message.dart';
import 'package:ironmusic420ai/models/song_project.dart';

void main() {
  test('ChatMessage се записва и зарежда коректно', () {
    final original = ChatMessage(
      text: 'Тест',
      isUser: true,
      createdAt: DateTime(2026, 7, 27),
    );

    final restored = ChatMessage.fromJson(original.toJson());

    expect(restored.text, 'Тест');
    expect(restored.isUser, isTrue);
    expect(restored.createdAt, DateTime(2026, 7, 27));
  });

  test('SongProject се записва и експортира коректно', () {
    final song = SongProject.create(
      title: 'Тестова песен',
      lyrics: '[Куплет]\nТестов ред',
      musicPrompt: 'Dark Bulgarian rap, 140 BPM',
      excludePrompt: 'female vocal, cheerful pop',
      theme: 'Тест',
      style: 'Hard trap',
      mood: 'Тъмно и агресивно',
      rhymeScheme: 'AABB',
      bpm: 140,
    );

    final restored = SongProject.fromJson(song.toJson());

    expect(restored.title, 'Тестова песен');
    expect(restored.bpm, 140);
    expect(restored.exportText, contains('STYLE OF MUSIC'));
    expect(restored.exportText, contains('EXCLUDE'));
  });
}
