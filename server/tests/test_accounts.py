"""Accounts for players who come in through a public address (a friend's domain) instead of Tailscale."""
import pytest
from fastapi.testclient import TestClient

from hh.accounts import Accounts
from hh.ai import AI
from hh.api import create_app
from hh.store import Store

from test_api import FakeModel

ME = {"Tailscale-User-Login": "owner@example.com"}          # a person on the owner's Tailscale (via tailscale serve)
GATEWAY = {"Tailscale-User-Login": "friend@example.com"}    # the friend's server that forwards the public domain
NOBODY = {}                                                  # a tagged device / anything without a login: public
FRIEND = {"Tailscale-User-Login": "pal@example.com"}         # a friend on the owner's Tailscale (not the owner)
CHAT = {"messages": [{"role": "user", "content": "hi"}], "model": "anything"}


@pytest.fixture
def app(tmp_path):
    model = FakeModel(line="Aiyo, welcome!")
    ai = AI(base_url="http://model/v1", model="gx10-current", session=model)
    accounts = Accounts(tmp_path / "acc.db")
    c = TestClient(create_app(Store(":memory:"), ai, accounts, gate=True, gateway_logins={"friend@example.com"},
                                admin_logins={"owner@example.com"}))
    return c, accounts, model


def bearer(token, extra=None):
    return {"Authorization": f"Bearer {token}", **(extra or {})}


def admin_token(c, pw="admin"):
    r = c.post("/ai/accounts/login", json={"username": "admin", "password": pw}, headers=ME)
    assert r.status_code == 200, r.text
    assert r.json()["admin"] is True
    return r.json()["token"]


def test_tailscale_users_need_no_account(app):
    c, _, model = app
    r = c.post("/ai/v1/chat/completions", json=CHAT, headers=ME)
    assert r.status_code == 200 and model.calls[-1]["model"] == "gx10-current"
    assert c.get("/download", headers=ME).status_code == 200


@pytest.mark.parametrize("who", [GATEWAY, NOBODY])
def test_public_requests_need_an_approved_account_for_the_ai(app, who):
    c, _, model = app
    assert c.post("/ai/v1/chat/completions", json=CHAT, headers=who).status_code == 401
    assert c.post("/ai/v1/chat/completions", json=CHAT, headers=bearer("hh_made_up", who)).status_code == 401
    r = c.post("/ai/accounts/signup", json={"username": "JingQi", "password": "kopi-o-kosong"}, headers=who)
    assert r.status_code == 200 and r.json()["status"] == "pending"
    tok = r.json()["token"]
    r = c.post("/ai/v1/chat/completions", json=CHAT, headers=bearer(tok, who))
    assert r.status_code == 403 and "waiting" in r.json()["detail"]
    assert model.calls == []
    # the admin approves over Tailscale
    adm = admin_token(c)
    players = c.post("/ai/admin/players", headers=bearer(adm, ME)).json()["players"]
    assert [p["username"] for p in players] == ["JingQi"] and players[0]["status"] == "pending"
    assert c.post("/ai/admin/decide", json={"id": players[0]["id"], "action": "approve"}, headers=bearer(adm, ME)).json() == {"status": "approved"}
    r = c.post("/ai/v1/chat/completions", json=CHAT, headers=bearer(tok, who))
    assert r.status_code == 200 and r.json()["choices"][0]["message"]["content"] == "Aiyo, welcome!"
    assert c.post("/ai/admin/players", headers=bearer(adm, ME)).json()["players"][0]["ai_today"] == 1
    # removing cuts them off at once
    c.post("/ai/admin/decide", json={"id": players[0]["id"], "action": "remove"}, headers=bearer(adm, ME))
    assert c.post("/ai/v1/chat/completions", json=CHAT, headers=bearer(tok, who)).status_code == 401
    r = c.post("/ai/accounts/login", json={"username": "jingqi", "password": "kopi-o-kosong"}, headers=who)
    tok = r.json()["token"]
    assert r.json()["status"] == "removed"
    assert c.post("/ai/v1/chat/completions", json=CHAT, headers=bearer(tok, who)).status_code == 403


@pytest.mark.parametrize("path", ["/download", "/v1/device", "/v1/stalls", "/delete", "/ai/admin/players", "/docs",
                                  "/openapi.json"])
def test_the_public_side_sees_nothing_but_accounts_and_the_ai(app, path):
    c, _, _ = app
    assert c.get(path, headers=GATEWAY).status_code == 404
    assert c.post(path, headers=GATEWAY).status_code == 404


def test_admin_is_admin_admin_and_only_logs_in_over_tailscale(app):
    c, _, _ = app
    for who in (GATEWAY, NOBODY):
        r = c.post("/ai/accounts/login", json={"username": "admin", "password": "admin"}, headers=who)
        assert r.status_code == 401 and r.json()["detail"] == "Wrong username or password."   # as if it didn't exist
    adm = admin_token(c)
    # an admin login can't be used from the public side either
    assert c.post("/ai/accounts/me", headers=bearer(adm, GATEWAY)).status_code == 401
    assert c.post("/ai/v1/chat/completions", json=CHAT, headers=bearer(adm, GATEWAY)).status_code == 401
    assert c.post("/ai/admin/players", headers=bearer(adm, GATEWAY)).status_code == 404
    # and players aren't admins
    tok = c.post("/ai/accounts/signup", json={"username": "ahboy", "password": "secret12"}, headers=ME).json()["token"]
    assert c.post("/ai/admin/players", headers=bearer(tok, ME)).status_code == 403
    assert c.post("/ai/admin/players", headers=ME).status_code == 403
    # nobody can sign up as "admin"
    assert c.post("/ai/accounts/signup", json={"username": "ADMIN", "password": "whatever1"}, headers=ME).status_code == 409


def test_everyone_can_change_their_own_password_and_the_default_is_flagged(app):
    c, _, _ = app
    adm = admin_token(c)
    assert c.post("/ai/admin/players", headers=bearer(adm, ME)).json()["default_password"] is True
    assert c.post("/ai/accounts/password", json={"old": "nope", "new": "teh-tarik-88"}, headers=bearer(adm, ME)).status_code == 403
    assert c.post("/ai/accounts/password", json={"old": "admin", "new": "teh-tarik-88"}, headers=bearer(adm, ME)).status_code == 200
    assert c.post("/ai/admin/players", headers=bearer(adm, ME)).json()["default_password"] is False   # still logged in
    assert c.post("/ai/accounts/login", json={"username": "admin", "password": "admin"}, headers=ME).status_code == 401
    admin_token(c, "teh-tarik-88")
    # a player too, from the public side; their other phones are logged out
    r = c.post("/ai/accounts/signup", json={"username": "mei_fan", "password": "durian123"}, headers=GATEWAY)
    phone1 = r.json()["token"]
    phone2 = c.post("/ai/accounts/login", json={"username": "mei_fan", "password": "durian123"}, headers=GATEWAY).json()["token"]
    assert c.post("/ai/accounts/password", json={"old": "durian123", "new": "mango4567"}, headers=bearer(phone1, GATEWAY)).status_code == 200
    assert c.post("/ai/accounts/me", headers=bearer(phone1, GATEWAY)).status_code == 200
    assert c.post("/ai/accounts/me", headers=bearer(phone2, GATEWAY)).status_code == 401
    assert c.post("/ai/accounts/login", json={"username": "mei_fan", "password": "mango4567"}, headers=GATEWAY).status_code == 200


def test_admin_can_reset_a_forgotten_password(app):
    c, _, _ = app
    old = c.post("/ai/accounts/signup", json={"username": "uncle_tan", "password": "forgot-it"}, headers=GATEWAY).json()["token"]
    adm = admin_token(c)
    pid = c.post("/ai/admin/players", headers=bearer(adm, ME)).json()["players"][0]["id"]
    pw = c.post("/ai/admin/decide", json={"id": pid, "action": "reset"}, headers=bearer(adm, ME)).json()["password"]
    assert c.post("/ai/accounts/me", headers=bearer(old, GATEWAY)).status_code == 401
    assert c.post("/ai/accounts/login", json={"username": "uncle_tan", "password": pw}, headers=GATEWAY).status_code == 200


def test_wrong_passwords_lock_the_public_side_only(app):
    c, _, _ = app
    c.post("/ai/accounts/signup", json={"username": "kopi_lover", "password": "right-one"}, headers=GATEWAY)
    for _ in range(5):
        assert c.post("/ai/accounts/login", json={"username": "admin", "password": "guess"}, headers=GATEWAY).status_code == 401
        assert c.post("/ai/accounts/login", json={"username": "kopi_lover", "password": "guess"}, headers=GATEWAY).status_code == 401
    assert c.post("/ai/accounts/login", json={"username": "kopi_lover", "password": "right-one"}, headers=GATEWAY).status_code == 429
    admin_token(c)    # internet guessing never locks the owner out over Tailscale
    assert c.post("/ai/accounts/login", json={"username": "kopi_lover", "password": "right-one"}, headers=ME).status_code == 200


def test_sign_up_rules(app):
    c, accounts, _ = app
    bad = [("ab", "longenough"), ("has space", "longenough"), ("-dash", "longenough"), ("fine_name", "abc"), ("x" * 21, "longenough")]
    for u, p in bad:
        assert c.post("/ai/accounts/signup", json={"username": u, "password": p}, headers=GATEWAY).status_code == 400, u
    assert c.post("/ai/accounts/signup", json={"username": "Siti", "password": "longenough"}, headers=GATEWAY).status_code == 200
    assert c.post("/ai/accounts/signup", json={"username": "siti", "password": "longenough"}, headers=GATEWAY).status_code == 409
    # passwords are never kept readable
    with accounts._db() as db:
        stored = [r[0] for r in db.execute("SELECT pw FROM accounts")]
    assert all(s.startswith("scrypt$") and "longenough" not in s and s != "admin" for s in stored)


def test_daily_allowance_per_account(app, monkeypatch):
    c, accounts, _ = app
    import hh.api as api
    monkeypatch.setattr(api, "PUBLIC_AI_PER_DAY", 2)
    c2 = TestClient(create_app(Store(":memory:"), AI(base_url="http://model/v1", session=FakeModel()), accounts, gate=True,
                               gateway_logins={"friend@example.com"}))
    tok = c2.post("/ai/accounts/signup", json={"username": "greedy", "password": "longenough"}, headers=GATEWAY).json()["token"]
    pid = accounts.list()[0]["id"]
    accounts.decide(pid, "approve")
    codes = [c2.post("/ai/v1/chat/completions", json=CHAT, headers=bearer(tok, GATEWAY)).status_code for _ in range(3)]
    assert codes == [200, 200, 429]


def test_without_the_gate_nothing_changes(tmp_path):
    c = TestClient(create_app(Store(":memory:"), AI(base_url="http://model/v1", session=FakeModel()), Accounts(tmp_path / "a.db")))
    assert c.post("/ai/v1/chat/completions", json=CHAT).status_code == 200
    assert c.get("/download").status_code == 200


def test_friends_on_tailscale_play_freely_but_cannot_be_admin(app):
    c, _, _ = app
    assert c.post("/ai/v1/chat/completions", json=CHAT, headers=FRIEND).status_code == 200
    r = c.post("/ai/accounts/login", json={"username": "admin", "password": "admin"}, headers=FRIEND)
    assert r.status_code == 401 and r.json()["detail"] == "Wrong username or password."
    adm = admin_token(c)                       # the owner's own login
    assert c.post("/ai/admin/players", headers=bearer(adm, FRIEND)).status_code == 403
    assert c.post("/ai/accounts/me", headers=bearer(adm, FRIEND)).status_code == 401
    assert c.post("/ai/accounts/password", json={"old": "admin", "new": "hijacked1"}, headers=bearer(adm, FRIEND)).status_code == 401
    for _ in range(6):                         # a friend guessing can't lock the owner out
        c.post("/ai/accounts/login", json={"username": "admin", "password": "guess"}, headers=FRIEND)
    admin_token(c)


def test_no_admin_logins_set_means_no_admin_at_all(tmp_path):
    c = TestClient(create_app(Store(":memory:"), AI(base_url=""), Accounts(tmp_path / "a.db"), gate=True,
                              admin_logins=set()))
    assert c.post("/ai/accounts/login", json={"username": "admin", "password": "admin"}, headers=ME).status_code == 401


# ------------------------------------------------------------------ game progress, one copy per account
def signup(c, name, who=GATEWAY):
    r = c.post("/ai/accounts/signup", json={"username": name, "password": "kopi-o-kosong"}, headers=who)
    assert r.status_code == 200, r.text
    return r.json()["token"]


@pytest.mark.parametrize("who", [GATEWAY, NOBODY, FRIEND, ME])
def test_progress_follows_the_account_from_any_phone(app, who):
    c, _, _ = app
    tok = signup(c, "JingQi", who)          # pending accounts keep progress too (it costs no AI)
    assert c.post("/ai/accounts/progress", headers=bearer(tok, who)).json() == {"data": None, "rev": 0}
    r = c.post("/ai/accounts/progress/save", json={"data": '{"name": "Jing Qi"}', "rev": 0}, headers=bearer(tok, who))
    assert r.status_code == 200 and r.json() == {"rev": 1}
    # another phone logs in to the same account and sees the same progress
    other = c.post("/ai/accounts/login", json={"username": "jingqi", "password": "kopi-o-kosong"}, headers=who)
    got = c.post("/ai/accounts/progress", headers=bearer(other.json()["token"], who)).json()
    assert got == {"data": '{"name": "Jing Qi"}', "rev": 1}


def test_progress_needs_a_login_and_is_private(app):
    c, _, _ = app
    a, b = signup(c, "Aaa"), signup(c, "Bbb")
    c.post("/ai/accounts/progress/save", json={"data": '{"name": "A"}', "rev": 0}, headers=bearer(a, GATEWAY))
    assert c.post("/ai/accounts/progress", headers=bearer(b, GATEWAY)).json()["data"] is None
    for path in ("/ai/accounts/progress", "/ai/accounts/progress/save", "/ai/accounts/progress/delete"):
        assert c.post(path, json={"data": "{}", "rev": 0}, headers=GATEWAY).status_code == 401
        assert c.post(path, json={"data": "{}", "rev": 0}, headers=bearer("hh_nope", NOBODY)).status_code == 401


def test_a_stale_phone_cannot_overwrite_newer_progress(app):
    c, _, _ = app
    tok = signup(c, "JingQi")
    h = bearer(tok, GATEWAY)
    assert c.post("/ai/accounts/progress/save", json={"data": '{"n": 1}', "rev": 0}, headers=h).json()["rev"] == 1
    assert c.post("/ai/accounts/progress/save", json={"data": '{"n": 2}', "rev": 1}, headers=h).json()["rev"] == 2
    r = c.post("/ai/accounts/progress/save", json={"data": '{"n": 0}', "rev": 1}, headers=h)   # the other phone
    assert r.status_code == 409
    assert c.post("/ai/accounts/progress", headers=h).json() == {"data": '{"n": 2}', "rev": 2}


def test_bad_or_huge_progress_is_refused(app):
    c, _, _ = app
    h = bearer(signup(c, "JingQi"), GATEWAY)
    for body in ({"data": "not json", "rev": 0}, {"data": "[1]", "rev": 0}, {"data": {"a": 1}, "rev": 0}, {"rev": 0},
                 {"data": "{}", "rev": "0"}):
        assert c.post("/ai/accounts/progress/save", json=body, headers=h).status_code == 400, body
    big = '{"x": "' + "a" * (600 * 1024) + '"}'
    assert c.post("/ai/accounts/progress/save", json={"data": big, "rev": 0}, headers=h).status_code == 413
    assert c.post("/ai/accounts/progress", headers=h).json()["rev"] == 0


def test_delete_my_data_clears_the_account_copy(app):
    c, _, _ = app
    h = bearer(signup(c, "JingQi"), GATEWAY)
    c.post("/ai/accounts/progress/save", json={"data": '{"n": 1}', "rev": 0}, headers=h)
    assert c.post("/ai/accounts/progress/delete", headers=h).json() == {"rev": 2}
    assert c.post("/ai/accounts/progress", headers=h).json() == {"data": "", "rev": 2}


def test_removed_and_rejected_accounts_keep_no_progress(app):
    c, accounts, _ = app
    rej, rem = signup(c, "Rejected"), signup(c, "Removed")
    ids = {p["username"]: p["id"] for p in accounts.list()}
    adm = admin_token(c)
    c.post("/ai/admin/decide", json={"id": ids["Rejected"], "action": "reject"}, headers=bearer(adm, ME))
    c.post("/ai/admin/decide", json={"id": ids["Removed"], "action": "remove"}, headers=bearer(adm, ME))
    assert c.post("/ai/accounts/progress", headers=bearer(rej, GATEWAY)).status_code == 403
    assert c.post("/ai/accounts/progress", headers=bearer(rem, GATEWAY)).status_code == 401   # logged out everywhere


def test_admin_progress_only_from_the_owners_login(app):
    c, _, _ = app
    adm = admin_token(c)
    r = c.post("/ai/accounts/progress/save", json={"data": '{"name": "Caspar"}', "rev": 0}, headers=bearer(adm, ME))
    assert r.status_code == 200
    assert c.post("/ai/accounts/progress", headers=bearer(adm, ME)).json()["rev"] == 1
    for who in (FRIEND, GATEWAY, NOBODY):
        assert c.post("/ai/accounts/progress", headers=bearer(adm, who)).status_code in (401, 404)
