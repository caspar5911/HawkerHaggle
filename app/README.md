# Hawker Haggle app (Flutter: Android, iOS)

The whole game runs in the app (`lib/core`, plain Dart). The only optional network use is the AI endpoint set in
Settings → AI (any OpenAI-compatible address, model name, optional API key).

```bash
flutter pub get
flutter test        # reference check vs the Python version, full sweep, scenarios with a pretend AI, screens
flutter build apk --release --split-per-abi
# private build with your endpoint pre-filled (don't publish it):
flutter build apk --release --split-per-abi --dart-define=AI_ENDPOINT=https://host/v1 --dart-define=AI_MODEL=name
AI_ENDPOINT=https://host/v1 AI_MODEL=name dart run tool/live_matrix.dart report.md   # live check
```

* Characters are drawn in code (`lib/character.dart`): they blink, breathe, talk and react to each move.
* Progress, reports and the AI key live in secure storage (Keychain / Keystore). Delete my data wipes the game data.
* Android blocks plain `http://` addresses; use `https://` endpoints (Tailscale serve gives one).
* iOS: the same code builds on a Mac with Xcode (`flutter build ipa`); needs an Apple developer account to ship.
