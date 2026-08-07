# Iron Music 420 AI v3.3.0

- Gemini remains the primary AI provider.
- A configurable OpenAI-compatible backup provider is added.
- Gemini quota, authentication, network, and server failures trigger automatic fallback.
- The same provider chain is used by AI chat, Rap Studio, and the native Hey Iron voice router.
- If both cloud providers fail, native voice commands still use the existing local command parser.
- Provider keys, endpoint, and model are stored locally and synchronized to the Android foreground service.
- Added automated tests for Gemini 429 fallback and the small-screen provider sheet.
- Wake-word assets and the Android action allow-list are unchanged.
- Version: 3.3.0+38.
