"""Leaderboards for the arcade games (Caspar's Arcade on GitHub Pages). First: Ceiling Punch.

Scores are never taken on trust. Each run's tower comes from here (a seed in a signed, one-use ticket), and a score
is the exact list of taps (as engine ticks): the run is replayed here with the same rules as the browser
(`games/ceiling-punch/public/engine.mjs` in the RuleReaper repo, ported exactly, fixture-tested), and only the floor
the replay reaches counts. Names are cleaned. Nothing about the player is stored but the name they typed.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import math
import os
import re
import secrets
import sqlite3
import time
from pathlib import Path

# ---------------------------------------------------------------------------------------------- Ceiling Punch rules
# A line-by-line port of engine.mjs (version below). JavaScript's 32-bit integer maths (Math.imul, >>>, ^, |) is the
# same as unsigned arithmetic mod 2**32, and its doubles are Python's floats; Math.round is ties-to-plus-infinity.

ENGINE_VERSION = 1  # bump with the game's engine; the browser sends it, others are refused kindly

WIDTH = 416
EDGE = 32
END = WIDTH - EDGE
TICK = 1 / 120
SMASH_SECONDS = .26
BASE_SPEED = 150
MAX_SPEED = 265
SPEED_PER_FLOOR = 3.2
FLOOD_START = -2
FLOOD_BASE = .45
FLOOD_MAX = 1.4
FLOOD_RAMP = .012
FLOOD_GAP_MAX = 2.4
MARGIN = 50
MIN_GAP = 34
M32 = 0xFFFFFFFF


def _imul(a: int, b: int) -> int:
    return (a * b) & M32


def _js_round(x: float) -> int:
    r = math.floor(x)
    return r + 1 if x - r >= .5 else r


def speed_at(floor: int) -> float:
    return min(MAX_SPEED, BASE_SPEED + floor * SPEED_PER_FLOOR)


def flood_rate(t: float) -> float:
    return min(FLOOD_MAX, FLOOD_BASE + t * FLOOD_RAMP)


def difficulty(n: int) -> float:
    return min(1, max(0, n) / 45)


def _mulberry32(a: int):
    state = [a & M32]

    def rng() -> float:
        state[0] = (state[0] + 0x6D2B79F5) & M32
        t = state[0]
        t = _imul(t ^ (t >> 15), t | 1)
        t = (t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & M32)) & M32
        return ((t ^ (t >> 14)) & M32) / 4294967296

    return rng


def _mix(seed: int, n: int) -> int:
    h = (seed ^ _imul(n + 1, 0x9E3779B1)) & M32
    h = _imul(h ^ (h >> 16), 0x85EBCA6B)
    h = _imul(h ^ (h >> 13), 0xC2B2AE35)
    return (h ^ (h >> 16)) & M32


def next_seed(seed: int) -> int:
    return (_imul(seed & M32, 1664525) + 1013904223) & M32


def _fits(spans, left, right, below) -> bool:
    return (left >= MARGIN and right <= WIDTH - MARGIN
            and all(right + MIN_GAP <= a or left >= b + MIN_GAP for a, b in spans)
            and all(right < a or left > b for a, b in (below or [])))


def _make_ceiling(seed: int, n: int, below):
    rng = _mulberry32(_mix(seed, n))
    d = difficulty(n)

    def width() -> int:
        return _js_round((58 - 32 * d) * (.85 + .3 * rng()))

    roll = rng()
    count = 2 if n < 6 else 3 if roll < .25 * (1 - d) else 1 if roll > 1 - .3 * d else 2
    spans: list[tuple[int, int]] = []
    if below and rng() < .5:
        a, b = below[math.floor(rng() * len(below))]
        w = width()
        sign = -1 if rng() < .5 else 1
        centre = (a + b) / 2 + sign * (.25 + .15 * rng()) * min(w, b - a)
        left = _js_round(min(WIDTH - MARGIN - w, max(MARGIN, centre - w / 2)))
        if min(left + w, b) - max(left, a) >= 14:
            spans.append((left, left + w))
    tries = 0
    while len(spans) < count and tries < 60:
        w = width()
        left = _js_round(MARGIN + rng() * (WIDTH - 2 * MARGIN - w))
        if _fits(spans, left, left + w, below):
            spans.append((left, left + w))
        tries += 1
    if not spans:
        spans.append((WIDTH // 2 - 20, WIDTH // 2 + 20))
    return tuple(sorted(spans, key=lambda s: s[0]))


_cache: dict[tuple[int, int], tuple] = {}


def ceiling_at(seed: int, n: int):
    seed &= M32
    if (seed, n) in _cache:
        return _cache[(seed, n)]
    if len(_cache) > 20000:
        _cache.clear()
    k = n
    while k > 0 and (seed, k - 1) not in _cache:
        k -= 1
    while k <= n:
        _cache[(seed, k)] = _make_ceiling(seed, k, _cache[(seed, k - 1)] if k > 0 else None)
        k += 1
    return _cache[(seed, n)]


def double_windows(seed: int, floor: int):
    out = []
    for left, right in ceiling_at(seed, floor):
        for nl, nr in ceiling_at(seed, floor + 1):
            a, b = max(left, nl), min(right, nr)
            if a <= b:
                out.append((a, b))
    return sorted(out)


def create_run(seed: int) -> dict:
    return {"phase": "ready", "floor": 0, "x": EDGE, "direction": 1, "elapsed": 0, "impact": None,
            "seed": seed & M32, "time": 0, "flood": FLOOD_START}


def tap(run: dict) -> bool:
    if run["phase"] == "ready":
        run.update(create_run(run["seed"]), phase="running")
        return True
    if run["phase"] == "lost":
        run.update(create_run(next_seed(run["seed"])), phase="running")
        return True
    if run["phase"] != "running":
        return False
    x, frm = run["x"], run["floor"]
    if not any(a <= x <= b for a, b in ceiling_at(run["seed"], frm)):
        run["phase"] = "lost"
        run["impact"] = {"from": frm, "cleared": 0}
        return True
    cleared = 2 if any(a <= x <= b for a, b in double_windows(run["seed"], frm)) else 1
    run["floor"] = frm + cleared
    run["phase"] = "smash"
    run["elapsed"] = 0
    run["impact"] = {"from": frm, "cleared": cleared}
    if cleared == 2:
        run["flood"] = min(run["flood"], run["floor"] - FLOOD_GAP_MAX)
    return True


def step(run: dict) -> None:
    if run["phase"] not in ("running", "smash"):
        return
    run["time"] += TICK
    run["x"] += run["direction"] * speed_at(run["floor"]) * TICK
    if run["x"] > END:
        run["x"] = END - (run["x"] - END)
        run["direction"] = -1
    elif run["x"] < EDGE:
        run["x"] = EDGE + (EDGE - run["x"])
        run["direction"] = 1
    run["flood"] = max(run["flood"] + flood_rate(run["time"]) * TICK, run["floor"] - FLOOD_GAP_MAX)
    if run["phase"] == "smash":
        run["elapsed"] += TICK
        if run["elapsed"] >= SMASH_SECONDS:
            run["phase"] = "running"
            run["elapsed"] = 0
        return
    if run["flood"] >= run["floor"]:
        run["phase"] = "lost"
        run["impact"] = {"from": run["floor"], "cleared": 0}


MAX_TICKS = 120 * 60 * 30  # a run longer than half an hour isn't a real one
MAX_TAPS = 6000


def replay(seed: int, taps: list[int]) -> int | None:
    """The floor a run reaches: start, then each tap after that many engine ticks, until the run ends. None if the
    taps don't make sense (not whole numbers in order, too many, or the run never ends)."""
    if (not isinstance(taps, list) or len(taps) > MAX_TAPS
            or any(not isinstance(t, int) or isinstance(t, bool) or t < 0 or t > MAX_TICKS for t in taps)
            or any(b < a for a, b in zip(taps, taps[1:]))):
        return None
    run = create_run(seed)
    tap(run)
    n = 0
    for t in taps:
        while n < t and run["phase"] != "lost":
            step(run)
            n += 1
        if run["phase"] == "lost":
            break
        tap(run)
    while run["phase"] != "lost" and n < MAX_TICKS:
        step(run)
        n += 1
    return run["floor"] if run["phase"] == "lost" else None


# --------------------------------------------------------------------------------------------------- names, tickets
_RUDE = ("fuck", "shit", "bitch", "cunt", "dick", "pussy", "nigg", "fag", "slut", "whore", "rape", "nazi", "penis",
         "vagina", "porn", "sex", "asshole", "bastard", "cock", "kanina", "cibai", "knn", "lanjiao", "pukimak")


def clean_arcade_name(raw) -> str:
    """A name for the board: letters, digits, spaces and . ' - only, 2 to 16 characters, nothing rude."""
    if not isinstance(raw, str):
        return ""
    name = " ".join(re.sub(r"[^\w .'-]|_", " ", raw).split())[:16].strip()
    squashed = re.sub(r"[^a-z]", "", name.lower())
    if len(name) < 2 or not re.search(r"[^\W_]", name) or any(w in squashed for w in _RUDE):
        return ""
    return name


TICKET_HOURS = 3


class Arcade:
    """The scores (SQLite) and the signed one-use tickets that carry each run's seed."""

    def __init__(self, path: str | Path, secret: bytes | None = None, clock=time.time):
        self.path = str(path)
        Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        self.clock = clock
        self.secret = secret or self._secret()
        with self._db() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS scores (id INTEGER PRIMARY KEY, game TEXT, name TEXT, floor INTEGER,
                    day TEXT, at REAL);
                CREATE INDEX IF NOT EXISTS scores_game_floor ON scores(game, floor DESC);
                CREATE TABLE IF NOT EXISTS used (ticket TEXT PRIMARY KEY, at REAL);
            """)

    def _db(self) -> sqlite3.Connection:
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        return db

    def _secret(self) -> bytes:
        """A random signing key kept next to the database (never in the repo), made on first use."""
        p = Path(self.path).with_suffix(".key")
        if not p.exists():
            p.write_bytes(secrets.token_bytes(32))
            os.chmod(p, 0o600)
        return p.read_bytes()

    def _sign(self, body: str) -> str:
        return hmac.new(self.secret, body.encode(), hashlib.sha256).hexdigest()[:32]

    def ticket(self, seed: int | None = None) -> dict:
        seed = secrets.randbits(32) if seed is None else seed & M32  # (a given seed: tests only)
        body = f"{seed}.{int(self.clock())}"
        return {"seed": seed, "ticket": f"{body}.{self._sign(body)}", "engine": ENGINE_VERSION}

    def _check_ticket(self, ticket: str, seed: int) -> str | None:
        """None if fine, else why not."""
        parts = ticket.split(".") if isinstance(ticket, str) else []
        if len(parts) != 3 or not parts[0].isdigit() or not parts[1].isdigit():
            return "This run wasn't started online, so it can't go on the board."
        body = f"{parts[0]}.{parts[1]}"
        if not hmac.compare_digest(self._sign(body), parts[2]) or int(parts[0]) != seed:
            return "This run wasn't started online, so it can't go on the board."
        if self.clock() - int(parts[1]) > TICKET_HOURS * 3600:
            return "That run is too old to save. Play a new one!"
        return None

    def submit(self, game: str, ticket: str, seed: int, taps: list, floor: int, name: str, engine: int,
               today: dt.date) -> dict:
        """Check a run by replaying it, then keep it. Raises ValueError with a friendly reason."""
        if game != "ceiling-punch":
            raise ValueError("Unknown game.")
        if engine != ENGINE_VERSION:
            raise ValueError("The game was updated. Refresh the page to save scores again.")
        clean = clean_arcade_name(name)
        if not clean:
            raise ValueError("Pick a name: 2 to 16 letters or numbers, and keep it friendly.")
        why = self._check_ticket(ticket, seed)
        if why:
            raise ValueError(why)
        got = replay(seed, taps)
        if got is None or got != floor:
            raise ValueError("That run didn't check out, so it wasn't saved.")
        now = self.clock()
        with self._db() as db:
            db.execute("DELETE FROM used WHERE at < ?", (now - TICKET_HOURS * 3600 * 2,))
            try:
                db.execute("INSERT INTO used (ticket, at) VALUES (?, ?)", (ticket, now))
            except sqlite3.IntegrityError:
                raise ValueError("That run is already saved.") from None
            if floor > 0:
                db.execute("INSERT INTO scores (game, name, floor, day, at) VALUES (?, ?, ?, ?, ?)",
                           (game, clean, floor, today.isoformat(), now))
        return {"saved": floor > 0, "name": clean, "floor": floor, **self.board(game, today, clean)}

    def board(self, game: str, today: dt.date, you: str = "") -> dict:
        """This week's (Monday to Sunday) and all-time top 10, one line per name (their best)."""
        week = (today - dt.timedelta(days=today.weekday())).isoformat()

        def top(since: str | None) -> list[dict]:
            with self._db() as db:
                rows = db.execute(
                    "SELECT name, MAX(floor) AS floor, MIN(at) AS at FROM scores WHERE game=? AND day>=? "
                    "GROUP BY lower(name) ORDER BY floor DESC, at ASC LIMIT 10",
                    (game, since or "0000")).fetchall()
            return [{"place": i + 1, "name": r["name"], "floor": r["floor"],
                     **({"you": True} if you and r["name"].lower() == you.lower() else {})}
                    for i, r in enumerate(rows)]

        return {"week": top(week), "all": top(None), "week_from": week}
