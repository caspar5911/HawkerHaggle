# Hawker Haggle 🍈🐟

A cozy mobile game: bargain with stallholders at Singapore wet markets, night markets and bazaars.
Android first; the Flutter app also builds for iOS. See [DESIGN.md](DESIGN.md) for how it fits together.

- **Tap mode**: pick from 3 suggested moves each turn (free, no AI).
- **Live mode**: type anything; an AI understands it and the stallholder answers in Singlish. The game engine,
  not the AI, decides every price, so stallholders can't be talked into nonsense.

## Server

```bash
cd server
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python -m pytest -q
# optional AI (OpenAI-compatible endpoint), in server/.env (git-ignored):
#   HH_AI_BASE_URL=https://your-model-host/v1
#   HH_AI_MODEL=your-model
HH_SERVE=1 .venv/bin/uvicorn hh.api:app --host 0.0.0.0 --port 8090
```

Without `HH_AI_BASE_URL` the game still works: typed messages are understood by simple word rules and the
stallholders use their ready-made lines.

## App

See `app/README.md`.
