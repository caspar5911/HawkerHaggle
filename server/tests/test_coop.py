"""Live co-op rooms: a mailbox between two logged-in phones (the host's phone runs the haggle)."""
import pytest
from fastapi.testclient import TestClient

from hh.accounts import Accounts
from hh.ai import AI
from hh.api import create_app
from hh.coop import ROOM_IDLE, Rooms
from hh.store import Store

from test_accounts import GATEWAY, ME, NOBODY, bearer
from test_api import FakeModel


@pytest.fixture
def app(tmp_path):
    ai = AI(base_url="http://model/v1", model="gx10-current", session=FakeModel(line="hi"))
    c = TestClient(create_app(Store(":memory:"), ai, Accounts(tmp_path / "acc.db"), gate=True,
                              gateway_logins={"friend@example.com"}, admin_logins={"owner@example.com"}))
    return c


def player(c, name, who=GATEWAY):
    r = c.post("/ai/accounts/signup", json={"username": name, "password": "kopi-o-kosong"}, headers=who)
    assert r.status_code == 200, r.text
    return bearer(r.json()["token"], who)


def test_host_and_friend_through_the_public_domain(app):
    c = app
    host, friend = player(c, "Arella"), player(c, "Melody")
    r = c.post("/ai/coop/create", json={"stall": "mei", "item": "mango"}, headers=host)
    assert r.status_code == 200
    code = r.json()["code"]
    assert len(code) == 5 and code.isupper()
    j = c.post("/ai/coop/join", json={"code": code.lower()}, headers=friend).json()   # codes aren't case-sensitive
    assert j["host_name"] == "Arella" and j["joined"] and (j["stall"], j["item"]) == ("mei", "mango")
    # the friend sends a move; the host pulls it, plays it, and posts the new state
    assert c.post("/ai/coop/send", json={"code": code, "msg": {"type": "move", "text": " 12 can? "}},
                  headers=friend).status_code == 200
    got = c.post("/ai/coop/pull", json={"code": code, "after": 0}, headers=host).json()
    assert got["you"] == "host" and got["guest_name"] == "Melody"
    assert [m["type"] for m in got["messages"]] == ["joined", "move"]
    assert got["messages"][-1] == {"seq": 2, "from": "guest", "type": "move", "text": "12 can?"}
    state = {"type": "state", "view": {"line": "Aiyo, $16 lah", "ask": 16}}
    assert c.post("/ai/coop/send", json={"code": code, "msg": state}, headers=host).json() == {"seq": 3}
    seen = c.post("/ai/coop/pull", json={"code": code, "after": 2}, headers=friend).json()["messages"]
    assert seen == [{"seq": 3, "from": "host", **state}]
    # leaving: the friend can rejoin; the host closes the room
    assert c.post("/ai/coop/leave", json={"code": code}, headers=friend).status_code == 200
    assert c.post("/ai/coop/leave", json={"code": code}, headers=host).status_code == 200
    assert c.post("/ai/coop/pull", json={"code": code}, headers=friend).status_code == 404


def test_rooms_need_a_login_and_only_their_two_players(app):
    c = app
    host, friend, stranger = player(c, "Arella"), player(c, "Melody"), player(c, "Stranger")
    for path in ("/ai/coop/create", "/ai/coop/join", "/ai/coop/send", "/ai/coop/pull", "/ai/coop/leave"):
        assert c.post(path, json={}, headers=GATEWAY).status_code == 401
        assert c.post(path, json={}, headers=bearer("hh_nope", NOBODY)).status_code == 401
    code = c.post("/ai/coop/create", json={"stall": "mei", "item": "mango"}, headers=host).json()["code"]
    c.post("/ai/coop/join", json={"code": code}, headers=friend)
    assert c.post("/ai/coop/join", json={"code": code}, headers=stranger).status_code == 409    # full
    assert c.post("/ai/coop/pull", json={"code": code}, headers=stranger).status_code == 403
    assert c.post("/ai/coop/join", json={"code": code}, headers=host).status_code == 400        # your own room
    assert c.post("/ai/coop/join", json={"code": "ZZZZZ"}, headers=friend).status_code == 404
    assert c.post("/ai/coop/create", json={"stall": "nope", "item": "x"}, headers=host).status_code == 400


@pytest.mark.parametrize("msg", [
    {"type": "state", "view": {}},                     # a friend can't post the haggle's state
    {"type": "move"},                                  # nothing
    {"type": "move", "pick": 1, "text": "hi"},         # two at once
    {"type": "move", "pick": 7},
    {"type": "move", "pick": True},
    {"type": "move", "move": "steal"},
    {"type": "move", "text": "   "},
    {"type": "move", "text": "x" * 301},
    "not a dict",
])
def test_a_friend_can_only_send_proper_moves(app, msg):
    c = app
    host, friend = player(c, "Arella"), player(c, "Melody")
    code = c.post("/ai/coop/create", json={"stall": "mei", "item": "mango"}, headers=host).json()["code"]
    c.post("/ai/coop/join", json={"code": code}, headers=friend)
    assert c.post("/ai/coop/send", json={"code": code, "msg": msg}, headers=friend).status_code == 400


def test_the_host_sends_state_not_moves_and_big_messages_are_refused(app):
    c = app
    host, friend = player(c, "Arella"), player(c, "Melody")
    code = c.post("/ai/coop/create", json={"stall": "mei", "item": "mango"}, headers=host).json()["code"]
    c.post("/ai/coop/join", json={"code": code}, headers=friend)
    assert c.post("/ai/coop/send", json={"code": code, "msg": {"type": "move", "text": "hi"}},
                  headers=host).status_code == 400
    big = {"type": "state", "view": {"line": "x" * 9000}}
    assert c.post("/ai/coop/send", json={"code": code, "msg": big}, headers=host).status_code == 413


def test_polling_is_allowed_often_but_not_without_limit(app):
    c = app
    host = player(c, "Arella")
    code = c.post("/ai/coop/create", json={"stall": "mei", "item": "mango"}, headers=host).json()["code"]
    statuses = [c.post("/ai/coop/pull", json={"code": code}, headers=host).status_code for _ in range(160)]
    assert statuses[:100].count(200) == 100      # a phone polling every 1.5 s is fine
    assert 429 in statuses                       # a runaway loop is slowed down


def test_idle_rooms_expire_and_one_room_per_host():
    t = [1000.0]
    rooms = Rooms(clock=lambda: t[0])
    a = rooms.create(1, "Arella", "mei", "mango")["code"]
    b = rooms.create(1, "Arella", "lim", "pomfret")["code"]
    assert a not in rooms.rooms and b in rooms.rooms          # a new room replaces the old one
    t[0] += ROOM_IDLE + 1
    rooms.create(2, "Melody", "mei", "mango")
    assert b not in rooms.rooms                                # idle too long


def test_the_owner_on_tailscale_can_host_too(app):
    c = app
    r = c.post("/ai/accounts/login", json={"username": "admin", "password": "admin"}, headers=ME)
    adm = bearer(r.json()["token"], ME)
    assert c.post("/ai/coop/create", json={"stall": "mei", "item": "mango"}, headers=adm).status_code == 200
