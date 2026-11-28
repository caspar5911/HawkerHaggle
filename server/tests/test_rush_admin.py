"""👑 The owner's Hawker Rush admin: only from the owner's own Tailscale login; to anyone else it doesn't exist."""
import json
import sqlite3

from fastapi.testclient import TestClient
import pytest

from hh.accounts import Accounts
from hh.ai import AI
from hh.api import create_app
from hh.arcade import Arcade
from hh.hawker_rush import period_for
from hh.store import Store

OWNER = {"Tailscale-User-Login": "owner@example.com"}
FRIEND = {"Tailscale-User-Login": "friend@example.com"}
PUBLIC = {"Origin": "https://caspar5911.github.io"}          # (the public gateway: no Tailscale login)
ADMIN = "/ai/arcade/hawker-rush/admin"


@pytest.fixture
def setup(tmp_path):
    arcade = Arcade(tmp_path / "arcade.db", secret=b"k" * 32)
    app = create_app(Store(":memory:"), AI(base_url=""), Accounts(tmp_path / "accounts.db"), arcade=arcade, gate=True,
                     admin_logins={"owner@example.com"}, gateway_logins=set())
    with TestClient(app) as c:
        yield c, arcade


def signup(client, name, pw="first-pw"):
    return client.post("/ai/arcade/hawker-rush/account/signup", json={"username": name, "password": pw}, headers=PUBLIC).json()


@pytest.mark.parametrize("headers", [PUBLIC, FRIEND, {}])
def test_nobody_else_can_open_it(setup, headers):
    client, _ = setup
    assert client.get(ADMIN, headers=headers).status_code == 404
    for what in ("overview", "reset", "remove", "unlist"):
        assert client.post(f"{ADMIN}/{what}", json={"username": "x"}, headers=headers).status_code == 404


def test_the_owner_sees_players_stats_and_boards(setup):
    client, arcade = setup
    page = client.get(ADMIN, headers=OWNER)
    assert page.status_code == 200 and "Hawker Rush · Owner" in page.text and page.headers["cache-control"] == "no-store"
    me = signup(client, "MeiLing")
    client.post("/ai/arcade/hawker-rush/progress/save", json={"data": json.dumps({"day": 6, "wallet": 88.5, "xp": 95}), "rev": 0},
                headers={**PUBLIC, "Authorization": "Bearer " + me["token"]})
    signup(client, "Boon")
    out = client.post(f"{ADMIN}/overview", json={}, headers=OWNER).json()
    assert [a["username"] for a in out["accounts"]] == ["Boon", "MeiLing"]
    assert {k: out["accounts"][1][k] for k in ("day", "wallet", "level")} == {"day": 6, "wallet": 88.5, "level": 3}
    assert set(out["stats"]) >= {"players", "came_back", "story_days", "furthest_day"} and set(out["boards"]) == {"daily", "speed"}


def test_reset_a_forgotten_password(setup):
    client, _ = setup
    me = signup(client, "Ahmad")
    r = client.post(f"{ADMIN}/reset", json={"username": "ahmad"}, headers=OWNER).json()
    assert r["username"] == "Ahmad" and len(r["password"]) == 14
    auth = {**PUBLIC, "Authorization": "Bearer " + me["token"]}
    assert client.post("/ai/arcade/hawker-rush/account/me", json={}, headers=auth).status_code == 401   # (logged out)
    assert client.post("/ai/arcade/hawker-rush/account/login", json={"username": "ahmad", "password": "first-pw"}, headers=PUBLIC).status_code == 401
    assert client.post("/ai/arcade/hawker-rush/account/login", json={"username": "ahmad", "password": r["password"]}, headers=PUBLIC).status_code == 200
    assert client.post(f"{ADMIN}/reset", json={"username": "nobody"}, headers=OWNER).status_code == 404


def test_remove_an_account_and_a_board_entry(setup):
    client, arcade = setup
    signup(client, "RudeName")
    assert client.post(f"{ADMIN}/remove", json={"username": "rudename"}, headers=OWNER).json()["username"] == "RudeName"
    assert client.post("/ai/arcade/hawker-rush/account/login", json={"username": "rudename", "password": "first-pw"}, headers=PUBLIC).status_code == 401
    period = period_for("daily", arcade.clock())
    with sqlite3.connect(arcade.path) as db:
        db.execute("INSERT INTO rush_bests VALUES ('daily', ?, 'rude', 'Rude', 1234, 0)", (period,))
    boards = client.post(f"{ADMIN}/overview", json={}, headers=OWNER).json()["boards"]
    assert boards["daily"]["entries"] == [{"player": "rude", "name": "Rude", "value": 1234}]
    assert client.post(f"{ADMIN}/unlist", json={"mode": "daily", "period": period, "player": "rude"}, headers=OWNER).status_code == 200
    assert client.post(f"{ADMIN}/overview", json={}, headers=OWNER).json()["boards"]["daily"]["entries"] == []
    assert client.post(f"{ADMIN}/unlist", json={"mode": "daily", "period": period, "player": "rude"}, headers=OWNER).status_code == 400


def test_an_account_with_nothing_saved_shows_no_progress(setup):
    client, _ = setup
    signup(client, "NewKid")
    acct = client.post(f"{ADMIN}/overview", json={}, headers=OWNER).json()["accounts"][0]
    assert acct["username"] == "NewKid" and "day" not in acct
