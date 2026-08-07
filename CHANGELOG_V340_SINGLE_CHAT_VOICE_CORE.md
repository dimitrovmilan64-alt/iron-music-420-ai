# v3.4.0 Single Chat + Voice Core

- Starts from the clean v3.3.5 source commit.
- Executes deterministic phone and navigation commands before Gemini/Groq.
- Keeps local commands working when both AI providers are rate-limited.
- Adds Bulgarian and English command variants.
- Adds direct voice flows for rap lyrics, rhymes/punchlines and chorus generation.
- Opens the existing Rap Studio, loads the request and starts its existing generator.
- Adds common “Hey Aaron” pronunciation variants to the offline wake-word model.
- Preserves the silent notification channel, native chat speech, Groq fallback and stable signing.

## Build 45 voice lifecycle fix

- Waits for the wake-word recorder to release the microphone before chat dictation.
- Retries one transient Android speech failure without accepting stale callbacks.
- Stops pending recognizer setup and guarantees Activity/service cleanup.
- Pauses wake capture during every app TTS playback and restores it afterward.
- Prevents stale AI and TTS callbacks from blocking or restarting the wrong voice state.
- Restores an enabled Hey Iron service when the app becomes visible again.
- Persists an explicit stop from either the app or the foreground notification.
- Adds executable Kotlin lifecycle tests and runs the complete Flutter test suite in CI.

## Build 46 Realme device regression fix

- Uses one flash-capable rear camera and one shared torch state for UI and voice commands.
- Reads the real Android torch state before the flashlight tile toggles it.
- Routes requested songs to a YouTube search instead of opening the YouTube home page.
- Makes the offline wake phrase stricter and removes unsafe single-word wake fallbacks.
- Uses one Android speech-recognition attempt per wake phrase to stop ColorOS cue loops.
- Adds device-regression tests for flashlight off, YouTube queries and one-shot listening.

## Build 47 Realme wake-word calibration

- Confirms from the Realme log that Android grants the microphone and keeps a stable 16 kHz capture.
- Replays the user's real „Хей Айрън“ recording against the exact APK model during diagnosis.
- Calibrates only complete two-word Bulgarian-accented phrases; no single-word or no-H trigger remains.
- Keeps the RMS voice guard and one-shot Android command recognition to prevent the old cue loop.
- Adds privacy-safe wake health logs so microphone signal and model state can be verified directly.
