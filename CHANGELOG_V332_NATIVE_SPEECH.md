# Iron Music 420 AI v3.3.2

- Replaces the AI chat microphone path with Android's native `SpeechRecognizer` using Bulgarian `bg-BG`.
- Stops the background Hey Iron service before chat dictation so its `AudioRecord` releases the microphone.
- Returns partial and final recognized text to Flutter through the existing MethodChannel.
- Restarts Hey Iron automatically after recognition, cancellation, timeout, or error when it was previously active.
- Removes the chat dependency on the Flutter `speech_to_text` runtime path.
- Gemini/Groq fallback, local commands, wake-word assets, UI, and the action allow-list are unchanged.
- Version: `3.3.2+40`.
