"""The nightly backup: a checked copy of each database, private, and only the last two weeks kept."""
import datetime as dt
import sqlite3
import stat

from hh import backup as b


def _db(path, rows):
    with sqlite3.connect(path) as db:
        db.execute("PRAGMA journal_mode=WAL")   # like the live databases
        db.execute("CREATE TABLE t (x TEXT)")
        db.executemany("INSERT INTO t VALUES (?)", [(r,) for r in rows])


def test_copies_each_database_checked_and_private(tmp_path):
    var, dest = tmp_path / "var", tmp_path / "backups"
    var.mkdir()
    _db(var / "accounts.db", ["arella", "kaze"])
    _db(var / "hh.db", ["x"])
    live = sqlite3.connect(var / "accounts.db")   # the server holds it open while the backup runs
    made = b.backup(dest, var=var, today=dt.date(2026, 11, 26))
    live.close()
    assert sorted(p.name for p in made) == ["hawker-haggle-2026-11-26-accounts.db", "hawker-haggle-2026-11-26-hh.db"]
    with sqlite3.connect(made[0]) as db:
        assert [r[0] for r in db.execute("SELECT x FROM t")] == ["arella", "kaze"]
    assert stat.S_IMODE(made[0].stat().st_mode) == 0o600
    assert stat.S_IMODE(dest.stat().st_mode) == 0o700
    assert sorted(p.name for p in dest.iterdir()) == sorted(p.name for p in made)   # no side files
    with sqlite3.connect(made[0]) as db:
        assert db.execute("PRAGMA journal_mode").fetchone()[0] == "delete"


def test_keeps_two_weeks_and_leaves_other_files_alone(tmp_path):
    var, dest = tmp_path / "var", tmp_path / "backups"
    var.mkdir()
    _db(var / "accounts.db", ["a"])
    dest.mkdir()
    for day in ("2026-11-01", "2026-11-12", "2026-11-13", "2026-11-25"):
        (dest / f"hawker-haggle-{day}-accounts.db").write_text("old")
    (dest / "notes.txt").write_text("mine")
    (dest / "hawker-haggle-2026-11-25-accounts.db.part-wal").write_text("")   # left by the first version
    b.backup(dest, var=var, today=dt.date(2026, 11, 26))
    left = sorted(p.name for p in dest.iterdir())
    assert left == ["hawker-haggle-2026-11-13-accounts.db", "hawker-haggle-2026-11-25-accounts.db",
                    "hawker-haggle-2026-11-26-accounts.db", "notes.txt"]


def test_one_bad_destination_does_not_stop_the_others(tmp_path, monkeypatch):
    var = tmp_path / "var"
    var.mkdir()
    _db(var / "accounts.db", ["a"])
    monkeypatch.setattr(b, "VAR", var)
    blocked = tmp_path / "file-not-folder"
    blocked.write_text("x")
    good = tmp_path / "good"
    assert b.main([str(blocked), str(good)]) == 1
    assert list(good.glob("hawker-haggle-*-accounts.db"))
    monkeypatch.delenv("HH_BACKUP_DIRS", raising=False)
    assert b.main([]) == 2                       # no destination: says so
