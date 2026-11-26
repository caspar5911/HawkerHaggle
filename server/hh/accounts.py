"""Player accounts for people who play through a public address (a friend's domain) instead of Tailscale.

Anyone can sign up; an account can use the AI only after the admin approves it. Passwords are kept as scrypt hashes
(never readable), sessions as SHA-256 hashes of random tokens. The admin account starts as admin/admin and can only
log in from the owner's own Tailscale login (refused for friends on the tailnet and for the public gateway), so the
default password is useless to anyone else; the admin screen nags until it is changed. Every account can change its own password.
"""
from __future__ import annotations

import contextlib
import datetime as dt
import hashlib
import hmac
import json
import re
import secrets
import sqlite3
import time
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS accounts (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL COLLATE NOCASE,
    pw TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'player', status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL, decided_at TEXT, last_used TEXT, default_pw INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS logins (token_hash TEXT PRIMARY KEY, account_id INTEGER NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS ai_calls (account_id INTEGER NOT NULL, day TEXT NOT NULL, n INTEGER NOT NULL,
    PRIMARY KEY (account_id, day));
CREATE TABLE IF NOT EXISTS saves (account_id INTEGER PRIMARY KEY, data TEXT NOT NULL, rev INTEGER NOT NULL,
    updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS legend_events (id INTEGER PRIMARY KEY AUTOINCREMENT, stall TEXT NOT NULL,
    day_from TEXT NOT NULL, day_to TEXT NOT NULL, item TEXT NOT NULL, created_at TEXT NOT NULL);
"""

ADMIN = "admin"
STATUSES = ("pending", "approved", "rejected", "removed")
USERNAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{2,19}")
PW_MIN, PW_MAX = 4, 128      # 4 so the admin's own "admin" fits; the screens suggest 8+
MAX_PENDING = 50             # sign-ups stop while this many wait for the admin
SAVE_MAX = 512 * 1024        # one account's game progress (a full one, 500 haggles, is about 160 KB)
FAILS_BEFORE_LOCK, LOCK_SECONDS = 5, 15 * 60
SCRYPT = dict(n=2**14, r=8, p=1, dklen=32)


class AccountError(Exception):
    def __init__(self, code: int, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def hash_pw(pw: str) -> str:
    salt = secrets.token_bytes(16)
    h = hashlib.scrypt(pw.encode(), salt=salt, **SCRYPT)
    return f"scrypt${salt.hex()}${h.hex()}"


def check_pw(pw: str, stored: str) -> bool:
    try:
        _, salt, h = stored.split("$")
        got = hashlib.scrypt(pw.encode(), salt=bytes.fromhex(salt), **SCRYPT)
        return hmac.compare_digest(got.hex(), h)
    except ValueError:
        return False


_DUMMY = hash_pw("not a real password")      # wrong usernames take as long as wrong passwords


def clean_name(raw) -> str:
    """A player's chosen name, safe to show and to put in a stallholder's notes: letters, spaces and . ' - only."""
    if not isinstance(raw, str):
        return ""
    name = " ".join(re.sub(r"[^\w .'-]|[\d_]", " ", raw).split())[:20].strip()
    return name if re.search(r"[^\W\d_]", name) else ""


def _tok(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class Accounts:
    def __init__(self, path: str | Path, clock=time.monotonic):
        self.path = str(path)
        self.clock = clock
        self.fails: dict[str, list[float]] = {}
        Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        with self._db() as db:
            db.executescript(SCHEMA)
            if not db.execute("SELECT 1 FROM accounts WHERE role='admin'").fetchone():
                db.execute("INSERT INTO accounts (username, pw, role, status, created_at, default_pw) VALUES (?,?,?,?,?,1)",
                           (ADMIN, hash_pw("admin"), "admin", "approved", now()))

    @contextlib.contextmanager
    def _db(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA journal_mode=WAL")
        try:
            with db:
                yield db
        finally:
            db.close()

    # ------------------------------------------------------------------ players
    @staticmethod
    def _check_new_pw(pw: str) -> None:
        if not isinstance(pw, str) or not PW_MIN <= len(pw) <= PW_MAX:
            raise AccountError(400, f"Password needs at least {PW_MIN} characters (8 or more is better).")

    def signup(self, username: str, pw: str) -> dict:
        username = (username or "").strip()
        if not USERNAME.fullmatch(username):
            raise AccountError(400, "Username: 3 to 20 letters or numbers (. _ - allowed), starting with a letter or number.")
        if username.lower() == ADMIN:
            raise AccountError(409, "That username is taken. Try another one.")
        self._check_new_pw(pw)
        with self._db() as db:
            if db.execute("SELECT COUNT(*) FROM accounts WHERE status='pending'").fetchone()[0] >= MAX_PENDING:
                raise AccountError(429, "Too many sign-ups waiting right now. Try again later.")
            try:
                cur = db.execute("INSERT INTO accounts (username, pw, created_at) VALUES (?,?,?)",
                                 (username, hash_pw(pw), now()))
            except sqlite3.IntegrityError:
                raise AccountError(409, "That username is taken. Try another one.")
            return self._new_login(db, cur.lastrowid)

    def admin_password_changed(self) -> bool:
        """The admin account may be used from anywhere only once its default password has been changed."""
        with self._db() as db:
            r = db.execute("SELECT default_pw FROM accounts WHERE role='admin'").fetchone()
        return r is not None and not r["default_pw"]

    def login(self, username: str, pw: str, *, admin_allowed: bool, owner: bool | None = None) -> dict:
        """admin_allowed: the admin account may log in from here (the owner's own Tailscale login; anywhere once its
        password has been changed). Otherwise it simply doesn't exist (same answer as a wrong password). owner: the
        owner's own login, whose wrong guesses are counted apart, so others' guessing can't lock the owner out."""
        name = (username or "").strip().lower()
        owner = admin_allowed if owner is None else owner
        key = ("owner:" if owner else "others:") + name
        t = self.clock()
        recent = [x for x in self.fails.get(key, []) if t - x < LOCK_SECONDS]
        self.fails[key] = recent
        if len(recent) >= FAILS_BEFORE_LOCK:
            raise AccountError(429, "Too many wrong passwords. Wait 15 minutes and try again.")
        with self._db() as db:
            row = db.execute("SELECT * FROM accounts WHERE username=?", (name,)).fetchone()
            if row is not None and row["role"] == "admin" and not admin_allowed:
                row = None
            ok = check_pw(pw or "", row["pw"] if row else _DUMMY) and row is not None
            if not ok:
                self.fails[key].append(t)
                raise AccountError(401, "Wrong username or password.")
            self.fails.pop(key, None)
            return self._new_login(db, row["id"])

    def _new_login(self, db, account_id: int) -> dict:
        token = "hh_" + secrets.token_urlsafe(32)
        db.execute("INSERT INTO logins (token_hash, account_id, created_at) VALUES (?,?,?)", (_tok(token), account_id, now()))
        row = db.execute("SELECT * FROM accounts WHERE id=?", (account_id,)).fetchone()
        return {"token": token, **self._public(row)}

    @staticmethod
    def _public(row) -> dict:
        return {"username": row["username"], "status": row["status"], "admin": row["role"] == "admin",
                "default_password": bool(row["default_pw"])}

    def who(self, token: str) -> sqlite3.Row | None:
        if not token:
            return None
        with self._db() as db:
            return db.execute("SELECT a.* FROM logins l JOIN accounts a ON a.id=l.account_id WHERE l.token_hash=?",
                              (_tok(token),)).fetchone()

    def me(self, token: str) -> dict:
        row = self.who(token)
        if row is None:
            raise AccountError(401, "Please log in again.")
        return self._public(row)

    def logout(self, token: str) -> None:
        with self._db() as db:
            db.execute("DELETE FROM logins WHERE token_hash=?", (_tok(token),))

    def change_password(self, token: str, old: str, new: str) -> None:
        row = self.who(token)
        if row is None:
            raise AccountError(401, "Please log in again.")
        if not check_pw(old or "", row["pw"]):
            raise AccountError(403, "Your current password is wrong.")
        self._check_new_pw(new)
        if new == old:
            raise AccountError(400, "Pick a different password.")
        with self._db() as db:
            db.execute("UPDATE accounts SET pw=?, default_pw=0 WHERE id=?", (hash_pw(new), row["id"]))
            # other phones logged in with the old password are logged out; this one stays in
            db.execute("DELETE FROM logins WHERE account_id=? AND token_hash<>?", (row["id"], _tok(token)))

    def use_ai(self, row, per_day: int) -> None:
        """Count one AI call for an approved account; refuse past its daily allowance."""
        day = dt.date.today().isoformat()
        with self._db() as db:
            n = db.execute("SELECT n FROM ai_calls WHERE account_id=? AND day=?", (row["id"], day)).fetchone()
            if n and n[0] >= per_day:
                raise AccountError(429, "That's all the AI chat for today. Come back tomorrow!")
            db.execute("INSERT INTO ai_calls (account_id, day, n) VALUES (?,?,1) "
                       "ON CONFLICT(account_id, day) DO UPDATE SET n=n+1", (row["id"], day))
            db.execute("UPDATE accounts SET last_used=? WHERE id=?", (now(), row["id"]))

    def calls_today(self) -> int:
        with self._db() as db:
            return db.execute("SELECT COALESCE(SUM(n),0) FROM ai_calls WHERE day=?", (dt.date.today().isoformat(),)).fetchone()[0]

    # ------------------------------------------------------------------ game progress (one copy per account)
    @staticmethod
    def _can_save(row) -> None:
        if row is None:
            raise AccountError(401, "Please log in again.")
        if row["status"] not in ("pending", "approved"):
            raise AccountError(403, "This account can't keep progress.")

    def progress(self, row) -> dict:
        self._can_save(row)
        with self._db() as db:
            r = db.execute("SELECT data, rev FROM saves WHERE account_id=?", (row["id"],)).fetchone()
        return {"data": r["data"], "rev": r["rev"]} if r else {"data": None, "rev": 0}

    def save_progress(self, row, data: str, rev: int) -> dict:
        """rev is the copy the phone started from; if another phone saved since, refuse (409) so the phone takes the
        newer copy instead of overwriting it."""
        self._can_save(row)
        if not isinstance(data, str) or len(data.encode()) > SAVE_MAX:
            raise AccountError(413, "That progress is too big to keep.")
        with self._db() as db:
            r = db.execute("SELECT rev FROM saves WHERE account_id=?", (row["id"],)).fetchone()
            current = r["rev"] if r else 0
            if rev != current:
                raise AccountError(409, "Newer progress was saved from another phone.")
            db.execute("INSERT INTO saves (account_id, data, rev, updated_at) VALUES (?,?,?,?) ON CONFLICT(account_id) "
                       "DO UPDATE SET data=excluded.data, rev=excluded.rev, updated_at=excluded.updated_at",
                       (row["id"], data, current + 1, now()))
        return {"rev": current + 1}

    def delete_progress(self, row) -> dict:
        """Delete my data: the account starts over (the rev keeps counting so other phones notice)."""
        self._can_save(row)
        with self._db() as db:
            r = db.execute("SELECT rev FROM saves WHERE account_id=?", (row["id"],)).fetchone()
            if r is None:
                return {"rev": 0}
            db.execute("UPDATE saves SET data='', rev=rev+1, updated_at=? WHERE account_id=?", (now(), row["id"]))
            return {"rev": r["rev"] + 1}

    # ------------------------------------------------------------------ friends: this week's board and gossip
    def board(self, viewer, stalls: dict, today: dt.date) -> dict:
        """Everyone's best deal on each item this week (Monday to Sunday), from the progress the accounts keep here,
        plus who bought what lately (for the stallholders' gossip). Only approved accounts and the admin are shown;
        prices outside what the game allows are ignored."""
        self._can_save(viewer)
        week = (today - dt.timedelta(days=today.weekday())).isoformat()
        recent = (today - dt.timedelta(days=2)).isoformat()
        with self._db() as db:
            rows = db.execute("SELECT a.id, a.username, s.data FROM saves s JOIN accounts a ON a.id=s.account_id "
                              "WHERE (a.status='approved' OR a.role='admin') AND s.data<>''").fetchall()
        best: dict[tuple[str, str], dict[int, dict]] = {}
        gossip: list[dict] = []
        # top hagglers: each player's best stars on each item this week (so playing one item fifty times doesn't win)
        stars: dict[int, dict] = {}
        for r in rows:
            try:
                prof = json.loads(r["data"])
                haggles = prof.get("haggles") or []
            except (ValueError, AttributeError):
                continue
            name = clean_name(prof.get("name")) or r["username"]
            for h in haggles[-500:]:
                if not isinstance(h, dict) or h.get("result") != "deal":
                    continue
                st, it, day = str(h.get("stall")), str(h.get("item")), str(h.get("day") or "")[:10]
                item = next((i for i in stalls.get(st, {}).get("items", []) if i["id"] == it), None)
                price = h.get("deal")
                if item is None or not isinstance(price, (int, float)) or not day:
                    continue
                if not item["floor"] * 0.9 - 0.01 <= price <= item["ask"] * 1.3:
                    continue
                if day >= week:
                    mine = best.setdefault((st, it), {})
                    if r["id"] not in mine or price < mine[r["id"]]["price"]:
                        mine[r["id"]] = {"name": name, "price": price, "you": r["id"] == viewer["id"]}
                    n = h.get("stars")
                    n = n if isinstance(n, int) and not isinstance(n, bool) and 0 <= n <= 3 else 0
                    p = stars.setdefault(r["id"], {"name": name, "you": r["id"] == viewer["id"], "best": {}, "deals": 0})
                    p["best"][(st, it)] = max(p["best"].get((st, it), 0), n)
                    p["deals"] += 1
                if day >= recent and r["id"] != viewer["id"]:
                    gossip.append({"stall": st, "item": it, "name": name, "day": day})
        items = []
        for s in stalls.values():
            for i in s["items"]:
                ranked = sorted(best.get((s["id"], i["id"]), {}).values(), key=lambda x: x["price"])
                if ranked:
                    you = next((x for x in ranked if x["you"]), None)
                    items.append({"stall": s["id"], "item": i["id"], "top": ranked[:3], "you": you,
                                  "players": len(ranked)})
        # the latest few per stall, newest first, one per friend
        gossip.sort(key=lambda g: g["day"], reverse=True)
        seen, latest = set(), []
        for g in gossip:
            if (g["stall"], g["name"]) not in seen and sum(x["stall"] == g["stall"] for x in latest) < 2:
                seen.add((g["stall"], g["name"]))
                latest.append(g)
        ranked = sorted(({"name": p["name"], "stars": sum(p["best"].values()), "items": len(p["best"]),
                          "deals": p["deals"], "you": p["you"]} for p in stars.values()),
                        key=lambda x: (-x["stars"], -x["items"], -x["deals"], x["name"].lower()))
        for i, x in enumerate(ranked):
            x["place"] = i + 1
        hagglers = ranked[:10] + [x for x in ranked[10:] if x["you"]]
        return {"week": week, "items": items, "gossip": latest, "hagglers": hagglers}

    # ------------------------------------------------------------------ ✨ legendary events (posted by the admin)
    def legend_events(self, today: dt.date, past_days: int = 1, ahead_days: int = 60) -> list[dict]:
        """Events still on or coming up (what every phone fetches), oldest first."""
        lo, hi = (today - dt.timedelta(days=past_days)).isoformat(), (today + dt.timedelta(days=ahead_days)).isoformat()
        with self._db() as db:
            rows = db.execute("SELECT * FROM legend_events WHERE day_to>=? AND day_from<=? ORDER BY day_from, id",
                              (lo, hi)).fetchall()
        return [{"id": r["id"], "stall": r["stall"], "from": r["day_from"], "to": r["day_to"],
                 "item": json.loads(r["item"])} for r in rows]

    def legend_create(self, body: dict, stalls: dict, today: dt.date) -> dict:
        ev = clean_legend(body, stalls, today)
        with self._db() as db:
            clash = db.execute("SELECT id FROM legend_events WHERE day_from<=? AND day_to>=?",
                               (ev["to"], ev["from"])).fetchone()
            if clash is not None:
                raise AccountError(409, "Another legendary event is already on those days.")
            cur = db.execute("INSERT INTO legend_events (stall, day_from, day_to, item, created_at) VALUES (?,?,?,?,?)",
                             (ev["stall"], ev["from"], ev["to"], json.dumps(ev["item"]), now()))
            return {**ev, "id": cur.lastrowid}

    def legend_delete(self, event_id: int) -> dict:
        with self._db() as db:
            if db.execute("DELETE FROM legend_events WHERE id=?", (event_id,)).rowcount == 0:
                raise AccountError(404, "No such event.")
        return {"ok": True}

    # ------------------------------------------------------------------ admin
    def stats(self, stalls: dict, today: dt.date) -> dict:
        """How the market's players play, for the admin: who keeps playing and where people stop, how each stall
        goes. Counts only, from the progress the accounts keep here (players without an account aren't seen)."""
        week_ago = (today - dt.timedelta(days=7)).isoformat()
        with self._db() as db:
            accs = db.execute("SELECT a.id, a.status, a.created_at, a.last_used, s.data FROM accounts a "
                              "LEFT JOIN saves s ON s.account_id=a.id WHERE a.role<>'admin'").fetchall()

        def num(x):
            return x if isinstance(x, (int, float)) and not isinstance(x, bool) else 0

        players = {"approved": 0, "pending": 0, "new_7d": 0, "active_7d": 0}
        reach = {"1": 0, "3": 0, "10": 0, "30": 0, "days_2": 0, "days_7": 0}
        stopped = {"after_1": 0, "after_2_3": 0, "after_4_10": 0, "after_11": 0}
        stopped_last = {}
        first = {}
        first_bad_gone = 0
        style = {"haggles": 0, "typed": 0, "tapped": 0, "together": 0, "hard": 0}
        per = {sid: {"name": s.get("name", sid), "haggles": 0, "deals": 0, "walked": 0, "refused": 0, "stars": 0,
                     "moves": 0} for sid, s in stalls.items()}
        for a in accs:
            if a["status"] in players:
                players[a["status"]] += 1
            if str(a["created_at"] or "")[:10] >= week_ago:
                players["new_7d"] += 1
            try:
                prof = json.loads(a["data"] or "{}")
                hs = [h for h in (prof.get("haggles") or []) if isinstance(h, dict)]
            except (ValueError, AttributeError, TypeError):
                hs = []
            days = {str(h.get("day") or "")[:10] for h in hs} - {""}
            last = max(days) if days else ""
            if last >= week_ago:
                players["active_7d"] += 1
            n = len(hs)
            for k in ("1", "3", "10", "30"):
                reach[k] += n >= int(k)
            reach["days_2"] += len(days) >= 2
            reach["days_7"] += len(days) >= 7
            if not hs:
                continue
            res0 = str(hs[0].get("result") or "other")
            first[res0] = first.get(res0, 0) + 1
            if res0 != "deal" and n == 1 and last < week_ago:
                first_bad_gone += 1
            if last < week_ago:   # not seen for a week: how far they got
                stopped["after_1" if n == 1 else "after_2_3" if n <= 3 else "after_4_10" if n <= 10 else "after_11"] += 1
                r = str(hs[-1].get("result") or "other")
                stopped_last[r] = stopped_last.get(r, 0) + 1
            for h in hs:
                style["haggles"] += 1
                style["typed"] += int(num(h.get("typed")))
                style["tapped"] += int(num(h.get("tapped")))
                style["together"] += h.get("coop") is True
                style["hard"] += h.get("hard") is True
                st = per.get(str(h.get("stall")))
                if st is None:
                    continue
                st["haggles"] += 1
                r = h.get("result")
                if r == "deal":
                    st["deals"] += 1
                    st["stars"] += min(3, max(0, int(num(h.get("stars")))))
                elif r in ("walked", "refused"):
                    st[r] += 1
                st["moves"] += min(99, max(0, int(num(h.get("moves")))))
        return {"day": today.isoformat(), "players": players, "reach": reach, "stopped": stopped,
                "stopped_last": stopped_last, "first": first, "first_bad_gone": first_bad_gone, "style": style,
                "stalls": [{"id": sid, **v} for sid, v in per.items()], "ai_today": self.calls_today()}

    def list(self) -> list[dict]:
        day = dt.date.today().isoformat()
        with self._db() as db:
            rows = db.execute("SELECT a.*, COALESCE(c.n,0) AS today FROM accounts a "
                              "LEFT JOIN ai_calls c ON c.account_id=a.id AND c.day=? WHERE a.role<>'admin' "
                              "ORDER BY CASE a.status WHEN 'pending' THEN 0 WHEN 'approved' THEN 1 ELSE 2 END, a.id DESC",
                              (day,)).fetchall()
        return [{"id": r["id"], "username": r["username"], "status": r["status"], "created_at": r["created_at"],
                 "last_used": r["last_used"], "ai_today": r["today"]} for r in rows]

    def decide(self, account_id: int, action: str) -> dict:
        """approve / reject / remove (cuts off at once: logs the account out everywhere) / reset (new password) /
        delete (erases the account and everything kept for it). The admin account can't be changed here."""
        with self._db() as db:
            row = db.execute("SELECT * FROM accounts WHERE id=? AND role<>'admin'", (account_id,)).fetchone()
            if row is None:
                raise AccountError(404, "No such player.")
            if action == "delete":
                # gone for good: the account, its logins, progress and AI counts; the username is free again
                for table in ("logins", "saves", "ai_calls"):
                    db.execute(f"DELETE FROM {table} WHERE account_id=?", (account_id,))
                db.execute("DELETE FROM accounts WHERE id=?", (account_id,))
                return {"status": "deleted"}
            if action == "reset":
                pw = "-".join(secrets.token_hex(2) for _ in range(3))
                db.execute("UPDATE accounts SET pw=? WHERE id=?", (hash_pw(pw), account_id))
                db.execute("DELETE FROM logins WHERE account_id=?", (account_id,))
                return {"password": pw}
            status = {"approve": "approved", "reject": "rejected", "remove": "removed"}.get(action)
            if status is None:
                raise AccountError(400, "Unknown action.")
            db.execute("UPDATE accounts SET status=?, decided_at=? WHERE id=?", (status, now(), account_id))
            if status == "removed":
                db.execute("DELETE FROM logins WHERE account_id=?", (account_id,))
            return {"status": status}


# ------------------------------------------------------------------ ✨ checking a legendary event
_PLAIN = re.compile(r"^[^\W_]?[\w '’\-,&().!:;/]+$")
_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _text(x, lo: int, hi: int, what: str) -> str:
    if not isinstance(x, str) or not lo <= len(x.strip()) <= hi:
        raise AccountError(400, f"{what}: {lo} to {hi} characters.")
    x = x.strip()
    low = x.lower()
    if not _PLAIN.match(x) or "_" in x or "http" in low or "www." in low:
        raise AccountError(400, f"{what}: plain words only (letters, numbers, spaces and . , ' - & ( ) ! : ; /).")
    return x


def clean_legend(body: dict, stalls: dict, today: dt.date) -> dict:
    """An event the admin wants to post, checked the same way the app checks it (its facts go to the AI): a real
    stall, at most 7 days from today on, prices with as little room as a legendary item, plain short text."""
    if not isinstance(body, dict):
        raise AccountError(400, "Bad event.")
    stall = body.get("stall")
    if stall not in stalls:
        raise AccountError(400, "Pick one of the market's stalls.")
    d_from, d_to = str(body.get("from", "")), str(body.get("to", ""))
    try:
        if not (_DATE.match(d_from) and _DATE.match(d_to)):
            raise ValueError
        f, t = dt.date.fromisoformat(d_from), dt.date.fromisoformat(d_to)
    except ValueError:
        raise AccountError(400, "Dates as YYYY-MM-DD.")
    if f < today or t < f or (t - f).days > 6 or (f - today).days > 60:
        raise AccountError(400, "From today on, at most 7 days long, within the next 60 days.")
    name = _text(body.get("name"), 3, 50, "Name")
    emoji = body.get("emoji")
    if not isinstance(emoji, str) or not 1 <= len(emoji) <= 8 or any(ord(c) < 128 for c in emoji):
        raise AccountError(400, "One emoji, please.")
    nums = {}
    for k in ("fair", "ask", "floor"):
        v = body.get(k)
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            raise AccountError(400, "Prices must be numbers.")
        nums[k] = round(float(v), 2)
    fair, ask, floor = nums["fair"], nums["ask"], nums["floor"]
    if not (0.5 <= floor < fair < ask <= 2000):
        raise AccountError(400, "Lowest price < fair price < asking price (at most $2000).")
    if not 0.55 <= floor / ask <= 0.95:
        raise AccountError(400, "A legendary item has little room: the lowest price must be 55% to 95% of the asking price.")
    facts = body.get("facts")
    if not isinstance(facts, list) or not 1 <= len(facts) <= 5:
        raise AccountError(400, "One to five facts.")
    facts = [_text(x, 3, 140, "Each fact") for x in facts]
    return {"stall": stall, "from": d_from, "to": d_to,
            "item": {"name": name, "emoji": emoji, "fair": fair, "ask": ask, "floor": floor, "facts": facts}}

