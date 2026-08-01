from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:160]!r}")
    file_path.write_text(text.replace(old, new, 1), encoding="utf-8")


# 1) Keep one truly silent, stable foreground notification.
service = "android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt"
replace_once(
    service,
    '        private const val CHANNEL_ID = "iron_voice_service"\n',
    '        private const val CHANNEL_ID = "iron_voice_service_silent_v3"\n',
)
replace_once(
    service,
    '''    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Iron гласов режим",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Показва, когато Iron слуша офлайн за „Hey Iron“."
            setSound(null, null)
            enableVibration(false)
        }

        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
''',
    '''    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java)
        manager.deleteNotificationChannel("iron_voice_service")

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Iron гласов режим",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Постоянен безшумен режим за офлайн „Hey Iron“."
            setSound(null, null)
            enableVibration(false)
            enableLights(false)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }

        manager.createNotificationChannel(channel)
    }
''',
)
replace_once(
    service,
    '''    private fun startAsForeground(status: String) {
        val notification = buildNotification(status)
''',
    '''    private fun startAsForeground(status: String) {
        if (status.isBlank()) return
        val notification = buildNotification()
''',
)
replace_once(
    service,
    '''    private fun updateNotification(status: String) {
        if (!isRunning || !foregroundStarted) return

        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(status))
    }

    private fun buildNotification(status: String): Notification {
''',
    '''    private fun updateNotification(status: String) {
        if (!isRunning || !foregroundStarted || status.isBlank()) return
        // The foreground notification intentionally stays unchanged. Rebuilding it
        // for every microphone state caused repeated alerts on some Android skins.
    }

    private fun buildNotification(): Notification {
''',
)
replace_once(
    service,
    '            .setContentText(status)\n',
    '            .setContentText("Iron е активен • готов за „Hey Iron“")\n',
)
replace_once(
    service,
    '''            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
''',
    '''            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setWhen(0)
            .setCategory(Notification.CATEGORY_SERVICE)
''',
)

# 2) Add a proper chat -> Rap Studio handoff in the local store.
store = "lib/services/local_store.dart"
replace_once(
    store,
    '''  Future<void> loadSongIntoStudio(SongProject song) async {
''',
    '''  Future<void> sendTextToStudio(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    _activeSongId = '';
    _rapDraft = cleanText;
    _rapResult = cleanText;
    _studioRevision++;
    await Future.wait([
      _preferences.setString(_rapDraftKey, _rapDraft),
      _preferences.setString(_rapResultKey, _rapResult),
      _preferences.remove(_activeSongIdKey),
    ]);
    notifyListeners();
  }

  Future<void> loadSongIntoStudio(SongProject song) async {
''',
)

# 3) Wire the handoff to the main navigation.
main_file = "lib/main.dart"
replace_once(
    main_file,
    '''      ChatPage(
        store: widget.store,
        onOpenTools: () => _openSection(4),
      ),
''',
    '''      ChatPage(
        store: widget.store,
        onOpenTools: () => _openSection(4),
        onSendToStudio: (text) async {
          await widget.store.sendTextToStudio(text);
          _openSection(1);
        },
      ),
''',
)

# 4) Add natural-language and one-tap transfer controls in chat.
chat = "lib/pages/chat_page.dart"
replace_once(
    chat,
    '''class ChatPage extends StatefulWidget {
  final LocalStore store;
  final VoidCallback? onOpenTools;

  const ChatPage({
    super.key,
    required this.store,
    this.onOpenTools,
  });
''',
    '''class ChatPage extends StatefulWidget {
  final LocalStore store;
  final VoidCallback? onOpenTools;
  final Future<void> Function(String text)? onSendToStudio;

  const ChatPage({
    super.key,
    required this.store,
    this.onOpenTools,
    this.onSendToStudio,
  });
''',
)
replace_once(
    chat,
    '''  Future<void> _syncNativeAiSettings() {
''',
    '''  bool _requestsStudioTransfer(String value) {
    final text = value.toLowerCase();
    final mentionsStudio = text.contains('рап студио') ||
        text.contains('rap studio') ||
        text.contains('студиото') ||
        text.contains('студио');
    final asksTransfer = text.contains('прехвърли') ||
        text.contains('прати') ||
        text.contains('изпрати') ||
        text.contains('сложи') ||
        text.contains('вкарай') ||
        text.contains('отвори го');
    return mentionsStudio && asksTransfer;
  }

  bool _isDirectStudioTransferCommand(String value) {
    if (!_requestsStudioTransfer(value)) return false;
    final text = value.toLowerCase();
    final asksCreation = text.contains('напиши') ||
        text.contains('направи') ||
        text.contains('създай') ||
        text.contains('генерирай') ||
        text.contains('измисли') ||
        text.contains('редактирай');
    return !asksCreation;
  }

  ChatMessage? _lastAssistantMessage() {
    for (final message in _messages.reversed) {
      if (!message.isUser && !message.isLocalNotice && message.text.trim().isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  Future<void> _sendTextToStudio(String text) async {
    final cleanText = cleanMarkdownForDisplay(text).trim();
    if (cleanText.isEmpty) {
      _showMessage('Няма текст за прехвърляне.');
      return;
    }
    final callback = widget.onSendToStudio;
    if (callback == null) {
      _showMessage('Рап студиото не е достъпно.');
      return;
    }
    await callback(cleanText);
    if (mounted) {
      _showMessage('Текстът е прехвърлен в Рап студио.');
    }
  }

  Future<void> _syncNativeAiSettings() {
''',
)
replace_once(
    chat,
    '''    if (_isListening) {
      await _automation.cancelNativeSpeechRecognition();
      if (mounted) setState(() => _isListening = false);
    }

    final apiKey = widget.store.apiKey.trim();
''',
    '''    if (_isListening) {
      await _automation.cancelNativeSpeechRecognition();
      if (mounted) setState(() => _isListening = false);
    }

    final wantsStudioTransfer = _requestsStudioTransfer(text);
    if (_isDirectStudioTransferCommand(text)) {
      final previous = _lastAssistantMessage();
      _messageController.clear();
      if (previous == null) {
        _showMessage('Първо нека напиша текст, който да прехвърля.');
        return;
      }
      await _sendTextToStudio(previous.text);
      return;
    }

    final apiKey = widget.store.apiKey.trim();
''',
)
replace_once(
    chat,
    '''      setState(() => _messages.add(aiMessage));
      await widget.store.replaceChatHistory(_messages);
      _scrollToBottom();
      await _speak(reply);
''',
    '''      setState(() => _messages.add(aiMessage));
      await widget.store.replaceChatHistory(_messages);
      _scrollToBottom();
      if (wantsStudioTransfer) {
        await _sendTextToStudio(reply);
      }
      await _speak(reply);
''',
)
replace_once(
    chat,
    '''                return _ChatBubble(message: _messages[index]);
''',
    '''                final message = _messages[index];
                return _ChatBubble(
                  message: message,
                  onSendToStudio: !message.isUser && !message.isLocalNotice
                      ? () => _sendTextToStudio(message.text)
                      : null,
                );
''',
)
replace_once(
    chat,
    '''class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});
''',
    '''class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onSendToStudio;

  const _ChatBubble({
    required this.message,
    this.onSendToStudio,
  });
''',
)
replace_once(
    chat,
    '''                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () async {
''',
    '''                if (onSendToStudio != null) ...[
                  Tooltip(
                    message: 'В Рап студио',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onSendToStudio,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.mic_external_on_rounded,
                          size: 16,
                          color: ironGreen,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                ],
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () async {
''',
)

# 5) Version, changelog and regression test.
replace_once(
    "pubspec.yaml",
    "version: 3.3.4+42\n",
    "version: 3.3.5+43\n",
)

Path("CHANGELOG_V335_SILENT_NOTIFICATION_STUDIO_HANDOFF.md").write_text(
    """# v3.3.5 Silent Notification + Studio Handoff

- Uses a new silent Android notification channel and removes the legacy channel.
- Keeps one fixed foreground notification instead of refreshing it for every microphone state.
- Prevents repeated notification sounds on Android skins that ignored the old channel settings.
- Adds a one-tap “В Рап студио” action to AI replies.
- Understands commands such as “прехвърли го в студиото”.
- Can generate a text and automatically open it in Rap Studio in one request.
- Preserves Groq fallback, native Bulgarian speech and stable APK signing.
""",
    encoding="utf-8",
)

Path("test/stable_notification_studio_handoff_test.dart").write_text(
    """import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('foreground notification is silent and no longer refreshed', () {
    final service = File(
      'android/app/src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt',
    ).readAsStringSync();

    expect(service, contains('iron_voice_service_silent_v3'));
    expect(service, contains('deleteNotificationChannel("iron_voice_service")'));
    expect(service, contains('setSound(null, null)'));
    expect(service, contains('setShowBadge(false)'));
    expect(
      service,
      contains('setContentText("Iron е активен • готов за „Hey Iron“")'),
    );

    final updateStart = service.indexOf('private fun updateNotification');
    final buildStart = service.indexOf('private fun buildNotification');
    expect(updateStart, greaterThanOrEqualTo(0));
    expect(buildStart, greaterThan(updateStart));
    final updateBlock = service.substring(updateStart, buildStart);
    expect(updateBlock, isNot(contains('.notify(')));
  });

  test('chat can hand AI text to Rap Studio', () {
    final store = File('lib/services/local_store.dart').readAsStringSync();
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(store, contains('Future<void> sendTextToStudio(String text)'));
    expect(store, contains('_studioRevision++'));
    expect(chat, contains('onSendToStudio'));
    expect(chat, contains('_requestsStudioTransfer'));
    expect(chat, contains("message: 'В Рап студио'"));
    expect(main, contains('widget.store.sendTextToStudio(text)'));
    expect(main, contains('_openSection(1)'));
  });
}
""",
    encoding="utf-8",
)
