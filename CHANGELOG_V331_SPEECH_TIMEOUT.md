# Iron Music 420 AI v3.3.1

- Fixes repeated `error_speech_timeout` from the AI chat microphone on Android.
- Waits briefly after stopping TTS before opening speech recognition.
- Automatically retries once when Android reports initial silence/no-match.
- Replaces raw speech-recognizer error codes with clear Bulgarian guidance.
- Keeps Gemini/Groq fallback, wake-word service, phone actions and UI unchanged.
- Version: 3.3.1+39.
