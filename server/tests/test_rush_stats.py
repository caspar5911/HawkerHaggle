"""📊 Anonymous Hawker Rush play stats: strictly checked, capped, no names or addresses kept."""
import datetime as dt
import sqlite3

from fastapi.testclient import TestClient
import pytest

from hh.accounts import Accounts
from hh.ai import AI
from hh.api import create_app
from hh.arcade import Arcade
from hh.rush_stats import RushStats
from hh.store import Store

URL = "/ai/arcade/hawker-rush/stats"
ORIGIN = {"Origin": "https://caspar5911.github.io"}
PHONE = "aZ09_-aZ09_-aZ09_-xy"
SHIFT = {"id": PHONE, "event": "shift", "mode": "day", "level": 11, "stars": 2, "served": 18, "lost": 3,
         "seconds": 121, "quit": False, "players": 1, "theme": "sakura", "build": 150}
TODAY = dt.date(2026, 11, 28)


@pytest.fixture
def arcade(tmp_path):
    return Arcade(tmp_path / "arcade.db", secret=b"k" * 32)


@pytest.fixture
def client(arcade, tmp_path):
    with TestClient(create_app(Store(":memory:"), AI(base_url=""), Accounts(tmp_path / "accounts.db"),
                               arcade=arcade, gate=True)) as c:
        yield c


def rows(arcade):
    with sqlite3.connect(arcade.path) as db:
        return db.execute("SELECT * FROM rush_stats").fetchall()


def test_a_phone_sends_events_through_the_public_gateway_and_no_id_is_kept(client, arcade):
    r = client.post(URL, json=SHIFT, headers=ORIGIN)
    assert r.status_code == 200 and r.json() == {"ok": True}
    assert r.headers["access-control-allow-origin"] == ORIGIN["Origin"]
    assert client.post(URL, json={"id": PHONE, "event": "open", "level": 3, "theme": "latte", "build": 150},
                       headers=ORIGIN).status_code == 200
    saved = rows(arcade)
    assert len(saved) == 2
    assert all(PHONE not in str(row) for row in saved)        # (only a keyed hash of the id)
    assert saved[0][2] == saved[1][2]                          # (the same phone, the same hash)


@pytest.mark.parametrize("bad", [
    {**SHIFT, "id": "short"}, {**SHIFT, "id": "has spaces in it, quite a few"}, {**SHIFT, "event": "tap"},
    {**SHIFT, "stars": 4}, {**SHIFT, "quit": 1}, {**SHIFT, "mode": "battle"}, {**SHIFT, "served": -1},
    {**SHIFT, "level": True}, {**SHIFT, "theme": "<b>"}, {**SHIFT, "seconds": 99999}, {**SHIFT, "players": 5},
    ["not", "an", "object"],
])
def test_anything_else_is_refused(client, arcade, bad):
    assert client.post(URL, json=bad, headers=ORIGIN).status_code == 400
    assert rows(arcade) == []


def test_extra_fields_are_dropped_and_big_bodies_refused(client, arcade):
    assert client.post(URL, json={**SHIFT, "name": "Mei", "email": "x@y.z"}, headers=ORIGIN).status_code == 200
    assert "Mei" not in str(rows(arcade)) and "x@y.z" not in str(rows(arcade))
    assert client.post(URL, json={**SHIFT, "pad": "x" * 2000}, headers=ORIGIN).status_code == 413


def test_each_phone_is_capped_per_day_and_the_table_pruned(arcade):
    stats = RushStats(arcade, max_rows=50, per_device=5)
    for _ in range(9):
        stats.record(SHIFT, TODAY)
    assert len(rows(arcade)) == 5                              # (a phone's cap for the day)
    stats.record(SHIFT, TODAY + dt.timedelta(days=1))
    assert len(rows(arcade)) == 6                              # (a new day)
    for k in range(80):
        stats.record({**SHIFT, "id": f"phone-number-{k:06d}"}, TODAY)
    assert len(rows(arcade)) <= 50                             # (oldest pruned)


def test_the_owners_summary(arcade):
    stats = RushStats(arcade)
    stats.record(SHIFT, TODAY)
    stats.record({**SHIFT, "level": 12, "stars": 0, "quit": True}, TODAY + dt.timedelta(days=1))
    stats.record({**SHIFT, "id": "another-phone-0000", "mode": "speed", "level": 3}, TODAY)
    s = stats.summary(30, TODAY + dt.timedelta(days=2))
    assert s["players"] == 2 and s["came_back"] == 1
    assert s["furthest_day"] == {12: 1, 3: 1}
    assert [d["day"] for d in s["story_days"]] == [11, 12] and s["story_days"][1]["quit"] == 1
    assert s["modes"] == {"day": 2, "speed": 1} and s["themes"] == {"sakura": 2}
