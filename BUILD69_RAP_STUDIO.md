# Build 69 Rap Studio validation

This branch keeps the verified build 68 UI and voice base, then applies the isolated Rap Studio fix during CI.

Validation targets:
- Suno Style changes with song text, theme, keywords, style, mood, BPM and output type.
- Manual Suno field edits are preserved until the user explicitly regenerates them.
- AI text tools visibly report whether they changed the lyrics and refresh auto-managed Suno fields.
- Hook generation works from a theme even when no lyrics exist yet.
- Hey Iron and native voice sources remain untouched.
