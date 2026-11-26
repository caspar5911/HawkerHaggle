"""Nightly backup of the market server's data: player accounts and their saved progress (accounts.db), and the game
store (hh.db). Each is copied with SQLite's online backup, safe while the server runs, then checked and kept for
KEEP_DAYS days in every destination folder.

Run: python -m hh.backup DEST [DEST...]   (or set HH_BACKUP_DIRS=dir1:dir2)
The copies hold password hashes and login-token hashes (never plain passwords), so they are made readable by the
owner only. Keep the destinations private.
"""
from __future__ import annotations

import datetime as dt
import os
import re
import sqlite3
import sys
from pathlib import Path

VAR = Path(__file__).resolve().parent.parent / "var"
DATABASES = ("accounts.db", "hh.db")
KEEP_DAYS = 14
NAME = re.compile(r"^hawker-haggle-(\d{4}-\d{2}-\d{2})-(.+\.db)$")


def backup(dest: Path, var: Path = VAR, today: dt.date | None = None, keep_days: int = KEEP_DAYS) -> list[Path]:
    """Copies each database into [dest] as hawker-haggle-YYYY-MM-DD-<name>, checks it, and removes copies older
    than [keep_days]. Returns the new copies."""
    today = today or dt.date.today()
    dest.mkdir(parents=True, exist_ok=True)
    try:
        dest.chmod(0o700)
    except OSError:
        pass  # a Windows folder (/mnt/c) ignores this; Windows keeps the user's own folders private
    made = []
    for name in DATABASES:
        src = var / name
        if not src.exists():
            continue
        out = dest / f"hawker-haggle-{today.isoformat()}-{name}"
        tmp = out.with_suffix(".db.part")
        tmp.unlink(missing_ok=True)
        s, d = sqlite3.connect(f"file:{src}?mode=ro", uri=True), sqlite3.connect(tmp)
        try:
            s.backup(d)
            d.execute("PRAGMA journal_mode=DELETE")   # one self-contained file (the live one uses WAL)
            ok = d.execute("PRAGMA integrity_check").fetchone()[0]
        finally:
            s.close()
            d.close()
        for side in ("-wal", "-shm"):
            Path(f"{tmp}{side}").unlink(missing_ok=True)
        if ok != "ok":
            tmp.unlink(missing_ok=True)
            raise RuntimeError(f"backup of {name} failed its check: {ok}")
        os.chmod(tmp, 0o600)
        tmp.replace(out)
        made.append(out)
    oldest = today - dt.timedelta(days=keep_days - 1)
    for f in dest.iterdir():
        if f.name.startswith("hawker-haggle-") and f.name.endswith((".part-wal", ".part-shm")):
            f.unlink()   # side files left by the first version of this script
            continue
        m = NAME.match(f.name)
        if m and dt.date.fromisoformat(m.group(1)) < oldest:
            f.unlink()
    return made


def main(argv: list[str]) -> int:
    dirs = argv or [d for d in os.environ.get("HH_BACKUP_DIRS", "").split(":") if d]
    if not dirs:
        print("Give a destination folder (or set HH_BACKUP_DIRS).", file=sys.stderr)
        return 2
    failed = 0
    for d in dirs:
        try:
            made = backup(Path(d).expanduser())
            print(f"{d}: {', '.join(p.name for p in made) or 'nothing to back up'}")
        except Exception as e:  # one destination failing (say, the Windows drive) never stops the others
            failed += 1
            print(f"{d}: FAILED {e}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
