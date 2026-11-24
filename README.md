# Hawker Haggle 🍈🐟

A cozy mobile game: bargain with stallholders at Singapore wet markets, night markets and bazaars.
Android first; the Flutter app also builds for iOS. See [DESIGN.md](DESIGN.md) for how it fits together.

**Everything runs in the app.** The game, the stallholders, the prices and your progress live on the phone.
The only optional network use is an AI endpoint you choose in **Settings → AI**: any OpenAI-compatible
address (your own model, Ollama, LM Studio, OpenAI, OpenRouter...), a model name and, if needed, an API key.

- **Simple mode** (no AI set, works offline): tap suggested moves or type; replies are ready-made lines.
- **With an AI**: type anything; the AI reads it and the stallholder answers in Singlish. The game, not the AI,
  decides every price, so stallholders can't be talked into nonsense.

## App

```bash
cd app
flutter test                                   # game core, reference check, sweep, screens
flutter build apk --release --split-per-abi    # public build: no AI set by default
# a private build with your own endpoint filled in (keep it out of the public repo):
flutter build apk --release --split-per-abi --dart-define=AI_ENDPOINT=https://host/v1 --dart-define=AI_MODEL=name
# live check of the app's own code against a real endpoint:
AI_ENDPOINT=https://host/v1 AI_MODEL=name dart run tool/live_matrix.dart report.md
```

## Server (reference and older test builds)

`server/` is the original Python version of the game. It stays as the **reference**: the app's Dart core is
checked against its answers (`tools/export_fixtures.py` → `app/test/fixtures/reference.json`), and the AI prompts
are generated from it (`tools/gen_prompts.py`). It also still serves test builds 1–8 until they're retired.

```bash
cd server && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt && .venv/bin/python -m pytest -q
```

When changing the game rules or prompts: change `server/hh`, run its tests, regenerate the fixtures and prompts,
port the change to `app/lib/core`, and run `flutter test`.
