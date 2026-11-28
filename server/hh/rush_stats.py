"""📊 Anonymous Hawker Rush play stats, so the game can be balanced from real play instead of guesses.

What a phone sends (and only this, checked field by field): a random id it made up for itself, which kind of event
("open": the game was opened; "shift": a shift ended or was quit), and numbers about it (the day, stars, customers
served and lost, seconds played, the theme, the build). No names, no accounts, no addresses: the id is stored only as
a keyed hash, with the date (not the time). Players can switch it off in the game.

Capped: a phone's events per day, everyone's events per minute (in the API), and the table's size (oldest pruned).
`python -m hh.rush_stats` prints a summary for the owner.
"""
from __future__ import annotations

import datetime as dt
import os
import re
import sqlite3
from pathlib import Path

from .arcade import Arcade

ID = re.compile(r"^[A-Za-z0-9_-]{16,40}$")
WORD = re.compile(r"^[a-z]{1,16}$")
EVENTS = {"open", "shift"}
MODES = {"day", "daily", "speed", "coop"}
PER_DEVICE_PER_DAY = 200
MAX_ROWS = 200_000


def _int(v, lo, hi):
    return type(v) is int and lo <= v <= hi


class RushStats:
    def __init__(self, arcade: Arcade, max_rows: int = MAX_ROWS, per_device: int = PER_DEVICE_PER_DAY):
        self.arcade = arcade
        self.max_rows = max_rows
        self.per_device = per_device
        with arcade._db() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS rush_stats (
                    id INTEGER PRIMARY KEY, day TEXT NOT NULL, device TEXT NOT NULL, event TEXT NOT NULL,
                    mode TEXT, level INTEGER, stars INTEGER, served INTEGER, lost INTEGER, seconds INTEGER,
                    quit INTEGER, players INTEGER, theme TEXT, build INTEGER);
                CREATE INDEX IF NOT EXISTS rush_stats_device ON rush_stats (device, day);
                CREATE INDEX IF NOT EXISTS rush_stats_day ON rush_stats (day);
            """)

    @staticmethod
    def clean(body) -> dict:
        """The event in its checked shape, or ValueError."""
        if not isinstance(body, dict) or not isinstance(body.get("id"), str) or not ID.match(body["id"]):
            raise ValueError("Bad stats.")
        event = body.get("event")
        if event not in EVENTS:
            raise ValueError("Bad stats.")
        out = {"event": event, "level": body.get("level"), "theme": body.get("theme"), "build": body.get("build")}
        if not _int(out["level"], 1, 99999) or not (out["theme"] is None or (isinstance(out["theme"], str) and WORD.match(out["theme"]))) \
                or not (out["build"] is None or _int(out["build"], 0, 10_000_000)):
            raise ValueError("Bad stats.")
        if event == "shift":
            shift = {k: body.get(k) for k in ("mode", "stars", "served", "lost", "seconds", "quit", "players")}
            if (shift["mode"] not in MODES or not _int(shift["stars"], 0, 3) or not _int(shift["served"], 0, 500)
                    or not _int(shift["lost"], 0, 500) or not _int(shift["seconds"], 0, 3600)
                    or type(shift["quit"]) is not bool or not _int(shift["players"], 1, 4)):
                raise ValueError("Bad stats.")
            shift["quit"] = int(shift["quit"])
            out.update(shift)
        return out

    def record(self, body, today: dt.date) -> dict:
        event = self.clean(body)
        device = self.arcade._sign("rush-stats:" + body["id"])[:16]
        day = today.isoformat()
        with self.arcade._db() as db:
            seen = db.execute("SELECT COUNT(*) FROM rush_stats WHERE device = ? AND day = ?", (device, day)).fetchone()[0]
            if seen >= self.per_device:
                return {"ok": True}   # (quietly: enough from this phone today)
            db.execute(
                "INSERT INTO rush_stats (day, device, event, mode, level, stars, served, lost, seconds, quit, players, theme, build)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (day, device, event["event"], event.get("mode"), event["level"], event.get("stars"), event.get("served"),
                 event.get("lost"), event.get("seconds"), event.get("quit"), event.get("players"), event["theme"], event["build"]))
            total = db.execute("SELECT COUNT(*) FROM rush_stats").fetchone()[0]
            if total > self.max_rows:
                db.execute("DELETE FROM rush_stats WHERE id IN (SELECT id FROM rush_stats ORDER BY id LIMIT ?)",
                           (total - self.max_rows + self.max_rows // 10,))
        return {"ok": True}

    def summary(self, days: int = 30, today: dt.date | None = None) -> dict:
        today = today or dt.date.today()
        since = (today - dt.timedelta(days=days)).isoformat()
        with self.arcade._db() as db:
            q = lambda sql, *a: db.execute(sql, (since, *a)).fetchall()
            players = q("SELECT COUNT(DISTINCT device) FROM rush_stats WHERE day >= ?")[0][0]
            back = q("SELECT COUNT(*) FROM (SELECT device FROM rush_stats WHERE day >= ? GROUP BY device HAVING COUNT(DISTINCT day) >= 2)")[0][0]
            reached = q("SELECT best, COUNT(*) FROM (SELECT device, MAX(level) AS best FROM rush_stats WHERE day >= ? GROUP BY device)"
                        " GROUP BY best ORDER BY best")
            days_played = q("SELECT level, COUNT(*), AVG(stars), AVG(served), AVG(lost), AVG(seconds), SUM(quit) FROM rush_stats"
                            " WHERE day >= ? AND event = 'shift' AND mode IN ('day', 'coop') GROUP BY level ORDER BY level")
            modes = q("SELECT mode, COUNT(*) FROM rush_stats WHERE day >= ? AND event = 'shift' GROUP BY mode")
            themes = q("SELECT theme, COUNT(DISTINCT device) FROM rush_stats WHERE day >= ? GROUP BY theme")
            daily = q("SELECT day, COUNT(DISTINCT device), SUM(event = 'shift') FROM rush_stats WHERE day >= ? GROUP BY day ORDER BY day")
        return {
            "players": players, "came_back": back,
            "furthest_day": {r[0]: r[1] for r in reached},
            "story_days": [{"day": r[0], "shifts": r[1], "stars": round(r[2] or 0, 2), "served": round(r[3] or 0, 1),
                            "lost": round(r[4] or 0, 1), "seconds": round(r[5] or 0), "quit": r[6] or 0} for r in days_played],
            "modes": {r[0]: r[1] for r in modes}, "themes": {r[0] or "?": r[1] for r in themes},
            "by_date": [{"date": r[0], "players": r[1], "shifts": r[2] or 0} for r in daily],
        }


if __name__ == "__main__":  # the owner's report: python -m hh.rush_stats [days]
    import json
    import sys
    root = Path(__file__).resolve().parents[2]
    arcade = Arcade(os.environ.get("HH_ARCADE_DB", str(root / "server" / "var" / "arcade.db")))
    try:
        print(json.dumps(RushStats(arcade).summary(int(sys.argv[1]) if len(sys.argv) > 1 else 30), indent=2))
    except sqlite3.Error as exc:
        print("No stats yet:", exc)
