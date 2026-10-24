# Iron Music 420 AI

Bulgarian AI chat + voice assistant + Rap Studio (Flutter).

## Current status (24 Oct 2026)

- Stable base: **Build 76** (`133d444`)
- UI refresh branch: `agent/build77-ui-refresh-from-build76` (version `3.4.0+77`)
- Voice engine (Hey Iron / sherpa-onnx) is **off by default** to avoid system freezes on Realme.
- Model load has a 15-second safety timeout.
- Test device: Realme 14 Pro+ 5G (RMX5051, Android 16)

## Build

GitHub Actions (`android-build.yml`) produces an arm64 **release** APK.

Manual trigger:
```
gh workflow run android-build.yml --ref agent/build77-ui-refresh-from-build76
```

## Notes

- Do not change `applicationId` or the signing certificate without a strong reason.
- Original leaf artwork: `assets/images/hud_core_exact.png`
- Many historical `CHANGELOG_V*` files exist in the root; they are kept for reference.
