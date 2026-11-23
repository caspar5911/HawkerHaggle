# Hawker Haggle app (Flutter: Android, iOS)

```bash
flutter pub get
flutter test
# Android test build pointing at a server (or set it later in Settings > Server):
flutter build apk --release --dart-define=API_BASE=https://your-server
```

* Characters are drawn in code (`lib/character.dart`): they blink, breathe, talk and react to each move.
  Real illustrations can replace the painter later without touching the game screens.
* The player is an anonymous device account; the token lives in secure storage (Keychain / Keystore).
* iOS: the same code builds on a Mac with Xcode (`flutter build ipa`); needs an Apple developer account to ship.
* Before a store release: a real signing key (kept out of git), an HTTPS server, and removing the test-only
  Server field in Settings.
