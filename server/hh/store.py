"""SQLite storage. One short-lived connection per call (the API serves requests on threads), WAL mode, and a
busy timeout so a write never fails just because another one is running."""
from __future__ import annotations

import contextlib
import hashlib
import json
import secrets
import sqlite3
import datetime as dt
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS players (id INTEGER PRIMARY KEY AUTOINCREMENT, token_hash TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, player_id INTEGER NOT NULL, stall TEXT NOT NULL,
    item TEXT NOT NULL, seed INTEGER NOT NULL, state TEXT NOT NULL, rng TEXT NOT NULL, created_at TEXT NOT NULL,
    done INTEGER NOT NULL DEFAULT 0, result TEXT NOT NULL DEFAULT '', deal REAL, stars INTEGER NOT NULL DEFAULT 0,
    saved REAL NOT NULL DEFAULT 0, chat TEXT NOT NULL DEFAULT '[]');
CREATE TABLE IF NOT EXISTS flags (id INTEGER PRIMARY KEY AUTOINCREMENT, player_id INTEGER NOT NULL,
    session_id TEXT NOT NULL, created_at TEXT NOT NULL, exchange TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS ai_use (player_id INTEGER NOT NULL, day TEXT NOT NULL, n INTEGER NOT NULL,
    PRIMARY KEY (player_id, day));
"""

ADJ = ["Shiok", "Steady", "Kiasu", "Atas", "Chill", "Lucky", "Sneaky", "Jolly", "Swee", "Cheeky", "Zesty", "Blur"]
NOUN = ["Otter", "Kaya", "Pandan", "Satay", "Kopi", "Mango", "Durian", "Prata", "Rojak", "Kucing", "Laksa", "Chendol"]


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class Store:
    def __init__(self, path: str | Path):
        self.path = str(path)
        if self.path != ":memory:":
            Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        self._mem = sqlite3.connect(":memory:", check_same_thread=False) if self.path == ":memory:" else None
        with self.conn() as c:
            c.executescript(SCHEMA)
            cols = {r[1] for r in c.execute("PRAGMA table_info(sessions)")}
            if "chat" not in cols:          # databases from before the chat history
                c.execute("ALTER TABLE sessions ADD COLUMN chat TEXT NOT NULL DEFAULT '[]'")

    @contextlib.contextmanager
    def conn(self):
        if self._mem is not None:            # tests: one shared in-memory database
            self._mem.row_factory = sqlite3.Row
            with self._mem:
                yield self._mem
            return
        c = sqlite3.connect(self.path, timeout=10)
        c.row_factory = sqlite3.Row
        c.execute("PRAGMA journal_mode=WAL")
        c.execute("PRAGMA busy_timeout=5000")
        try:
            with c:
                yield c
        finally:
            c.close()

    # ------------------------------------------------------------------ players
    def new_player(self) -> tuple[str, dict]:
        token = secrets.token_urlsafe(32)
        name = f"{secrets.choice(ADJ)} {secrets.choice(NOUN)} {secrets.randbelow(900) + 100}"
        with self.conn() as c:
            cur = c.execute("INSERT INTO players (token_hash, name, created_at) VALUES (?,?,?)",
                            (hash_token(token), name, now()))
            pid = cur.lastrowid
        return token, {"id": pid, "name": name}

    def player(self, token: str) -> dict | None:
        with self.conn() as c:
            r = c.execute("SELECT id, name FROM players WHERE token_hash=?", (hash_token(token),)).fetchone()
        return dict(r) if r else None

    def delete_player(self, pid: int) -> None:
        with self.conn() as c:
            for t in ("sessions", "ai_use", "flags"):
                c.execute(f"DELETE FROM {t} WHERE player_id=?", (pid,))
            c.execute("DELETE FROM players WHERE id=?", (pid,))

    # ------------------------------------------------------------------ "she misunderstood me" reports
    def add_flag(self, pid: int, sid: str, exchange: dict) -> None:
        with self.conn() as c:
            c.execute("INSERT INTO flags (player_id, session_id, created_at, exchange) VALUES (?,?,?,?)",
                      (pid, sid, now(), json.dumps(exchange, ensure_ascii=False)))

    def flags(self, limit: int = 200) -> list[dict]:
        with self.conn() as c:
            rows = c.execute("SELECT f.id, f.created_at, s.stall, s.item, f.exchange FROM flags f "
                             "LEFT JOIN sessions s ON s.id = f.session_id ORDER BY f.id DESC LIMIT ?", (limit,)).fetchall()
        return [{**dict(r), "exchange": json.loads(r["exchange"])} for r in rows]

    # ------------------------------------------------------------------ sessions
    def save_session(self, sid: str, pid: int, stall: str, item: str, seed: int, state: dict, rng, outcome=None,
                     chat: list | None = None):
        rng_json = json.dumps([rng[0], list(rng[1]), rng[2]])
        chat_json = json.dumps((chat or [])[-40:], ensure_ascii=False)
        with self.conn() as c:
            c.execute("INSERT INTO sessions (id, player_id, stall, item, seed, state, rng, created_at, chat) "
                      "VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET state=excluded.state, "
                      "rng=excluded.rng, chat=excluded.chat",
                      (sid, pid, stall, item, seed, json.dumps(state), rng_json, now(), chat_json))
            if outcome and outcome.done:
                c.execute("UPDATE sessions SET done=1, result=?, deal=?, stars=?, saved=? WHERE id=?",
                          (outcome.result, outcome.deal, outcome.stars, outcome.saved, sid))

    def session(self, sid: str, pid: int) -> dict | None:
        with self.conn() as c:
            r = c.execute("SELECT * FROM sessions WHERE id=? AND player_id=?", (sid, pid)).fetchone()
        if not r:
            return None
        d = dict(r)
        d["state"] = json.loads(d["state"])
        d["chat"] = json.loads(d.get("chat") or "[]")
        v, internal, gauss = json.loads(d["rng"])
        d["rng"] = (v, tuple(internal), gauss)
        return d

    def best(self, pid: int) -> dict:
        """{(stall, item): best stars} for the player."""
        with self.conn() as c:
            rows = c.execute("SELECT stall, item, MAX(stars) AS stars FROM sessions WHERE player_id=? AND done=1 "
                             "GROUP BY stall, item", (pid,)).fetchall()
        return {(r["stall"], r["item"]): r["stars"] for r in rows}

    def stats(self, pid: int) -> dict:
        with self.conn() as c:
            r = c.execute("SELECT COUNT(*) AS haggles, SUM(result='deal') AS deals, COALESCE(SUM(stars),0) AS stars, "
                          "COALESCE(MAX(saved),0) AS best_saved FROM sessions WHERE player_id=? AND done=1",
                          (pid,)).fetchone()
        return {k: (r[k] or 0) for k in r.keys()}

    # ------------------------------------------------------------------ AI use per day
    def ai_used(self, pid: int, day: str) -> int:
        with self.conn() as c:
            r = c.execute("SELECT n FROM ai_use WHERE player_id=? AND day=?", (pid, day)).fetchone()
        return r["n"] if r else 0

    def add_ai_use(self, pid: int, day: str) -> None:
        with self.conn() as c:
            c.execute("INSERT INTO ai_use VALUES (?,?,1) ON CONFLICT(player_id, day) DO UPDATE SET n=n+1", (pid, day))
