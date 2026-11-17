import 'package:flutter_test/flutter_test.dart';
import 'package:ironmusic420ai/services/voice_utterance.dart';

void main() {
  test('the captured tail of a spoken sentence is treated as a fragment', () {
    expect(VoiceUtterance.isFragment('и тя има една'), isTrue);
    expect(VoiceUtterance.isFragment('and she has a'), isTrue);
    expect(VoiceUtterance.fragmentRepeatMessage, contains('отново'));
  });

  test('complete requests and short acknowledgements are sent', () {
    expect(
        VoiceUtterance.isFragment('Напиши припев за нощта в София'), isFalse);
    expect(VoiceUtterance.isFragment('да'), isFalse);
    expect(VoiceUtterance.isFragment('не'), isFalse);
    expect(VoiceUtterance.isFragment('ok'), isFalse);
  });

  test('стоп and stop cancel an in-flight reply', () {
    expect(VoiceUtterance.isCancelCommand('Стоп'), isTrue);
    expect(VoiceUtterance.isCancelCommand('stop'), isTrue);
    expect(VoiceUtterance.isCancelCommand('спри го'), isTrue);
    expect(VoiceUtterance.isCancelCommand('Напиши припев'), isFalse);
    expect(VoiceUtterance.isFragment('стоп'), isFalse);
  });
}
