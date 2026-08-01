# v3.3.5 Silent Notification + Studio Handoff

- Uses a new silent Android notification channel and removes the legacy channel.
- Keeps one fixed foreground notification instead of refreshing it for every microphone state.
- Prevents repeated notification sounds on Android skins that ignored the old channel settings.
- Adds a one-tap “В Рап студио” action to AI replies.
- Understands commands such as “прехвърли го в студиото”.
- Can generate a text and automatically open it in Rap Studio in one request.
- Preserves Groq fallback, native Bulgarian speech and stable APK signing.
