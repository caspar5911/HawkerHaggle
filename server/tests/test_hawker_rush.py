"""Public leaderboard tests with reference runs from the Hawker Rush browser engine."""
from concurrent.futures import ThreadPoolExecutor
import datetime as dt

from fastapi.testclient import TestClient
import pytest

from hh.accounts import Accounts
from hh.ai import AI
from hh.api import create_app
from hh.arcade import Arcade
from hh.store import Store

BASE = "/ai/arcade/hawker-rush/"
ORIGIN = {"Origin": "https://caspar5911.github.io"}
SUNDAY = dt.datetime(2026, 11, 29, 14, tzinfo=dt.timezone.utc).timestamp()


@pytest.fixture
def web(tmp_path):
    clock = [SUNDAY]
    arcade = Arcade(tmp_path / "arcade.db", secret=b"k" * 32, clock=lambda: clock[0])
    client = TestClient(create_app(Store(":memory:"), AI(base_url=""), Accounts(tmp_path / "accounts.db"),
                                   arcade=arcade, gate=True))
    return client, clock


def post(client, route, body):
    return client.post(BASE + route, json=body, headers=ORIGIN)


def ticket(client, mode):
    response = post(client, "ticket", {"mode": mode})
    assert response.status_code == 200, response.text
    return response.json()


def run(t, name="Chef", slow=False):
    # Serve Sunday's first customer's two cups, three ticks between inputs.
    extra = [["add", "kopi", 0]] if t["mode"] == "daily" else [
        ["add", "teh", 0], ["add", "milk", 0], ["add", "ice", 0]]
    actions = [["base", "cup", 0], ["add", "kopi", 0], ["add", "milk", 0], ["serve", 0, 0],
               ["base", "cup", 0], *extra, ["serve", 0, 0]]
    if t["mode"] == "daily":
        start, value = (280, 480) if slow else (130, 527)
    else:
        start, value = (600, 25990) if slow else (130, 25823)
    return {**t, "name": name, "value": value,
            "actions": [[start + 3 * i, *a] for i, a in enumerate(actions, 1)]}


@pytest.mark.parametrize("mode,period,first,second", [
    ("daily", "2026-11-29", 527, 480), ("speed", "2026-11-23", 25823, 25990)])
def test_leaderboard_replays_and_keeps_each_nicknames_best(web, mode, period, first, second):
    client, clock = web
    bodies = [run(ticket(client, mode), "Bea", True), run(ticket(client, mode), "Chef", True),
              run(ticket(client, mode), "cHEF")]
    assert len({b["ticket"] for b in bodies}) == 3
    assert all(b["period"] == period and b["engine"] == 1 for b in bodies)
    clock[0] += 130
    for body in bodies:
        response = post(client, "score", body)
        assert response.status_code == 200, response.text
        assert response.json()["saved"]
    board = post(client, "top", {"mode": mode, "name": "chef"})
    assert board.headers["access-control-allow-origin"] == ORIGIN["Origin"]
    assert board.json() == {"mode": mode, "period": period, "entries": [
        {"place": 1, "name": "cHEF", "value": first, "you": True},
        {"place": 2, "name": "Bea", "value": second}]}


def test_score_receipt_survives_lost_response_and_competing_requests(web):
    client, clock = web
    body = run(ticket(client, "daily"))
    clock[0] += 120
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: post(client, "score", body), range(2)))
    assert all(r.status_code == 200 and len(r.json()["entries"]) == 1 for r in results)
    assert post(client, "score", {**body, "name": "Other Chef"}).status_code == 400


def test_tickets_carry_start_period_across_singapore_midnight_and_monday(web):
    client, clock = web
    clock[0] += 2 * 3600 - 60  # 23:59 Sunday in Singapore
    bodies = [run(ticket(client, mode)) for mode in ["daily", "speed"]]
    assert post(client, "score", bodies[0]).status_code == 400
    clock[0] += 130
    for body in bodies:
        board = post(client, "score", body)
        assert board.status_code == 200 and board.json()["period"] == body["period"]
        assert post(client, "top", {"mode": body["mode"]}).json() == {
            "mode": body["mode"], "period": "2026-11-30", "entries": []}


@pytest.mark.parametrize("change", [
    {"mode": "speed"}, {"mode": []}, {"engine": True}, {"engine": 2}, {"period": "2026-11-30"}, {"value": 528},
    {"ticket": "unknown"}, {"name": "x"}, {"actions": None}, {"actions": [[True, "base", "cup", 0]]},
    {"actions": [[550, "base", "cup"], [120, "add", "milk"]]}, {"actions": [[10, "mystery", "cup"]]},
    {"actions": [[120, "serve", 0, 0]]}, {"actions": [[3600, "base", "cup"]]},
    {"actions": [[10, "base", "cup", 3]]}, {"actions": [[0, "base", {"key": [1]}]]}, {"actions": [[0, "base", "cup"]] * 3000},
])
def test_invalid_submissions_leave_ticket_usable(web, change):
    client, clock = web
    body = run(ticket(client, "daily"))
    clock[0] += 120
    assert post(client, "score", {**body, **change}).status_code == 400
    assert post(client, "score", body).status_code == 200


def test_startup_network_delay_and_action_pacing(web):
    client, clock = web
    body = run(ticket(client, "daily"))
    clock[0] += 113  # Seven seconds elapsed in the browser before the ticket arrived.
    busy = [[0, kind, a, b] for _ in range(20) for kind, a, b in [
        ("base", "cup", 0), ("bin-dish", 0, -1)]]
    assert post(client, "score", {**body, "actions": busy + body["actions"]}).status_code == 400
    assert post(client, "score", body).status_code == 200


def test_missing_verifier_can_be_retried_without_losing_the_score(web, monkeypatch):
    client, clock = web
    body = run(ticket(client, "speed"))
    clock[0] += 130
    with monkeypatch.context() as patch:
        patch.setenv("HH_ARCADE_NODE", "/no/runtime/installed")
        response = post(client, "score", body)
        assert response.status_code == 503
    assert post(client, "score", body).status_code == 200


def test_expiry_and_request_limits(web):
    client, clock = web
    body = run(ticket(client, "daily"))
    clock[0] += 3 * 3600 + 2
    assert post(client, "score", body).status_code == 400
    assert post(client, "ticket", {"mode": "story"}).status_code == 400
    assert post(client, "top", {"mode": {}}).status_code == 400
    assert client.post(BASE + "score", content=b" " * (128 * 1024 + 1)).status_code == 413
    assert client.options(BASE + "score", headers={**ORIGIN, "Access-Control-Request-Method": "POST"}).status_code == 204


def test_idle_completed_shifts_leave_board_empty(web):
    client, clock = web
    for mode, value in [("daily", 0), ("speed", 27763)]:
        t = ticket(client, mode)
        clock[0] += 130
        r = post(client, "score", {**t, "name": "Chef", "actions": [], "value": value})
        assert r.status_code == 200 and not r.json()["saved"] and r.json()["entries"] == []
