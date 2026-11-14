# Iron Music 420 AI

Bulgarian-language AI assistant and rap writing studio for Android.

Български AI асистент и студио за рап текстове за Android.

## What it does / Какво прави

**Hey Iron (Хей Айрън)** — chat in Bulgarian with voice input and spoken replies. Gemini is the primary model; Groq is the automatic backup.

**Studio (Студио)** — write and improve rap lyrics, then copy a package ready for Suno (lyrics, style, exclude).

**Songs (Песни)** — a local library of saved songs.

**Settings (Настройки)** — AI keys, voice options, and phone shortcuts (YouTube, flashlight, maps, and more).

Всички текстове и ключове се пазят на телефона. Ключовете за Gemini и Groq се записват криптирано.

## Requirements / Изисквания

- Android 7 (API 24) or newer, arm64.
- A [Gemini](https://aistudio.google.com/apikey) and/or [Groq](https://console.groq.com/keys) API key.

On first launch the app asks you to add a key. You can also open **Настройки**.

## Hey Iron wake word

The always-on “Hey Iron” wake-word listener is **temporarily disabled**. It froze some phones at launch. You can still talk to Iron with the microphone button in the chat tab. The background service will only return after it is proven safe.

Фоновото слушане на „Хей Айрън“ е временно изключено, защото забиваше някои телефони при стартиране. Микрофонът в чата работи.

## Build

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

The app uses Flutter 3.47.9. Impeller is disabled in the Android manifest for stability on budget phones.

While the wake-word service is disabled, CI does not embed the sherpa-onnx keyword models in the APK (this keeps the install much smaller). The Android compile still uses the sherpa AAR; native libraries are stripped from the package.

Release signing uses GitHub secrets (`IRON_KEYSTORE_B64` and related). Do not commit keystores or API keys.

## Privacy

API keys never leave the device except when talking to Gemini or Groq. Chat history and songs stay in local storage. The optional YouTube autoplay helper is an accessibility service that only looks at YouTube results for a few seconds after a voice command.

## License

Private project. Not affiliated with Google, Groq, or Suno.
