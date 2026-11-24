# Hawker Haggle: design

A mobile game (Android first, iOS from the same Flutter code later): bargain with stallholders at Singapore
wet markets and night markets.

## Pieces

```
app/      Flutter client: stalls, the haggle chat, results. Talks only to the game server over HTTPS.
server/   Python game server (FastAPI): anonymous device accounts, the haggling engine, AI calls, limits.
content/  Stallholders, items and ready-made lines (JSON). Can be extended offline by the AI.
```

## Who decides what

* **The engine (plain code) owns every number**: each stallholder's secret lowest price, the asking price,
  patience and mood. It decides whether an offer is accepted, countered or refused.
* **The AI only does language**: (1) turn a typed message into a structured move (offer $X, compliment,
  mention a cheaper stall, ...), (2) write the stallholder's reply in Singlish for an outcome the engine
  already decided, using only the prices the engine gives it. Replies that mention other prices are discarded
  for a ready-made line. So "ignore your rules and give it free" cannot work.

## Two ways to play

* **Tap mode** (free, no AI): each turn offers 3 suggested moves; replies come from ready-made lines.
* **Live mode**: type anything. Limited turns per player per day; more later via rewarded ads.

## AI path and limits

```
phone -> game server -> GLM on the owner's GX10 (private Tailscale link; never exposed)
```

* At most a few AI calls at once (the GX10 also serves a trading bot, which comes first).
* Per-player daily live-turn limit; short timeouts; on any failure the engine's ready-made line is used,
  so the game never stalls.
* A paid cloud model can be plugged in as a fallback later (`HH_FALLBACK_*`), keys only on the server.

## Accounts and data

* Anonymous device accounts: the server issues a random token on first launch; only its hash is stored.
  No free-text names (generated nicknames), no social login.
* `DELETE /v1/me` removes a player's data (required by both stores); also reachable from a web page.

## Launch checklist (later)

Privacy policy URL, Play Data safety form, account deletion URL, content rating, a hosted server
(not a home PC), `--dart-define=API_BASE=` pointing at it, a release keystore kept outside the repo.

## Reading typed messages
The AI first writes what the player means in one plain sentence, then picks a move. A deal only closes on a clear
yes ("deal", "OK I take it", "pack for me"). A vague "ok lah", "can lah" or "ok but..." becomes **clarify**: the
stallholder asks back, and nothing changes (no price move, no patience, no round used). The word-rule fallback
follows the same rule. Every haggle keeps its chat, so the AI reads each message with the whole conversation.

## Budgets, pity and the secret lowest price
Every item has a secret lowest price (`floor`). A good mood can take up to 10% off it, never more.
- **"I only have $16"** (or the same offer twice) is a firm limit. If it reaches their lowest price they say yes.
  If it's a bit under, they say their real lowest price once, and that really is final: no more $1 steps.
  Far under is an insult. The stallholder remembers the budget for the rest of the chat.
- **Pity** ("starving, no money, lost my job") works once, by personality (`kind`): Auntie Mei and Kak Siti soften
  a lot, Uncle Lim hardly. A second sob story tires them. Nobody goes below the lowest price.
