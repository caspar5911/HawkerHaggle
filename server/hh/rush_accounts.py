"""🏪 Hawker Rush accounts: Caspar's Arcade players keep their Hawker Rush progress on any phone.

Separate from Hawker Haggle's accounts in every way: their own usernames, passwords and logins, in their own tables
(in the arcade database), and no admin to wait for. Only the password hashing (scrypt) is shared code.

A player signs up with a username and a password, and gets a login token for that phone. Progress is one JSON object
with a revision number: a phone saving from an older copy than the server's is told so (409) and takes the newer one.
Wrong passwords are slowed down per username; sign-ups are capped per day. Players can delete their account.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import re
import secrets
import sqlite3
import time
from pathlib import Path

from .accounts import _DUMMY, check_pw, hash_pw

USERNAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{2,19}")
PW_MIN, PW_MAX = 6, 128
SAVE_MAX = 64 * 1024            # one player's progress (a long-played one is a few KB)
SIGNUPS_PER_DAY = 500
LOGINS_KEPT = 10                # phones logged in at once, per account (the oldest is logged out)
FAILS_BEFORE_LOCK, LOCK_SECONDS = 5, 15 * 60

SCHEMA = """
CREATE TABLE IF NOT EXISTS rush_accounts (id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL COLLATE NOCASE, pw TEXT NOT NULL, created_at TEXT NOT NULL, last_used TEXT);
CREATE TABLE IF NOT EXISTS rush_logins (token_hash TEXT PRIMARY KEY, account_id INTEGER NOT NULL, created_at TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS rush_logins_account ON rush_logins (account_id);
CREATE TABLE IF NOT EXISTS rush_progress (account_id INTEGER PRIMARY KEY, data TEXT NOT NULL, rev INTEGER NOT NULL,
    updated_at TEXT NOT NULL);
"""


class RushAccountError(Exception):
    def __init__(self, code: int, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def _now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def _tok(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class RushAccounts:
    def __init__(self, path: str | Path, clock=time.monotonic):
        self.path = str(path)
        self.clock = clock
        self.fails: dict[str, list[float]] = {}
        Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        with self._db() as db:
            db.executescript(SCHEMA)

    def _db(self) -> sqlite3.Connection:
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        return db

    # ------------------------------------------------------------------ signing up and in
    @staticmethod
    def _check_pw_rules(pw) -> None:
        if not isinstance(pw, str) or not PW_MIN <= len(pw) <= PW_MAX:
            raise RushAccountError(400, f"Password: at least {PW_MIN} characters.")

    def signup(self, username, pw) -> dict:
        username = username.strip() if isinstance(username, str) else ""
        if not USERNAME.fullmatch(username):
            raise RushAccountError(400, "Username: 3 to 20 letters or numbers (. _ - allowed), starting with a letter or number.")
        self._check_pw_rules(pw)
        with self._db() as db:
            today = _now()[:10]
            if db.execute("SELECT COUNT(*) FROM rush_accounts WHERE created_at LIKE ?", (today + "%",)).fetchone()[0] >= SIGNUPS_PER_DAY:
                raise RushAccountError(429, "Lots of sign-ups today. Try again tomorrow.")
            try:
                cur = db.execute("INSERT INTO rush_accounts (username, pw, created_at) VALUES (?, ?, ?)",
                                 (username, hash_pw(pw), _now()))
            except sqlite3.IntegrityError:
                raise RushAccountError(409, "That username is taken. Try another one.")
            return self._new_login(db, cur.lastrowid)

    def login(self, username, pw) -> dict:
        name = username.strip().lower() if isinstance(username, str) else ""
        t = self.clock()
        recent = [x for x in self.fails.get(name, []) if t - x < LOCK_SECONDS]
        self.fails[name] = recent
        if len(recent) >= FAILS_BEFORE_LOCK:
            raise RushAccountError(429, "Too many wrong passwords. Wait 15 minutes and try again.")
        with self._db() as db:
            row = db.execute("SELECT * FROM rush_accounts WHERE username = ?", (name,)).fetchone()
            ok = check_pw(pw if isinstance(pw, str) else "", row["pw"] if row else _DUMMY) and row is not None
            if not ok:
                self.fails[name].append(t)
                raise RushAccountError(401, "Wrong username or password.")
            self.fails.pop(name, None)
            return self._new_login(db, row["id"])

    def _new_login(self, db, account_id: int) -> dict:
        token = "hr_" + secrets.token_urlsafe(32)
        db.execute("INSERT INTO rush_logins (token_hash, account_id, created_at) VALUES (?, ?, ?)", (_tok(token), account_id, _now()))
        # (keep the newest few phones logged in)
        db.execute("DELETE FROM rush_logins WHERE account_id = ? AND token_hash NOT IN (SELECT token_hash FROM rush_logins "
                   "WHERE account_id = ? ORDER BY created_at DESC, rowid DESC LIMIT ?)", (account_id, account_id, LOGINS_KEPT))
        db.execute("UPDATE rush_accounts SET last_used = ? WHERE id = ?", (_now(), account_id))
        row = db.execute("SELECT username FROM rush_accounts WHERE id = ?", (account_id,)).fetchone()
        return {"token": token, "username": row["username"]}

    def who(self, token) -> sqlite3.Row:
        if not isinstance(token, str) or not token.startswith("hr_") or len(token) > 100:
            raise RushAccountError(401, "Please log in again.")
        with self._db() as db:
            row = db.execute("SELECT a.* FROM rush_logins l JOIN rush_accounts a ON a.id = l.account_id WHERE l.token_hash = ?",
                             (_tok(token),)).fetchone()
        if row is None:
            raise RushAccountError(401, "Please log in again.")
        return row

    def me(self, token) -> dict:
        return {"username": self.who(token)["username"]}

    def logout(self, token) -> dict:
        if isinstance(token, str):
            with self._db() as db:
                db.execute("DELETE FROM rush_logins WHERE token_hash = ?", (_tok(token),))
        return {"ok": True}

    def change_password(self, token, old, new) -> dict:
        row = self.who(token)
        if not check_pw(old if isinstance(old, str) else "", row["pw"]):
            raise RushAccountError(401, "Your current password isn't right.")
        self._check_pw_rules(new)
        with self._db() as db:
            db.execute("UPDATE rush_accounts SET pw = ? WHERE id = ?", (hash_pw(new), row["id"]))
            # (every other phone is logged out; this one stays in)
            db.execute("DELETE FROM rush_logins WHERE account_id = ? AND token_hash <> ?", (row["id"], _tok(token)))
        return {"ok": True}

    def delete(self, token, pw) -> dict:
        """Delete the account and its progress (the password again, to be sure)."""
        row = self.who(token)
        if not check_pw(pw if isinstance(pw, str) else "", row["pw"]):
            raise RushAccountError(401, "That password isn't right.")
        with self._db() as db:
            for table in ("rush_progress", "rush_logins"):
                db.execute(f"DELETE FROM {table} WHERE account_id = ?", (row["id"],))
            db.execute("DELETE FROM rush_accounts WHERE id = ?", (row["id"],))
        return {"ok": True}

    # ------------------------------------------------------------------ 👑 the owner's admin (only from the owner's login)
    def list(self) -> list[dict]:
        """Every account, newest first, with a glance at its progress."""
        with self._db() as db:
            rows = db.execute("SELECT a.username, a.created_at, a.last_used, p.data, p.updated_at FROM rush_accounts a "
                              "LEFT JOIN rush_progress p ON p.account_id = a.id ORDER BY a.id DESC").fetchall()
        out = []
        for r in rows:
            glance = {}
            try:
                if not r["data"]:
                    raise ValueError  # (nothing saved yet)
                data = json.loads(r["data"])
                xp = data.get("xp") if isinstance(data.get("xp"), int) else 0
                glance = {"day": data.get("day") if isinstance(data.get("day"), int) else 1,
                          "wallet": data.get("wallet") if isinstance(data.get("wallet"), (int, float)) else 0,
                          "level": max(1, int((1 + (1 + 4 * max(0, xp) / 15) ** .5) / 2))}
            except (ValueError, TypeError, AttributeError):
                pass
            out.append({"username": r["username"], "created": r["created_at"], "last_used": r["last_used"],
                        "saved": r["updated_at"], **glance})
        return out

    def _account(self, db, username):
        row = db.execute("SELECT id, username FROM rush_accounts WHERE username = ?",
                         (username.strip() if isinstance(username, str) else "",)).fetchone()
        if row is None:
            raise RushAccountError(404, "No account with that username.")
        return row

    def reset_password(self, username) -> dict:
        """A new temporary password for a player who forgot theirs (every phone of theirs is logged out)."""
        temp = "-".join("".join(secrets.choice("abcdefghjkmnpqrstuvwxyz23456789") for _ in range(4)) for _ in range(3))
        with self._db() as db:
            row = self._account(db, username)
            db.execute("UPDATE rush_accounts SET pw = ? WHERE id = ?", (hash_pw(temp), row["id"]))
            db.execute("DELETE FROM rush_logins WHERE account_id = ?", (row["id"],))
        self.fails.pop(row["username"].lower(), None)
        return {"username": row["username"], "password": temp}

    def remove(self, username) -> dict:
        with self._db() as db:
            row = self._account(db, username)
            for table in ("rush_progress", "rush_logins"):
                db.execute(f"DELETE FROM {table} WHERE account_id = ?", (row["id"],))
            db.execute("DELETE FROM rush_accounts WHERE id = ?", (row["id"],))
        return {"ok": True, "username": row["username"]}

    # ------------------------------------------------------------------ progress
    def load(self, token) -> dict:
        row = self.who(token)
        with self._db() as db:
            r = db.execute("SELECT data, rev FROM rush_progress WHERE account_id = ?", (row["id"],)).fetchone()
        return {"data": r["data"], "rev": r["rev"]} if r else {"data": None, "rev": 0}

    def save(self, token, data, rev) -> dict:
        """rev: the copy this phone started from. If another phone saved since, refuse (409): this phone takes the newer one."""
        row = self.who(token)
        if not isinstance(data, str) or len(data.encode()) > SAVE_MAX:
            raise RushAccountError(413, "That progress is too big to keep.")
        try:
            if not isinstance(json.loads(data), dict):
                raise ValueError
        except (ValueError, RecursionError):
            raise RushAccountError(400, "Bad progress.")
        if type(rev) is not int or rev < 0:
            raise RushAccountError(400, "Bad progress.")
        with self._db() as db:
            r = db.execute("SELECT rev FROM rush_progress WHERE account_id = ?", (row["id"],)).fetchone()
            current = r["rev"] if r else 0
            if rev != current:
                raise RushAccountError(409, "Newer progress was saved from another phone.")
            db.execute("INSERT INTO rush_progress (account_id, data, rev, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(account_id) "
                       "DO UPDATE SET data = excluded.data, rev = excluded.rev, updated_at = excluded.updated_at",
                       (row["id"], data, current + 1, _now()))
        return {"rev": current + 1}
