import 'dart:io';

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
    expect(
      chat,
      contains("_showMessage('Текстът е прехвърлен в Рап студио.')"),
    );
    expect(main, contains('widget.store.sendTextToStudio(text)'));
    expect(main, contains('_openSection(1)'));
  });
}
