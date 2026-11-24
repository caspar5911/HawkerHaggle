"""The game server's HTTP API (/v1). The app only ever talks to this.

Auth: POST /v1/device once, keep the token, send it as `Authorization: Bearer <token>`."""
from __future__ import annotations

import datetime as dt
import json
import math
import os
import random
import re
import secrets
import time
from collections import defaultdict, deque
from dataclasses import asdict
from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .ai import AI, Heard, fast_offer, heard_by_rules, money, plain_yes, rules
from .engine import Haggle, Item, Personality, State
from .store import Store

ROOT = Path(__file__).resolve().parents[2]
CONTENT = json.loads((ROOT / "content" / "stalls.json").read_text(encoding="utf-8"))
STALLS = {s["id"]: s for s in CONTENT["stalls"]}
PLAYER_LINES = CONTENT["player"]
# No daily AI limit. The GX10 is protected by the AI class (2 calls at once, never queued) and MOVES_PER_MINUTE.
# "live_left" stays in responses only so older test builds of the app keep working.
OLD_APP_LIVE_LEFT = 999
MOVES_PER_MINUTE = 40
TRUSTED_PROXIES = {"127.0.0.1", "::1"}
DOWNLOADS = Path(os.environ.get("HH_DOWNLOADS", str(ROOT / "server" / "var" / "downloads")))
WEB = Path(os.environ.get("HH_WEB", str(ROOT / "server" / "var" / "web")))   # the web version of the game (built)
RELAY_PER_MINUTE = 60
# Web pages elsewhere that may use the AI relay (the game's GitHub Pages copy). Everything else stays same-origin.
RELAY_ORIGINS = [o for o in os.environ.get("HH_RELAY_ORIGINS", "https://caspar5911.github.io").split(",") if o]       # tailscale serve / a relay on this machine


class Move(BaseModel):
    pick: int | None = Field(default=None, ge=0, le=2, description="index of a suggested move (tap mode)")
    move: str | None = Field(default=None, description="'walk', 'accept' (asks to confirm) or 'buy' (already confirmed in the app); 'confirm' or 'cancel' when a deal is pending")
    text: str | None = Field(default=None, max_length=300, description="free text (live mode)")


class Start(BaseModel):
    stall: str
    item: str | None = None


def create_app(store: Store | None = None, ai: AI | None = None) -> FastAPI:
    store = store or Store(os.environ.get("HH_DB", str(ROOT / "server" / "var" / "hh.db")))
    ai = ai or AI()
    app = FastAPI(title="Hawker Haggle", version="1")

    @app.middleware("http")
    async def relay_cors(request: Request, call_next):
        """Let the GitHub Pages copy of the game call the AI relay (and nothing else). Chrome also asks permission
        before a public page talks to a private (Tailscale) address: say yes for the relay."""
        origin = request.headers.get("origin", "")
        allowed = origin in RELAY_ORIGINS and request.url.path.startswith("/ai/")
        if request.method == "OPTIONS" and request.url.path.startswith("/ai/"):
            from starlette.responses import Response
            resp = Response(status_code=204 if allowed else 403)
        else:
            resp = await call_next(request)
        if allowed:
            resp.headers["Access-Control-Allow-Origin"] = origin
            resp.headers["Vary"] = "Origin"
            resp.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
            resp.headers["Access-Control-Allow-Headers"] = "content-type, authorization"
            resp.headers["Access-Control-Max-Age"] = "600"
            if request.headers.get("access-control-request-private-network"):
                resp.headers["Access-Control-Allow-Private-Network"] = "true"
        return resp
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
    def client_ip(request: Request) -> str:
        """The player's address. Behind a proxy on this machine (tailscale serve, or a relay later) every request
        comes from loopback, so use the address the proxy adds, and only then (anyone could send that header)."""
        peer = request.client.host if request.client else "?"
        fwd = request.headers.get("x-forwarded-for", "")
        if peer in TRUSTED_PROXIES and fwd:
            return fwd.split(",")[-1].strip() or peer
        return peer

    def line(stall: dict, item: dict, event: str, h: Haggle, offer=None, seed: int = 0, chat=()) -> str:
        """A ready-made line, avoiding ones already said in this haggle while there are fresh ones left."""
        options = stall["lines"].get(event) or stall["lines"]["smalltalk"]
        price = money(h.s.deal or h.s.pending or h.s.ask)
        fmt = [o.format(item=item["name"], price=price, offer=money(offer)) for o in options]
        said = {m.get("text") for m in chat if m.get("who") == "them"}
        fresh = [t for t in fmt if t not in said] or fmt
        return fresh[random.Random(f"{seed}-{h.s.rounds}-{event}").randrange(len(fresh))]

    def player_text(move: str, price=None, seed: str = "", who: str = "boss") -> str:
        options = PLAYER_LINES.get(move) or PLAYER_LINES["smalltalk"]
        return random.Random(seed).choice(options).replace("${price}", money(price)).replace("{who}", who)

    def suggestions(h: Haggle, sid: str, who: str = "boss") -> list[dict]:
        return [{"move": s["move"], "price": s["price"],
                 "text": player_text(s["move"], s["price"], f"{sid}-{h.s.rounds}-{i}", who)}
                for i, s in enumerate(h.suggestions())]

    def read(text: str, h: Haggle, chat: list, stall: dict, item: dict) -> Heard:
        """What a typed message means. Plain offers and a bare yes take the fast path (no AI reading); a price
        described in words is worked out here from the real prices, never by the model."""
        base = h.s.pending if h.s.pending is not None else h.s.ask
        fast = fast_offer(text, base)
        if fast is not None:
            heard = Heard("offer", fast, False, reading="plain offer")
        elif h.s.pending is not None and plain_yes(text):
            heard = Heard("accept", None, False, reading="plain yes")
        elif ai.enabled:
            heard = ai.understand(text, chat, h.s.ask, item["name"], stall["name"], pending=h.s.pending,
                                  last_offer=h.s.last_offer, qty=h.s.qty)
        else:
            heard = heard_by_rules(text)
        if heard.rel_op:
            if heard.rel_op == "less" and heard.rel_amount:
                price = base - heard.rel_amount
            elif heard.rel_op == "halfway" and h.s.last_offer:
                price = (base + h.s.last_offer) / 2
            elif heard.rel_op == "round_down":
                price = math.floor(base) if base != math.floor(base) else (math.ceil(base / 5) - 1) * 5
            else:
                return heard._replace(move="clarify", price=None, unclear="what price they want to pay")
            if price <= 0:
                return heard._replace(move="clarify", price=None, unclear="what price they want to pay")
            heard = heard._replace(move="offer" if heard.move not in ("budget",) else heard.move, price=price)
        if heard.qty and heard.qty > 2 and heard.move in ("bulk", "offer"):
            # The stalls sell at most two per customer: read their price per piece and say so in the reply.
            per_piece = heard.price / heard.qty if heard.price and heard.per == "total" else heard.price
            return heard._replace(move="bulk", price=per_piece, per="each")
        if heard.move == "offer" and heard.price and heard.per == "total" and h.s.qty > 1:
            heard = heard._replace(price=heard.price / 2)     # "two cases, 14" while buying two: $7 each
        if heard.move == "bulk" and heard.price:
            if heard.per == "total":
                heard = heard._replace(price=heard.price / 2)
            elif heard.per != "each":
                return heard._replace(move="clarify", price=None, unclear="whether the price is for both or each")
        return heard

    def view(sid: str, stall: dict, item: dict, h: Haggle, said: str, event: str, out, you: str | None,
             live_left: int, ai_line: bool) -> dict:
        return {"id": sid, "stall": stall["id"], "item": item["id"], "event": event, "line": said,
                "ai_line": ai_line, "you_said": you, "ask": h.s.ask, "opening": h.s.opening,
                "patience": max(0, round(h.s.patience)), "mood": round(h.s.mood, 1), "qty": h.s.qty,
                "done": h.s.done, "result": h.s.result, "deal": h.s.deal, "pending": h.s.pending,
                "stars": out.stars if out else 0, "saved": out.saved if out else 0.0,
                "suggestions": suggestions(h, sid, stall.get("address", "boss")),
                "accept_text": player_text("accept", h.s.ask, sid, stall.get("address", "boss")),
                "walk_text": player_text("walk", None, sid, stall.get("address", "boss")), "live_left": live_left}

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
        limit("device:" + client_ip(request), 10)
        token, p = store.new_player()
        return {"token": token, "player": {"name": p["name"]}}

    @app.get("/v1/me")
    def me(p: dict = Depends(player)):
        return {"name": p["name"], **store.stats(p["id"]),
                "live_left": OLD_APP_LIVE_LEFT}

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
        said = line(stall, item, "greet", h, seed=seed)
        store.save_session(sid, p["id"], stall["id"], item["id"], seed, asdict(h.s), h.rng.getstate(),
                           chat=[{"who": "them", "text": said, "ask": h.s.ask}])
        return view(sid, stall, item, h, said, "greet", None, None,
                    OLD_APP_LIVE_LEFT, False)

    @app.post("/v1/haggle/{sid}/move")
    def move(sid: str, body: Move, p: dict = Depends(player)):
        limit(f"p{p['id']}", MOVES_PER_MINUTE)
        sess, stall, item, h = load(sid, p)
        if h.s.done:
            raise HTTPException(409, "This haggle is over")
        chat = sess["chat"]
        use_ai, read_ai, unclear, heard = False, False, "", Heard("smalltalk", None, False)
        if body.text:
            heard = read(body.text, h, chat, stall, item)
            kind, price, read_ai, unclear = heard.move, heard.price, heard.ai, heard.unclear
            use_ai = ai.enabled                 # her reply is AI-written even when the reading took the fast path
            you = body.text.strip()
        elif body.move in ("confirm", "cancel"):
            kind, price = body.move, None
            you = ("Deal! " + money(h.s.pending)) if kind == "confirm" and h.s.pending else "Wait, let me think first."
        elif body.move == "buy":
            kind, price = "buy", None
            you = player_text("accept", h.s.pending or h.s.ask, f"{sid}-{h.s.rounds}-x", stall.get("address", "boss"))
        elif body.move in ("walk", "accept"):
            kind, price = body.move, None
            you = player_text(kind, h.s.ask if kind == "accept" else None, f"{sid}-{h.s.rounds}-x",
                              stall.get("address", "boss"))
        elif body.pick is not None:
            sug = suggestions(h, sid, stall.get("address", "boss"))
            if body.pick >= len(sug):
                raise HTTPException(400, "No such suggestion")
            kind, price, you = sug[body.pick]["move"], sug[body.pick]["price"], sug[body.pick]["text"]
        else:
            raise HTTPException(400, "Send pick, move or text")
        if h.s.pending is not None and body.text and (
                (kind == "accept" and not (price and price < h.s.pending)) or (not read_ai and plain_yes(body.text))):
            kind = "confirm"        # a typed yes to "deal at $X, confirm?" (the word rules know a bare "ok lah" too)
        if kind == "accept" and price and price < h.s.ask:
            kind = "offer"          # "ok 24 lah" while they ask 26 is an offer of 24, not a yes to 26
        if kind == "clarify":
            # Not sure what they mean: ask back. Nothing changes: no price move, no patience, no round used.
            out, event = None, "clarify"
        else:
            if heard.also and kind not in ("accept", "confirm", "walk", "buy", "cancel"):
                h.side(heard.also)              # "so nice, 20 can?": the compliment counts too (within its limits)
            out = h.move(kind, price)
            event = out.event
        said, ai_line = None, False
        if use_ai:
            said = ai.say(stall, item, event, {"ask": h.s.ask, "offer": out.offer if out else None,
                                               "deal": h.s.deal or h.s.pending},
                          history=chat, heard=you, also_ok=[m.get("ask") for m in chat] + [h.s.opening],
                          unclear=unclear, budget=h.s.budget, patience=h.s.patience, also=heard.also,
                          note=(f"They asked for {heard.qty}; you only have two left today, so say you can sell "
                                f"them two (prices are per piece)." if heard.qty and heard.qty > 2 else ""))
            ai_line = said is not None
            store.add_ai_use(p["id"], today())          # usage stats only, not a limit
        said = said or line(stall, item, event, h, offer=out.offer if out else None, seed=sess["seed"], chat=chat)
        you_entry = {"who": "you", "text": you[:300], "move": kind}
        if heard.reading or heard.also:
            you_entry.update(reading=heard.reading, also=heard.also)
        chat = chat + [you_entry,
                       {"who": "them", "text": said, "ask": h.s.ask}]
        store.save_session(sid, p["id"], stall["id"], item["id"], sess["seed"], asdict(h.s), h.rng.getstate(), out,
                           chat=chat)
        return view(sid, stall, item, h, said, event, out, you, OLD_APP_LIVE_LEFT, ai_line)

    @app.post("/v1/haggle/{sid}/flag")
    def flag(sid: str, p: dict = Depends(player)):
        """"She misunderstood me": keep the player's last typed message, how it was read, and her reply, so the
        owner can review real misreads and add them to the tests."""
        limit(f"flag{p['id']}", 10)
        sess = store.session(sid, p["id"])
        if not sess:
            raise HTTPException(404, "No such haggle")
        chat = sess["chat"]
        for i in range(len(chat) - 1, 0, -1):
            you, them = chat[i - 1], chat[i]
            if you.get("who") == "you" and them.get("who") == "them":
                store.add_flag(p["id"], sid, {"you": you.get("text"), "read_as": you.get("move"),
                                              "reading": you.get("reading", ""), "also": you.get("also", ""),
                                              "reply": them.get("text"), "context": chat[max(0, i - 7):i - 1]})
                return {"thanks": True}
        raise HTTPException(400, "Nothing to report yet")

    @app.get("/download", response_class=HTMLResponse)
    def downloads():
        """Private test builds for people on the owner's Tailscale (the files live in server/var/downloads, outside
        git). Only .apk files in that folder are listed or served."""
        files = sorted(DOWNLOADS.glob("*.apk"), key=lambda f: f.stat().st_mtime, reverse=True) if DOWNLOADS.is_dir() else []
        rows = "".join(f"<li><a href='/download/{f.name}'>{f.name}</a> ({f.stat().st_size // 1_000_000} MB)</li>"
                       for f in files) or "<li>Nothing here yet.</li>"
        return ("<html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>"
                "<body style='font-family:sans-serif;max-width:560px;margin:40px auto;padding:0 16px'>"
                "<h2>Hawker Haggle</h2><p><a href='https://caspar5911.github.io/HawkerHaggle/' style='font-size:1.2em'>"
                "🎮 Play in your browser</a></p>"
                f"<h3>Android test builds</h3><ul style='line-height:2'>{rows}</ul>"
                "<p>Tap a file to download it, then open it to install.</p></body></html>")

    @app.get("/download/{name}")
    def download(name: str):
        if not re.fullmatch(r"[A-Za-z0-9._-]+\.apk", name) or not (DOWNLOADS / name).is_file():
            raise HTTPException(404, "No such file")
        return FileResponse(DOWNLOADS / name, media_type="application/vnd.android.package-archive", filename=name)

    @app.post("/ai/v1/chat/completions")
    async def relay(request: Request):
        """The web version of the game talks to the AI through here, so the page and the AI share one address (a
        browser won't let a page call another site that doesn't allow it). Only chat completions, size-limited,
        rate-limited per player address, to the AI set in the server's .env. Reachable only on the owner's
        Tailscale."""
        limit("relay:" + client_ip(request), RELAY_PER_MINUTE)
        if not ai.enabled:
            raise HTTPException(503, "No AI set on this server")
        body = await request.body()
        if len(body) > 64_000:
            raise HTTPException(413, "Too big")
        try:
            data = json.loads(body)
        except ValueError:
            raise HTTPException(400, "Bad JSON")
        if not isinstance(data, dict) or not isinstance(data.get("messages"), list):
            raise HTTPException(400, "Need messages")
        data["model"] = ai.model                    # always the server's model
        data["stream"] = False
        headers = {"Content-Type": "application/json"}
        if ai.api_key:
            headers["Authorization"] = f"Bearer {ai.api_key}"

        def call():
            return ai.http.post(f"{ai.base_url.rstrip('/')}/chat/completions", json=data, headers=headers, timeout=90)

        try:
            from starlette.concurrency import run_in_threadpool
            r = await run_in_threadpool(call)
        except Exception:                           # noqa: BLE001 - any network trouble is a 502 for the page
            raise HTTPException(502, "The AI didn't answer")
        try:
            return JSONResponse(r.json(), status_code=r.status_code)
        except ValueError:
            raise HTTPException(502, "The AI sent something odd")

    @app.get("/play")
    def play_root():
        return RedirectResponse("/play/")

    if WEB.is_dir():
        app.mount("/play", StaticFiles(directory=str(WEB), html=True), name="play")

    @app.get("/delete", response_class=HTMLResponse)
    def delete_page():
        return ("<html><body style='font-family:sans-serif;max-width:560px;margin:40px auto;padding:0 16px'>"
                "<h2>Delete your Hawker Haggle data</h2><p>Open the app, go to Settings and tap "
                "<b>Delete my data</b>. Everything linked to your device (haggles, chats, stars, name and any 'she misunderstood "
                "me' reports) is removed at once. "
                "There is no account, email or other personal information to delete beyond that.</p></body></html>")

    return app


app = create_app() if os.environ.get("HH_SERVE") else None
