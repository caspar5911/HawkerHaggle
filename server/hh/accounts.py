"""Player accounts for people who play through a public address (a friend's domain) instead of Tailscale.

Anyone can sign up; an account can use the AI only after the admin approves it. Passwords are kept as scrypt hashes
(never readable), sessions as SHA-256 hashes of random tokens. The admin account starts as admin/admin and can only
log in over Tailscale (the API refuses it from the public gateway), so the default password is never exposed to the
internet; the admin screen nags until it is changed. Every account can change its own password.
"""
from __future__ import annotations

import contextlib
import datetime as dt
import hashlib
import hmac
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
"""

ADMIN = "admin"
STATUSES = ("pending", "approved", "rejected", "removed")
USERNAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{2,19}")
PW_MIN, PW_MAX = 4, 128      # 4 so the admin's own "admin" fits; the screens suggest 8+
MAX_PENDING = 50             # sign-ups stop while this many wait for the admin
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

    def login(self, username: str, pw: str, *, admin_allowed: bool) -> dict:
        """admin_allowed is False for requests from the public gateway: the admin account then simply doesn't
        exist (same answer as a wrong password)."""
        name = (username or "").strip().lower()
        key = ("tailnet:" if admin_allowed else "public:") + name   # public spam can't lock anyone out over Tailscale
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

    # ------------------------------------------------------------------ admin
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
        """approve / reject / remove (cuts off at once: logs the account out everywhere) / reset (new password)."""
        with self._db() as db:
            row = db.execute("SELECT * FROM accounts WHERE id=? AND role<>'admin'", (account_id,)).fetchone()
            if row is None:
                raise AccountError(404, "No such player.")
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
