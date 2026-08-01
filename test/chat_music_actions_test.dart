import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat exposes practical music actions', () {
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();

    expect(chat, contains("value: 'improve'"));
    expect(chat, contains("value: 'hook'"));
    expect(chat, contains("value: 'analyze'"));
    expect(chat, contains("value: 'music_prompt'"));
    expect(chat, contains("value: 'save'"));
    expect(chat, contains("value: 'studio'"));
    expect(chat, contains('Стегни римите'));
    expect(chat, contains('Направи припев'));
    expect(chat, contains('Анализирай текста'));
    expect(chat, contains('Suno музикален промпт'));
    expect(chat, contains('Запази като песен'));
  });

  test('spoken or typed commands can act on the previous AI reply', () {
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();

    expect(chat, contains('_detectMusicCommand'));
    expect(chat, contains('_lastAssistantMessage()'));
    expect(chat, contains('_runChatMusicAction(musicCommand, previous.text)'));
    expect(chat, contains('_saveChatTextAsSong'));
    expect(chat, contains('widget.store.loadSongIntoStudio(project)'));
    expect(chat, contains('_gemini.generateRap'));
  });
}
