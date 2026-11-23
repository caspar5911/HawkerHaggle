"""The game server's HTTP API (/v1). The app only ever talks to this.

Auth: POST /v1/device once, keep the token, send it as `Authorization: Bearer <token>`."""
from __future__ import annotations

import datetime as dt
import json
import os
import random
import secrets
import time
from collections import defaultdict, deque
from dataclasses import asdict
from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from .ai import AI, money
from .engine import Haggle, Item, Personality, State
from .store import Store

ROOT = Path(__file__).resolve().parents[2]
CONTENT = json.loads((ROOT / "content" / "stalls.json").read_text(encoding="utf-8"))
STALLS = {s["id"]: s for s in CONTENT["stalls"]}
PLAYER_LINES = CONTENT["player"]
LIVE_PER_DAY = int(os.environ.get("HH_LIVE_PER_DAY", "15"))
MOVES_PER_MINUTE = 40


class Move(BaseModel):
    pick: int | None = Field(default=None, ge=0, le=2, description="index of a suggested move (tap mode)")
    move: str | None = Field(default=None, description="'walk' or 'accept' (always available)")
    text: str | None = Field(default=None, max_length=300, description="free text (live mode)")


class Start(BaseModel):
    stall: str
    item: str | None = None


def create_app(store: Store | None = None, ai: AI | None = None) -> FastAPI:
    store = store or Store(os.environ.get("HH_DB", str(ROOT / "server" / "var" / "hh.db")))
    ai = ai or AI()
    app = FastAPI(title="Hawker Haggle", version="1")
    hits: dict[str, deque] = defaultdict(deque)

    def limit(key: str, per_minute: int) -> None:
        q, t = hits[key], time.monotonic()
        while q and t - q[0] > 60:
            q.popleft()
        if len(q) >= per_minute:
            raise HTTPException(429, "Slow down a little!")
        q.append(t)

    def player(authorization: str = Header(default="")) -> dict:
        token = authorization.removeprefix("Bearer ").strip()
        p = store.player(token) if token else None
        if not p:
            raise HTTPException(401, "Unknown player: register with POST /v1/device")
        return p

    # ------------------------------------------------------------------ helpers
    def line(stall: dict, item: dict, event: str, h: Haggle, offer=None, seed: int = 0) -> str:
        options = stall["lines"].get(event) or stall["lines"]["smalltalk"]
        pick = options[random.Random(f"{seed}-{h.s.rounds}-{event}").randrange(len(options))]
        return pick.format(item=item["name"], price=money(h.s.deal or h.s.ask), offer=money(offer))

    def player_text(move: str, price=None, seed: str = "") -> str:
        options = PLAYER_LINES.get(move) or PLAYER_LINES["smalltalk"]
        return random.Random(seed).choice(options).replace("${price}", money(price))

    def suggestions(h: Haggle, sid: str) -> list[dict]:
        return [{"move": s["move"], "price": s["price"],
                 "text": player_text(s["move"], s["price"], f"{sid}-{h.s.rounds}-{i}")}
                for i, s in enumerate(h.suggestions())]

    def view(sid: str, stall: dict, item: dict, h: Haggle, said: str, event: str, out, you: str | None,
             live_left: int, ai_line: bool) -> dict:
        return {"id": sid, "stall": stall["id"], "item": item["id"], "event": event, "line": said,
                "ai_line": ai_line, "you_said": you, "ask": h.s.ask, "opening": h.s.opening,
                "patience": max(0, round(h.s.patience)), "mood": round(h.s.mood, 1), "qty": h.s.qty,
                "done": h.s.done, "result": h.s.result, "deal": h.s.deal,
                "stars": out.stars if out else 0, "saved": out.saved if out else 0.0,
                "suggestions": suggestions(h, sid), "accept_text": player_text("accept", h.s.ask, sid),
                "walk_text": player_text("walk", None, sid), "live_left": live_left}

    def load(sid: str, p: dict):
        sess = store.session(sid, p["id"])
        if not sess:
            raise HTTPException(404, "No such haggle")
        stall = STALLS[sess["stall"]]
        item = next(i for i in stall["items"] if i["id"] == sess["item"])
        h = Haggle(Item(**{k: item[k] for k in ("id", "name", "fair", "ask", "floor")}),
                   Personality(**stall["personality"]), state=State(**sess["state"]))
        h.rng.setstate(sess["rng"])
        return sess, stall, item, h

    def today() -> str:
        return dt.datetime.now(dt.timezone.utc).date().isoformat()

    # ------------------------------------------------------------------ routes
    @app.get("/healthz")
    def health():
        return {"ok": True, "ai": ai.enabled}

    @app.post("/v1/device")
    def device(request: Request):
        limit("device:" + (request.client.host if request.client else "?"), 10)
        token, p = store.new_player()
        return {"token": token, "player": {"name": p["name"]}}

    @app.get("/v1/me")
    def me(p: dict = Depends(player)):
        return {"name": p["name"], **store.stats(p["id"]),
                "live_left": max(0, LIVE_PER_DAY - store.ai_used(p["id"], today()))}

    @app.delete("/v1/me")
    def delete_me(p: dict = Depends(player)):
        store.delete_player(p["id"])
        return {"deleted": True}

    @app.get("/v1/stalls")
    def stalls(p: dict = Depends(player)):
        best = store.best(p["id"])
        return {"stalls": [{
            "id": s["id"], "name": s["name"], "stall": s["stall"], "place": s["place"], "look": s["look"],
            "items": [{"id": i["id"], "name": i["name"], "emoji": i["emoji"], "ask": i["ask"],
                       "stars": best.get((s["id"], i["id"]), 0)} for i in s["items"]]}
            for s in CONTENT["stalls"]]}

    @app.post("/v1/haggle")
    def start(body: Start, p: dict = Depends(player)):
        limit(f"p{p['id']}", MOVES_PER_MINUTE)
        stall = STALLS.get(body.stall)
        if not stall:
            raise HTTPException(404, "No such stall")
        item = next((i for i in stall["items"] if i["id"] == body.item), None) or stall["items"][0]
        sid, seed = secrets.token_urlsafe(12), secrets.randbelow(2**31)
        h = Haggle(Item(**{k: item[k] for k in ("id", "name", "fair", "ask", "floor")}),
                   Personality(**stall["personality"]), seed=seed)
        store.save_session(sid, p["id"], stall["id"], item["id"], seed, asdict(h.s), h.rng.getstate())
        said = line(stall, item, "greet", h, seed=seed)
        return view(sid, stall, item, h, said, "greet", None, None,
                    max(0, LIVE_PER_DAY - store.ai_used(p["id"], today())), False)

    @app.post("/v1/haggle/{sid}/move")
    def move(sid: str, body: Move, p: dict = Depends(player)):
        limit(f"p{p['id']}", MOVES_PER_MINUTE)
        sess, stall, item, h = load(sid, p)
        if h.s.done:
            raise HTTPException(409, "This haggle is over")
        live_left = max(0, LIVE_PER_DAY - store.ai_used(p["id"], today()))
        use_ai = False
        if body.text:
            if live_left > 0 and ai.enabled:
                kind, price, use_ai = ai.understand(body.text)
            else:
                from .ai import rules
                kind, price = rules(body.text)
            you = body.text.strip()
        elif body.move in ("walk", "accept"):
            kind, price = body.move, None
            you = player_text(kind, h.s.ask if kind == "accept" else None, f"{sid}-{h.s.rounds}-x")
        elif body.pick is not None:
            sug = suggestions(h, sid)
            if body.pick >= len(sug):
                raise HTTPException(400, "No such suggestion")
            kind, price, you = sug[body.pick]["move"], sug[body.pick]["price"], sug[body.pick]["text"]
        else:
            raise HTTPException(400, "Send pick, move or text")
        if kind == "accept" and price and price < h.s.ask:
            kind = "offer"          # "ok 24 lah" while they ask 26 is an offer of 24, not a yes to 26
        out = h.move(kind, price)
        said, ai_line = None, False
        if use_ai:
            said = ai.say(stall, item, out.event, {"ask": h.s.ask, "offer": out.offer, "deal": h.s.deal})
            ai_line = said is not None
        if use_ai:
            store.add_ai_use(p["id"], today())
            live_left = max(0, live_left - 1)
        said = said or line(stall, item, out.event, h, offer=out.offer, seed=sess["seed"])
        store.save_session(sid, p["id"], stall["id"], item["id"], sess["seed"], asdict(h.s), h.rng.getstate(), out)
        return view(sid, stall, item, h, said, out.event, out, you, live_left, ai_line)

    @app.get("/delete", response_class=HTMLResponse)
    def delete_page():
        return ("<html><body style='font-family:sans-serif;max-width:560px;margin:40px auto;padding:0 16px'>"
                "<h2>Delete your Hawker Haggle data</h2><p>Open the app, go to Settings and tap "
                "<b>Delete my data</b>. Everything linked to your device (haggles, stars, name) is removed at once. "
                "There is no account, email or other personal information to delete beyond that.</p></body></html>")

    return app


app = create_app() if os.environ.get("HH_SERVE") else None
