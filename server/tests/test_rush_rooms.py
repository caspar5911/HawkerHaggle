"""Hawker Rush co-op rooms: a fast in-memory mailbox between friends' phones."""
import asyncio
import threading
import time

from fastapi.testclient import TestClient
import pytest

from hh.accounts import Accounts
from hh.ai import AI
from hh.api import create_app
from hh.arcade import Arcade
from hh.rush_rooms import RoomError, RushRooms, ROOM_IDLE
from hh.store import Store

ROOM = "/ai/arcade/hawker-rush/room/"
ORIGIN = {"Origin": "https://caspar5911.github.io"}
SPEC = {"day": 6, "seed": "coop-abc123", "mode": "day", "upgrades": {"fan": 1}, "players": 2}


@pytest.fixture
def client(tmp_path):
    arcade = Arcade(tmp_path / "arcade.db", secret=b"k" * 32)
    # (one event loop for every request, like the real server: long-polls wake on news from other requests)
    with TestClient(create_app(Store(":memory:"), AI(base_url=""), Accounts(tmp_path / "accounts.db"),
                               arcade=arcade, gate=True)) as c:
        yield c


def call(client, what, body, status=200):
    r = client.post(ROOM + what, json=body, headers=ORIGIN)
    assert r.status_code == status, r.text
    return r.json()


def test_friends_share_a_stall_through_the_public_gateway(client):
    host = call(client, "create", {"name": "Mei"})
    assert host["seat"] == 0 and len(host["code"]) == 5 and host["state"] == "lobby"
    guest = call(client, "join", {"code": host["code"].lower(), "name": "  Ah  Boy!! "})
    assert guest["seat"] == 1 and [p["name"] for p in guest["players"]] == ["Mei", "Ah Boy"]
    # the host hears the new friend
    news = call(client, "pull", {"code": host["code"], "token": host["token"], "after": 0})
    assert [m["t"] for m in news["messages"]] == ["roster"] and len(news["players"]) == 2
    # the host starts; the friend taps; the host plays it and sends frames
    call(client, "send", {"code": host["code"], "token": host["token"], "msg": {"t": "start", "spec": SPEC}})
    call(client, "send", {"code": host["code"], "token": guest["token"], "msg": {"t": "act", "kind": "base", "a": "cup", "b": -1}})
    heard = call(client, "pull", {"code": host["code"], "token": host["token"], "after": news["seq"]})
    assert [m for m in heard["messages"]] == [{"seq": 3, "from": 1, "t": "act", "kind": "base", "a": "cup", "b": -1}]
    call(client, "send", {"code": host["code"], "token": host["token"],
                          "msg": {"t": "frames", "upTo": 40, "actions": [[31, "base", "cup", -1, 1]]}})
    seen = call(client, "pull", {"code": host["code"], "token": guest["token"], "after": 0})
    assert [m["t"] for m in seen["messages"]] == ["start", "frames"]   # (never its own messages)
    assert seen["messages"][0]["spec"] == SPEC and seen["state"] == "playing"
    r = client.post(ROOM + "pull", json={"code": host["code"], "token": guest["token"]}, headers=ORIGIN)
    assert r.headers["access-control-allow-origin"] == ORIGIN["Origin"]


def test_names_seats_and_codes(client):
    assert call(client, "create", {"name": "x"}, 400)["detail"].startswith("Choose a name")
    host = call(client, "create", {"name": "Mei"})
    for name in ["Bo", "Cy", "Di"]:
        call(client, "join", {"code": host["code"], "name": name})
    assert "four cooks" in call(client, "join", {"code": host["code"], "name": "Ed"}, 409)["detail"]
    call(client, "join", {"code": "ZZZZZ", "name": "Ed"}, 404)
    call(client, "pull", {"code": host["code"], "token": "not-a-real-token-at-all"}, 403)
    call(client, "pull", {"code": host["code"], "token": None}, 403)
    call(client, "nothing", {}, 404)


@pytest.mark.parametrize("msg,status", [
    ({"t": "start", "spec": SPEC}, 403), ({"t": "frames", "upTo": 1, "actions": []}, 403), ({"t": "pause"}, 403),
    ({"t": "act", "kind": "launch", "a": "cup"}, 400), ({"t": "act", "kind": "add", "a": "<b>"}, 400),
    ({"t": "act", "kind": "serve", "a": 0, "b": 99}, 400), ({"t": "act", "kind": "add", "a": {"x": 1}}, 400),
    ({"t": "emote", "e": "rude words"}, 400), ({"t": "say", "text": "hi"}, 400), ("act", 400), ({"t": "act", "kind": "add", "a": "x" * 5000}, 413),
])
def test_friends_can_only_send_moves_and_cheers(client, msg, status):
    host = call(client, "create", {"name": "Mei"})
    guest = call(client, "join", {"code": host["code"], "name": "Bo"})
    call(client, "send", {"code": host["code"], "token": guest["token"], "msg": msg}, status)
    call(client, "send", {"code": host["code"], "token": guest["token"], "msg": {"t": "emote", "e": "help"}})


@pytest.mark.parametrize("msg", [
    {"t": "start", "spec": {**SPEC, "players": 5}}, {"t": "start", "spec": {**SPEC, "mode": "speed"}},
    {"t": "start", "spec": {**SPEC, "seed": "bad seed!"}}, {"t": "start", "spec": {**SPEC, "upgrades": {"fan": 99}}},
    {"t": "frames", "upTo": 10, "actions": [[11, "base", "cup", -1, 0]]},
    {"t": "frames", "upTo": 10, "actions": [[5, "base", "cup", -1, 0], [4, "add", "kopi", -1, 0]]},
    {"t": "frames", "upTo": 10, "actions": [[5, "base", "cup", -1, 7]]}, {"t": "frames", "upTo": -1},
    {"t": "act", "kind": "base", "a": "cup"},   # (the host plays its own taps; only friends send moves)
])
def test_host_messages_are_checked(client, msg):
    host = call(client, "create", {"name": "Mei"})
    call(client, "send", {"code": host["code"], "token": host["token"], "msg": msg}, 400)


def test_pull_wakes_as_soon_as_there_is_news(client):
    host = call(client, "create", {"name": "Mei"})
    guest = call(client, "join", {"code": host["code"], "name": "Bo"})
    got = {}

    def wait():
        start = time.monotonic()
        got["body"] = call(client, "pull", {"code": host["code"], "token": guest["token"], "after": 1})
        got["took"] = time.monotonic() - start

    t = threading.Thread(target=wait)
    t.start()
    time.sleep(.3)
    call(client, "send", {"code": host["code"], "token": host["token"], "msg": {"t": "day", "day": 4}})
    t.join(5)
    assert got["body"]["messages"][0]["day"] == 4 and got["took"] < 2


def test_host_leaving_closes_the_stall_and_friends_can_leave(client):
    host = call(client, "create", {"name": "Mei"})
    guest = call(client, "join", {"code": host["code"], "name": "Bo"})
    friend = call(client, "join", {"code": host["code"], "name": "Cy"})
    call(client, "leave", {"code": host["code"], "token": friend["token"]})
    assert [p["name"] for p in call(client, "pull", {"code": host["code"], "token": guest["token"]})["players"]] == ["Mei", "Bo"]
    call(client, "leave", {"code": host["code"], "token": host["token"]})
    assert call(client, "pull", {"code": host["code"], "token": guest["token"]}, 404)["detail"] == "The stall has closed."


def test_joining_mid_shift_catches_up_and_idle_rooms_close():
    clock = [1000.0]
    rooms = RushRooms(clock=lambda: clock[0])

    async def play():
        host = rooms.create("Mei")
        rooms.send(host["code"], host["token"], {"t": "day", "day": 3})
        rooms.send(host["code"], host["token"], {"t": "start", "spec": SPEC})
        rooms.send(host["code"], host["token"], {"t": "frames", "upTo": 30, "actions": []})
        late = rooms.join(host["code"], "Bo")
        news = await rooms.pull(host["code"], late["token"], 0)
        assert [m["t"] for m in news["messages"]] == ["start", "frames", "roster"]
        clock[0] += ROOM_IDLE + 1
        with pytest.raises(RoomError):
            await rooms.pull(host["code"], late["token"], 0)

    asyncio.run(play())
