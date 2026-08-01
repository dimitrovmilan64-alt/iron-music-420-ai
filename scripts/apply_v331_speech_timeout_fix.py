from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)


root = Path('.')
chat_path = root / 'lib/pages/chat_page.dart'
pubspec_path = root / 'pubspec.yaml'
changelog_path = root / 'CHANGELOG_V331_SPEECH_TIMEOUT.md'

chat = chat_path.read_text(encoding='utf-8')

chat = replace_once(
    chat,
    "import '../services/local_store.dart';\n",
    "import '../services/local_store.dart';\nimport '../services/speech_error_policy.dart';\n",
    'speech policy import',
)

chat = replace_once(
    chat,
    """  bool _voiceReady = false;
  bool _speechSendTriggered = false;
  String _bulgarianLocale = 'bg_BG';
""",
    """  bool _voiceReady = false;
  bool _speechSendTriggered = false;
  bool _speechHeard = false;
  bool _speechRetryScheduled = false;
  int _speechTimeoutRetryCount = 0;
  String _bulgarianLocale = 'bg_BG';
""",
    'speech retry state',
)

chat = replace_once(
    chat,
    """        onError: (error) {
          if (!mounted) return;
          setState(() => _isListening = false);
          _showMessage('Проблем с микрофона: ${error.errorMsg}');
        },
""",
    """        onError: (error) {
          _handleSpeechError(error.errorMsg);
        },
""",
    'speech error callback',
)

old_toggle = """  Future<void> _toggleListening() async {
    if (_speechToText.isListening) {
      await _speechToText.stop();
      if (mounted) setState(() => _isListening = false);
      await _sendRecognizedSpeech();
      return;
    }

    await _flutterTts.stop();

    if (!_speechAvailable) {
      await _prepareSpeechRecognition();
    }

    if (!_speechAvailable) {
      if (mounted) {
        _showMessage(
          'Разпознаването на реч не е налично. Разреши микрофона и провери Google Speech Services.',
        );
      }
      return;
    }

    _speechSendTriggered = false;
    setState(() => _isListening = true);

    try {
      await _speechToText.listen(
        localeId: _bulgarianLocale,
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
        onResult: (result) {
          if (!mounted) return;
          final recognized = result.recognizedWords.trim();
          setState(() {
            _messageController.text = recognized;
            _messageController.selection = TextSelection.fromPosition(
              TextPosition(offset: _messageController.text.length),
            );
          });

          if (result.finalResult && recognized.isNotEmpty) {
            Future.microtask(_sendRecognizedSpeech);
          }
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isListening = false);
      _showMessage('Микрофонът не можа да стартира.');
    }
  }

"""

new_toggle = """  void _handleSpeechError(String errorMessage) {
    if (!mounted) return;

    final canRetry = SpeechErrorPolicy.shouldRetry(errorMessage) &&
        !_speechHeard &&
        !_speechSendTriggered &&
        !_isLoading &&
        _speechTimeoutRetryCount < 1 &&
        !_speechRetryScheduled;

    setState(() => _isListening = false);

    if (canRetry) {
      _speechTimeoutRetryCount++;
      _speechRetryScheduled = true;
      Future<void>.delayed(const Duration(milliseconds: 550), () async {
        if (!mounted) return;
        _speechRetryScheduled = false;
        if (_isLoading || _speechSendTriggered) return;

        try {
          await _speechToText.cancel();
        } catch (_) {
          // Android may already have closed the timed-out recognizer.
        }
        if (!mounted) return;
        await _startSpeechListening(isRetry: true);
      });
      return;
    }

    _speechRetryScheduled = false;
    _showMessage(SpeechErrorPolicy.friendlyMessage(errorMessage));
  }

  Future<void> _startSpeechListening({required bool isRetry}) async {
    if (!mounted || _isLoading) return;

    await _flutterTts.stop();
    await Future<void>.delayed(
      Duration(milliseconds: isRetry ? 450 : 300),
    );
    if (!mounted) return;

    if (!_speechAvailable) {
      await _prepareSpeechRecognition();
    }

    if (!_speechAvailable) {
      if (mounted) {
        _showMessage(
          'Разпознаването на реч не е налично. Разреши микрофона и провери Google Speech Services.',
        );
      }
      return;
    }

    if (!isRetry) _speechTimeoutRetryCount = 0;
    _speechHeard = false;
    _speechSendTriggered = false;
    setState(() => _isListening = true);

    try {
      await _speechToText.listen(
        localeId: _bulgarianLocale,
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
        onResult: (result) {
          if (!mounted) return;
          final recognized = result.recognizedWords.trim();
          if (recognized.isNotEmpty) _speechHeard = true;
          setState(() {
            _messageController.text = recognized;
            _messageController.selection = TextSelection.fromPosition(
              TextPosition(offset: _messageController.text.length),
            );
          });

          if (result.finalResult && recognized.isNotEmpty) {
            Future.microtask(_sendRecognizedSpeech);
          }
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isListening = false);
      _showMessage(
        SpeechErrorPolicy.friendlyMessage('error_recognizer_busy'),
      );
    }
  }

  Future<void> _toggleListening() async {
    if (_speechToText.isListening) {
      _speechRetryScheduled = false;
      await _speechToText.stop();
      if (mounted) setState(() => _isListening = false);
      await _sendRecognizedSpeech();
      return;
    }

    await _startSpeechListening(isRetry: false);
  }

"""

chat = replace_once(
    chat,
    old_toggle,
    new_toggle,
    'speech listening flow',
)
chat_path.write_text(chat, encoding='utf-8')

pubspec = pubspec_path.read_text(encoding='utf-8')
pubspec = replace_once(
    pubspec,
    'version: 3.3.0+38',
    'version: 3.3.1+39',
    'version bump',
)
pubspec_path.write_text(pubspec, encoding='utf-8')

changelog_path.write_text(
    '''# Iron Music 420 AI v3.3.1

- Fixes repeated `error_speech_timeout` from the AI chat microphone on Android.
- Waits briefly after stopping TTS before opening speech recognition.
- Automatically retries once when Android reports initial silence/no-match.
- Replaces raw speech-recognizer error codes with clear Bulgarian guidance.
- Keeps Gemini/Groq fallback, wake-word service, phone actions and UI unchanged.
- Version: 3.3.1+39.
''',
    encoding='utf-8',
)

print('v3.3.1 speech timeout fix applied successfully')
