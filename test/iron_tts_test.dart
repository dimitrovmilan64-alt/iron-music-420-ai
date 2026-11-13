import 'package:flutter_test/flutter_test.dart';
import 'package:ironmusic420ai/services/iron_tts.dart';

void main() {
  test('chunkForSpeech splits on sentences and keeps short phrases whole', () {
    expect(IronTts.chunkForSpeech('Здравей, Айрън.'), ['Здравей, Айрън.']);

    final text =
        'Първо изречение е кратко. Второто също е ясно! Третото продължава с много думи, за да се съберат в по-дълъг откъс, който все пак остава естествен.';
    final chunks = IronTts.chunkForSpeech(text, maxChars: 40);
    expect(chunks, isNotEmpty);
    expect(
        chunks.every(
            (chunk) => chunk.length <= 40 || chunk.split(' ').length == 1),
        isTrue);
    expect(chunks.join(' '), text);
  });

  test('Groq chunks stay under the official 200-character input limit', () {
    final text =
        List.filled(12, 'This is a longer English sentence about Iron Music.')
            .join(' ');
    final chunks = IronTts.chunkForSpeech(text, maxChars: IronTts.groqMaxChars);
    expect(chunks, isNotEmpty);
    expect(
        chunks.every((chunk) => chunk.length <= IronTts.groqMaxChars), isTrue);
    expect(IronTts.groqMaxChars, lessThanOrEqualTo(200));
  });

  test('looksBulgarian detects Cyrillic and leaves English alone', () {
    expect(IronTts.looksBulgarian('Здравей, Айрън, готов ли си?'), isTrue);
    expect(IronTts.looksBulgarian('Hello, I am Iron.'), isFalse);
    expect(IronTts.looksBulgarian('Iron Music 420'), isFalse);
  });

  test('deviceVoiceScore prefers Bulgarian network and enhanced voices', () {
    final bulgarian = IronTts.deviceVoiceScore({
      'name': 'bg-BG-neural',
      'locale': 'bg-BG',
      'quality': '400',
      'network_required': 'true',
    });
    final compact = IronTts.deviceVoiceScore({
      'name': 'bg-bg-compact-local',
      'locale': 'bg-BG',
    });
    final english = IronTts.deviceVoiceScore({
      'name': 'en-US-neural',
      'locale': 'en-US',
    });
    expect(bulgarian, greaterThan(compact));
    expect(bulgarian, greaterThan(english));
    expect(english, greaterThan(0));
  });

  test('parseStored keeps Gemini and Groq cloud ids', () {
    final gemini = IronTts.parseStored('gemini:Kore', 'bg-BG')!;
    expect(gemini.provider, IronTtsProvider.gemini);
    expect(gemini.supportsBulgarian, isTrue);
    expect(gemini.name, 'Kore');

    final groq = IronTts.parseStored('groq:autumn', 'en-US')!;
    expect(groq.provider, IronTtsProvider.groq);
    expect(groq.supportsBulgarian, isFalse);
    expect(groq.id, 'groq:autumn');
  });

  test('cloud voices appear only when the matching key is present', () {
    expect(IronTts.cloudVoices(hasGemini: false, hasGroq: false), isEmpty);

    final gemini = IronTts.cloudVoices(hasGemini: true, hasGroq: false);
    expect(gemini, hasLength(IronTts.geminiPrebuiltVoices.length));
    expect(gemini.every((voice) => voice.provider == IronTtsProvider.gemini),
        isTrue);
    expect(gemini.every((voice) => voice.supportsBulgarian), isTrue);
    expect(gemini.map((voice) => voice.name),
        containsAll(['Kore', 'Aoede', 'Sulafat', 'Puck']));

    final groq = IronTts.cloudVoices(hasGemini: false, hasGroq: true);
    expect(groq, hasLength(IronTts.groqEnglishVoices.length));
    expect(groq.every((voice) => voice.supportsBulgarian), isFalse);
    expect(groq.map((voice) => voice.badge), everyElement(contains('само EN')));
  });

  test('Groq is marked English-only and falls back for Bulgarian text', () {
    final autumn = IronTts.cloudVoices(hasGemini: false, hasGroq: true).first;
    expect(
      IronTts.playbackProvider(selected: autumn, text: 'Здравей, Айрън.'),
      IronTtsProvider.device,
    );
    expect(
      IronTts.playbackProvider(selected: autumn, text: 'Hello from Iron.'),
      IronTtsProvider.groq,
    );
  });

  test('Gemini stays on the cloud path for Bulgarian text', () {
    final kore = IronTts.cloudVoices(hasGemini: true, hasGroq: false)
        .firstWhere((voice) => voice.name == 'Kore');
    expect(kore.supportsBulgarian, isTrue);
    expect(
      IronTts.playbackProvider(selected: kore, text: 'Здравей, аз съм Айрън.'),
      IronTtsProvider.gemini,
    );
  });

  test('official model ids and endpoints stay current', () {
    expect(IronTts.geminiModels, contains('gemini-3.8-flash-lite-tts'));
    expect(IronTts.geminiModels, contains('gemini-3.8-flash-tts'));
    expect(IronTts.groqModel, 'canopylabs/orpheus-v1-english');
    expect(IronTts.groqEndpoint, 'https://api.groq.com/openai/v1/audio/speech');
  });

  test('cache keys include the voice, rate, pitch and phrase', () {
    final a = IronTts.cacheKey(
      voiceId: 'gemini:Kore',
      rate: 0.44,
      pitch: 0.92,
      text: 'Здравей',
    );
    final b = IronTts.cacheKey(
      voiceId: 'gemini:Kore',
      rate: 0.44,
      pitch: 0.92,
      text: 'Друго',
    );
    expect(a, isNot(b));
    expect(a, contains('gemini:Kore'));
    expect(a, contains('Здравей'));
  });
}
