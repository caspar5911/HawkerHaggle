"""🏪 Hawker Rush accounts: their own usernames, passwords and logins (separate from Hawker Haggle's), and progress."""
import json

from fastapi.testclient import TestClient
import pytest

from hh import rush_accounts as rush_accounts_module
from hh.accounts import Accounts
from hh.ai import AI
from hh.api import create_app
from hh.arcade import Arcade
from hh.rush_accounts import RushAccounts, RushAccountError
from hh.store import Store

ORIGIN = {"Origin": "https://caspar5911.github.io"}
ACCOUNT = "/ai/arcade/hawker-rush/account/"
LOAD, SAVE = "/ai/arcade/hawker-rush/progress", "/ai/arcade/hawker-rush/progress/save"


@pytest.fixture
def setup(tmp_path):
    hh_accounts = Accounts(tmp_path / "accounts.db")
    arcade = Arcade(tmp_path / "arcade.db", secret=b"k" * 32)
    with TestClient(create_app(Store(":memory:"), AI(base_url=""), hh_accounts, arcade=arcade, gate=True)) as c:
        yield c, hh_accounts, arcade


def post(client, path, body=None, token=None, status=200):
    headers = {**ORIGIN, **({"Authorization": "Bearer " + token} if token else {})}
    r = client.post(path, json=body or {}, headers=headers)
    assert r.status_code == status, r.text
    return r.json()


def test_a_player_signs_up_through_the_public_gateway_and_keeps_progress_on_any_phone(setup):
    client, _, _ = setup
    me = post(client, ACCOUNT + "signup", {"username": "MeiLing", "password": "kopi-o-kosong"})
    assert me["username"] == "MeiLing" and me["token"].startswith("hr_")
    assert post(client, ACCOUNT + "me", token=me["token"]) == {"username": "MeiLing"}
    assert post(client, LOAD, token=me["token"]) == {"data": None, "rev": 0}
    save = json.dumps({"version": 2, "day": 7, "wallet": 120.5})
    assert post(client, SAVE, {"data": save, "rev": 0}, me["token"]) == {"rev": 1}
    # another phone logs in (any capitals) and gets the same progress
    other = post(client, ACCOUNT + "login", {"username": "meiling", "password": "kopi-o-kosong"})
    assert post(client, LOAD, token=other["token"]) == {"data": save, "rev": 1}
    # a phone saving from an older copy is told a newer one exists
    post(client, SAVE, {"data": save, "rev": 0}, other["token"], status=409)
    assert post(client, SAVE, {"data": save, "rev": 1}, other["token"]) == {"rev": 2}
    post(client, ACCOUNT + "logout", token=other["token"])
    post(client, LOAD, token=other["token"], status=401)
    assert post(client, LOAD, token=me["token"])["rev"] == 2          # (the first phone is still in)


def test_completely_separate_from_hawker_haggle_accounts(setup):
    client, hh_accounts, _ = setup
    post(client, "/ai/accounts/signup", {"username": "Siti", "password": "password1"})       # (a Hawker Haggle account)
    post(client, ACCOUNT + "login", {"username": "Siti", "password": "password1"}, status=401)  # (not a Hawker Rush one)
    rush = post(client, ACCOUNT + "signup", {"username": "siti", "password": "another-pw"})   # (the name is free here)
    post(client, "/ai/accounts/progress", token=rush["token"], status=401)                   # (no Hawker Haggle access)
    assert [p["username"] for p in hh_accounts.list() if p["username"] != "admin"] == ["Siti"]  # (the admin list is unchanged)
    post(client, ACCOUNT + "signup", {"username": "SITI", "password": "password2"}, status=409)


@pytest.mark.parametrize("body", [{"username": "x", "password": "password1"}, {"username": "ok_name", "password": "123"},
                                  {"username": "has space", "password": "password1"}, {"username": 5, "password": "password1"},
                                  {"username": "fine.name", "password": ["no"]}])
def test_bad_sign_ups_are_refused(setup, body):
    post(setup[0], ACCOUNT + "signup", body, status=400)


def test_progress_is_checked(setup):
    client, _, _ = setup
    token = post(client, ACCOUNT + "signup", {"username": "Ahmad", "password": "teh-tarik"})["token"]
    post(client, LOAD, status=401)
    post(client, LOAD, token="hr_not-a-real-token", status=401)
    post(client, SAVE, {"data": "[1, 2]", "rev": 0}, token, status=400)                     # (progress is an object)
    post(client, SAVE, {"data": "{}", "rev": "0"}, token, status=400)
    post(client, SAVE, {"data": "{not json", "rev": 0}, token, status=400)
    post(client, SAVE, {"data": json.dumps({"x": "y" * 70000}), "rev": 0}, token, status=413)


def test_passwords_logins_and_deleting(setup):
    client, _, arcade = setup
    a = post(client, ACCOUNT + "signup", {"username": "Boon", "password": "first-pw"})
    b = post(client, ACCOUNT + "login", {"username": "boon", "password": "first-pw"})
    post(client, ACCOUNT + "password", {"old": "wrong", "new": "second-pw"}, a["token"], status=401)
    post(client, ACCOUNT + "password", {"old": "first-pw", "new": "second-pw"}, a["token"])
    post(client, ACCOUNT + "me", token=b["token"], status=401)                               # (other phones logged out)
    post(client, ACCOUNT + "login", {"username": "boon", "password": "first-pw"}, status=401)
    post(client, SAVE, {"data": "{}", "rev": 0}, a["token"])
    post(client, ACCOUNT + "delete", {"password": "nope"}, a["token"], status=401)
    post(client, ACCOUNT + "delete", {"password": "second-pw"}, a["token"])
    post(client, ACCOUNT + "login", {"username": "boon", "password": "second-pw"}, status=401)
    import sqlite3
    with sqlite3.connect(arcade.path) as db:
        assert db.execute("SELECT COUNT(*) FROM rush_progress").fetchone()[0] == 0


def test_wrong_passwords_lock_a_name_for_a_while_and_sign_ups_are_capped(tmp_path, monkeypatch):
    t = [0.0]
    accts = RushAccounts(tmp_path / "a.db", clock=lambda: t[0])
    accts.signup("Lily", "right-pw")
    for _ in range(5):
        with pytest.raises(RushAccountError):
            accts.login("lily", "wrong")
    with pytest.raises(RushAccountError) as err:
        accts.login("lily", "right-pw")
    assert err.value.code == 429
    t[0] += 16 * 60
    assert accts.login("lily", "right-pw")["username"] == "Lily"
    monkeypatch.setattr(rush_accounts_module, "SIGNUPS_PER_DAY", 2)
    accts.signup("Two2", "password")
    with pytest.raises(RushAccountError) as err:
        accts.signup("Three3", "password")
    assert err.value.code == 429


def test_only_the_newest_ten_phones_stay_logged_in(tmp_path):
    accts = RushAccounts(tmp_path / "a.db")
    tokens = [accts.signup("Rajan", "password")["token"]] + [accts.login("rajan", "password")["token"] for _ in range(11)]
    with pytest.raises(RushAccountError):
        accts.me(tokens[0])
    assert accts.me(tokens[-1]) == {"username": "Rajan"}
