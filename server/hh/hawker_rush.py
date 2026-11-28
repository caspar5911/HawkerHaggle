"""Daily earnings and weekly Speed Run boards in the existing arcade database."""
import datetime as dt
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
from threading import BoundedSemaphore

from .arcade import Arcade, clean_arcade_name, TICKET_HOURS

ENGINE = 6  # the Hawker Rush rules version (+ gentler late days: a slower-growing crowd, a learning day, an easier first star)
SINGAPORE = dt.timezone(dt.timedelta(hours=8))
WORKER = Path(__file__).with_name("hawker_rush_rules") / "verify.mjs"
MAX_ACTIONS = 2500
STARTUP_GRACE_SECONDS = 8  # A shift may begin while the browser fetches config and its ticket.
RUNNERS = BoundedSemaphore(2)
INVALID_RUN = "That run didn't check out, so it wasn't saved."


def period_for(mode, when):
    if mode not in ("daily", "speed"):
        raise ValueError("Choose Daily Rush or Speed Run.")
    day = dt.datetime.fromtimestamp(when, SINGAPORE).date()
    if mode == "speed":
        day -= dt.timedelta(days=day.weekday())
    return day.isoformat()


def replay(mode, period, actions):
    node = shutil.which(os.environ.get("HH_ARCADE_NODE", "node"))
    if not node or not RUNNERS.acquire(blocking=False):
        raise RuntimeError("Replay verification is unavailable. Try saving again shortly.")
    try:
        result = subprocess.run(
            [node, "--max-old-space-size=48", str(WORKER)], env={},
            input=json.dumps({"mode": mode, "period": period, "actions": actions}),
            text=True, capture_output=True, timeout=4, check=True,
        )
        checked = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError) as exc:
        raise RuntimeError("Replay verification is unavailable. Try saving again shortly.") from exc
    finally:
        RUNNERS.release()
    if checked is None:
        raise ValueError(INVALID_RUN)
    return checked


class HawkerRush:
    def __init__(self, arcade: Arcade):
        self.arcade = arcade
        with arcade._db() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS rush_bests (
                    mode TEXT NOT NULL, period TEXT NOT NULL, player TEXT NOT NULL,
                    name TEXT NOT NULL, value INTEGER NOT NULL, at REAL NOT NULL,
                    PRIMARY KEY(mode, period, player));
                CREATE TABLE IF NOT EXISTS rush_receipts (
                    token TEXT PRIMARY KEY, digest TEXT NOT NULL, saved INTEGER NOT NULL, expires INTEGER NOT NULL);
                CREATE INDEX IF NOT EXISTS rush_receipts_expiry ON rush_receipts(expires);
            """)

    def _signature(self, mode, period, stamp, nonce):
        return self.arcade._sign(f"hawker-rush:{ENGINE}:{mode}:{period}:{stamp}:{nonce}")

    def ticket(self, mode):
        stamp = int(self.arcade.clock())
        period = period_for(mode, stamp)
        nonce = secrets.token_hex(12)
        sig = self._signature(mode, period, stamp, nonce)
        return {"mode": mode, "period": period, "engine": ENGINE, "ticket": f"{stamp}.{nonce}.{sig}"}

    def _issued(self, token, mode, period, now):
        parts = re.fullmatch(r"([0-9]{1,12})\.([0-9a-f]{24})\.([0-9a-f]{32})", token) if isinstance(token, str) else None
        if parts:
            stamp, nonce, signature = parts.groups()
            issued = int(stamp)
            if hmac.compare_digest(self._signature(mode, period, stamp, nonce), signature) and issued <= now:
                if now - issued > TICKET_HOURS * 3600:
                    raise ValueError("That ticket expired. Start a new ranked run.")
                return issued
        raise ValueError("This run needs its original online ticket.")

    def top(self, mode, name=""):
        return self._board(mode, period_for(mode, self.arcade.clock()), clean_arcade_name(name))

    def _board(self, mode, period, name):
        order = "DESC" if mode == "daily" else "ASC"
        with self.arcade._db() as db:
            rows = db.execute(
                f"SELECT player,name,value FROM rush_bests WHERE mode=? AND period=? "
                f"ORDER BY value {order}, at, player LIMIT 10", (mode, period)).fetchall()
        return {"mode": mode, "period": period, "entries": [
            {"place": i, "name": r["name"], "value": r["value"],
             **({"you": True} if name.casefold() == r["player"] else {})}
            for i, r in enumerate(rows, 1)]}

    # 👑 the owner's admin: this week's Speed Run and today's Daily Rush, and taking an entry off (a rude name, say)
    def admin_boards(self):
        now = self.arcade.clock()
        out = {}
        for mode in ("daily", "speed"):
            period = period_for(mode, now)
            order = "DESC" if mode == "daily" else "ASC"
            with self.arcade._db() as db:
                rows = db.execute(f"SELECT player, name, value FROM rush_bests WHERE mode=? AND period=? "
                                  f"ORDER BY value {order}, at, player LIMIT 50", (mode, period)).fetchall()
            out[mode] = {"period": period, "entries": [{"player": r["player"], "name": r["name"], "value": r["value"]} for r in rows]}
        return out

    def admin_unlist(self, mode, period, player):
        if mode not in ("daily", "speed") or not isinstance(period, str) or not isinstance(player, str):
            raise ValueError("Bad entry.")
        with self.arcade._db() as db:
            gone = db.execute("DELETE FROM rush_bests WHERE mode=? AND period=? AND player=?", (mode, period, player)).rowcount
        if not gone:
            raise ValueError("That entry isn't on the board.")
        return {"ok": True}

    def submit(self, body):
        now = self.arcade.clock()
        mode, period = body.get("mode"), body.get("period")
        if mode not in ("daily", "speed") or not isinstance(period, str) or len(period) != 10:
            raise ValueError("Invalid challenge.")
        if type(body.get("engine")) is not int or body["engine"] != ENGINE:
            raise ValueError("The game was updated. Refresh the page and start a new run.")
        token = body.get("ticket")
        issued = self._issued(token, mode, period, now)
        name = clean_arcade_name(body.get("name"))
        if not name:
            raise ValueError("Pick a friendly name of 2 to 16 letters or numbers.")
        value, actions = body.get("value"), body.get("actions")
        if type(value) is not int or value < 0 or not isinstance(actions, list) or len(actions) > MAX_ACTIONS:
            raise ValueError(INVALID_RUN)
        # Bound the shape before serializing untrusted JSON. The engine checks operands and legality.
        if any(not isinstance(a, list) or len(a) not in (3, 4) or type(a[0]) is not int
               or type(a[1]) is not str or type(a[2]) not in (int, str)
               or (len(a) == 4 and type(a[3]) is not int) for a in actions):
            raise ValueError(INVALID_RUN)
        digest = hashlib.sha256(json.dumps([name, value, actions], separators=(",", ":"),
                                           allow_nan=False).encode()).hexdigest()
        with self.arcade._db() as db:
            existing = db.execute("SELECT digest,saved FROM rush_receipts WHERE token=?", (token,)).fetchone()
        if existing:
            if existing["digest"] != digest:
                raise ValueError("That ticket was already used for a different submission.")
            saved = bool(existing["saved"])
        else:
            checked = replay(mode, period, actions)
            if checked["value"] != value or checked["ticks"] / 30 > now - issued + STARTUP_GRACE_SECONDS:
                raise ValueError(INVALID_RUN)
            saved = checked["served"] > 0 and checked["value"] > 0
            with self.arcade._db() as db:
                db.execute("DELETE FROM rush_receipts WHERE expires < ?", (int(now),))
                inserted = db.execute("INSERT OR IGNORE INTO rush_receipts VALUES (?, ?, ?, ?)",
                                      (token, digest, saved, issued + TICKET_HOURS * 3600))
                if not inserted.rowcount:
                    receipt = db.execute("SELECT digest FROM rush_receipts WHERE token=?", (token,)).fetchone()
                    if receipt["digest"] != digest:
                        raise ValueError("That ticket was already used for a different submission.")
                elif saved:
                    comparison = ">" if mode == "daily" else "<"
                    db.execute(
                        "INSERT INTO rush_bests (mode,period,player,name,value,at) VALUES (?,?,?,?,?,?) "
                        "ON CONFLICT(mode,period,player) DO UPDATE SET name=excluded.name, value=excluded.value, "
                        f"at=excluded.at WHERE excluded.value {comparison} rush_bests.value",
                        (mode, period, name.casefold(), name, checked["value"], now))
        return {"saved": saved, "name": name, "value": value, **self._board(mode, period, name)}
