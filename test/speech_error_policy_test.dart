import 'package:flutter_test/flutter_test.dart';

import 'package:ironmusic420ai/services/speech_error_policy.dart';

void main() {
  test('speech timeout and no match receive one automatic retry', () {
    expect(SpeechErrorPolicy.shouldRetry('error_speech_timeout'), isTrue);
    expect(SpeechErrorPolicy.shouldRetry('error_no_match'), isTrue);
    expect(SpeechErrorPolicy.shouldRetry('error_permission'), isFalse);
  });

  test('raw speech timeout is replaced with a Bulgarian instruction', () {
    final message =
        SpeechErrorPolicy.friendlyMessage('error_speech_timeout');

    expect(message, contains('Не чух реч'));
    expect(message, isNot(contains('error_speech_timeout')));
  });
}
