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

## Build 48 YouTube playback fix

- Preserves the exact requested song for „Отвори YouTube и пусни Бяла роза“.
- Uses Android's media-play-from-search contract before opening YouTube results.
- Replaces the unreliable external ACTION_SEARCH route with an ACTION_VIEW deep-link fallback.
- Logs the selected YouTube launch route without recording the spoken song title.
- Adds native and Flutter regression coverage for the exact Bulgarian command.

## Build 49 one-shot YouTube auto-play

- Adds an explicit, user-enabled accessibility setting for deterministic YouTube playback.
- Arms the automation only after a spoken Iron command and expires it after 15 seconds.
- Reads events only from the official YouTube package and never requests gesture access.
- Clicks one visible, non-ad, non-Shorts result that contains every requested title token.
- Shows an in-app disclosure explaining the screen access before Android settings are opened.
- Adds native matching tests and Flutter privacy/regression checks.

## Build 50 any-song YouTube auto-play

- Removes the requirement for every spoken query token to appear in the displayed title.
- Verifies the active YouTube search field independently from result-title spelling.
- Prefers a strict title match when one exists, then falls back to YouTube's first real video.
- Continues to reject ads, Shorts, editable search controls and non-video suggestions.
- Adds regression coverage for punctuation-heavy and differently transliterated song names.

## Build 51 unified Hey Iron chat

- Makes the existing chat the single conversational path for typed, tapped-microphone and wake-phrase requests.
- Keeps deterministic phone commands local, including any-song YouTube playback and flashlight control.
- Moves the Hey Iron on/off control into the chat and removes its duplicate tools-screen card.
- Renames the main AI tab and chat header to „Хей Айрън“.
- Tightens the full-phrase acoustic threshold and voiced-frame gate to reduce occasional ambient false wakes.
- Removes the unused legacy home page, native duplicate AI router, provider-sync bridge and duplicate command handler.

## Build 52 strict Hey Iron activation

- Keeps only the complete two-word „Хей Айрън“ wake phrase and makes its acoustic match less permissive.
- Uses one keyword-search path and requires consecutive voiced frames instead of carrying old noise forward.
- Adds a short wake cooldown so one sound cannot immediately start another listening cycle.
- Rejects bare „Iron/Айрън“ and the assistant's own „Слушам“ as chat prompts.
- Collapses repeated greeting and duplicate voice prompts before they can flood the unified chat.
- Adds executable native regression tests for wake gating, cooldowns and prompt filtering.

## Build 55 core UI restart

- Restarts the main chat UI around a larger central Iron core stage.
- Keeps the fixed voice path untouched while refreshing only Flutter layout and visuals.
- Adds compact HUD chips for wake, online and interaction states.
- Adds a holographic platform under the 3D cannabis core.
- Keeps the chat, microphone, voice replies and AI provider controls on the same screen.

## Build 56 HUD control center

- Replaces the first chat-first screen with a HUD-style Iron control center.
- Keeps chat available behind the `CHAT` and `KEYBOARD` controls.
- Adds direct HUD controls for commands, music mode, flashlight, settings and voice status.
- Keeps the fixed Bulgarian voice path untouched.


## Build 65 real leaf core fix

- Replaces the stick-thin leaf mask in the central sphere with wider serrated cannabis leaflets.
- Uses one shared cannabis leaf silhouette for both the filled body and the pulsing vein overlay.
- Enlarges the core leaf slightly so it reads as the living nucleus instead of a small line drawing.
- Preserves the Build 64 mobile layout and the native Bulgarian voice path.

## Build 64 mobile core fix

- Removes the Build 63 side HUD overlay from the phone first screen after real-device review.
- Keeps the sci-fi core and segmented machine ring while moving controls below the core.
- Prevents clipped action/status text and keeps the bottom `HEY IRON` dock inside the viewport.
- Leaves the native Bulgarian voice path untouched.

## Build 63 reference HUD core

- Rebuilds the first screen to match the supplied sci-fi HUD references more closely.
- Adds left action panels, right status panels, top online/mic controls and a bottom `HEY IRON` dock.
- Adds a segmented machine ring around the core so the center reads more like a 3D reactor.
- Keeps the Build 62 code-drawn cannabis leaf and leaves the native Bulgarian voice path untouched.

## Build 62 real 3D core

- Replaces the flat `hud_core_exact.png` core body with a code-drawn 3D cannabis leaf inside the glass sphere.
- Keeps the pulsing vein overlay locked to the same leaf silhouette so veins do not cross empty space.
- Adds subtle pseudo-perspective leaf motion inside the orb while preserving the clean Build 60 first screen.
- Renames the chat transition away from HUD wording and keeps the fixed Bulgarian voice path untouched.

## Build 61 3D core aligned veins

- Clips the animated vein pulse inside a cannabis leaf silhouette instead of painting over the whole orb.
- Reduces vein overlay intensity so the existing leaf veins stay readable.
- Adds stronger sphere depth: cast shadow, inner lower shade, rim lift and glass highlight.
- Preserves the clean Build 60 first screen and the fixed Bulgarian voice path.

## Build 60 clean core interface

- Replaces the HUD control center with a minimal living-core start screen.
- Removes the start-screen command grid, status cards and bottom tab bar.
- Keeps the large animated cannabis core as the main interaction target.
- Leaves chat, microphone and voice controls close to the core without crowding it.
- Preserves the fixed Bulgarian voice path.

## Build 59 single leaf only

- Keeps the cannabis leaf only inside the center HUD core.
- Replaces the bottom `Хей Айрън` tab icon with a chat icon.
- Replaces the wake-word status leaf icon with a radar icon.
- Removes the faint background mini-leaf watermarks.

## Build 58 living leaf veins

- Adds a visible animated vein layer over the single HUD core cannabis leaf.
- Keeps Build 57's duplicate-leaf fix: the generated `hud_core_exact.png` remains the only leaf body.
- Makes the core read as alive through pulsing vein glow, moving energy highlights and small sparks.

## Build 57 single-leaf HUD

- Removes the extra painted cannabis overlay from the core.
- Keeps the generated `hud_core_exact.png` core leaf as the single visible leaf.
- Preserves the HUD-first layout and the fixed Bulgarian voice path.
