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


# Reference runs from the browser engine (rules version 4): serve the first customer, an input every three ticks.
RUNS = {"daily_fast":[[130,"cook","grill",-1],[133,"base","plate",-1],[136,"add","rice",0],[139,"add","chicken",0],[142,"add","cucumber",0],[145,"serve",0,-1],[148,"base","plate",-1],[151,"add","rice",0],[154,"add","chicken",0],[157,"add","cucumber",0],[160,"add","chilli",0],[163,"serve",0,-1]],"daily_slow":[[280,"cook","grill",-1],[283,"base","plate",-1],[286,"add","rice",0],[289,"add","chicken",0],[292,"add","cucumber",0],[295,"serve",0,-1],[298,"base","plate",-1],[301,"add","rice",0],[304,"add","chicken",0],[307,"add","cucumber",0],[310,"add","chilli",0],[313,"serve",0,-1]],"speed_fast":[[130,"base","cup",-1],[133,"add","teh",0],[136,"add","milk",0],[139,"serve",0,-1]],"speed_slow":[[600,"base","cup",-1],[603,"add","teh",0],[606,"add","milk",0],[609,"serve",0,-1]]}
VALUES = {"daily_fast": 315, "daily_slow": 253, "speed_fast": 27190, "speed_slow": 27307}


def run(t, name="Chef", slow=False):
    key = f"{t['mode']}_{'slow' if slow else 'fast'}"
    return {**t, "name": name, "value": VALUES[key], "actions": RUNS[key]}


@pytest.mark.parametrize("mode,period,first,second", [
    ("daily", "2026-11-29", 315, 253), ("speed", "2026-11-23", 27190, 27307)])
def test_leaderboard_replays_and_keeps_each_nicknames_best(web, mode, period, first, second):
    client, clock = web
    bodies = [run(ticket(client, mode), "Bea", True), run(ticket(client, mode), "Chef", True),
              run(ticket(client, mode), "cHEF")]
    assert len({b["ticket"] for b in bodies}) == 3
    assert all(b["period"] == period and b["engine"] == 5 for b in bodies)
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
    {"mode": "speed"}, {"mode": []}, {"engine": True}, {"engine": 3}, {"period": "2026-11-30"}, {"value": 1668},
    {"ticket": "unknown"}, {"name": "x"}, {"actions": None}, {"actions": [[True, "base", "cup", 0]]},
    {"actions": [[550, "base", "cup"], [120, "add", "milk"]]}, {"actions": [[10, "mystery", "cup"]]},
    {"actions": [[120, "serve", 0, 0]]}, {"actions": [[3600, "base", "cup"]]},
    {"actions": [[10, "base", "cup", 3]]}, {"actions": [[10, "call", 0, -1]]}, {"actions": [[10, "take", "toaster", 7]]}, {"actions": [[10, "flip", "oven", -1]]}, {"actions": [[0, "base", {"key": [1]}]]}, {"actions": [[0, "base", "cup"]] * 3000},
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
    for mode, value in [("daily", 0), ("speed", 28573)]:
        t = ticket(client, mode)
        clock[0] += 130
        r = post(client, "score", {**t, "name": "Chef", "actions": [], "value": value})
        assert r.status_code == 200 and not r.json()["saved"] and r.json()["entries"] == []


# A whole Daily Rush from the browser engine that uses every kind of move: the wok, flipping prata, plating up...
FULL_SHIFT = [[13,"cook","grill",-1],[25,"base","plate",-1],[36,"add","rice",0],[46,"add","chicken",0],[64,"add","cucumber",0],[80,"serve",0,-1],[92,"base","plate",-1],[109,"add","rice",0],[125,"add","chicken",0],[142,"add","cucumber",0],[156,"add","chilli",0],[166,"serve",0,-1],[177,"base","plate",-1],[187,"add","satay",0],[200,"add","peanut",0],[218,"serve",0,-1],[231,"base","pastry",-1],[242,"add","potato",0],[256,"add","curry",0],[272,"cook-dish",0,-1],[286,"base","cup",-1],[297,"add","teh",0],[312,"add","milk",0],[327,"serve",0,-1],[342,"base","cup",-1],[355,"add","teh",0],[370,"add","milk",0],[385,"add","ice",0],[403,"serve",0,-1],[415,"take","wok",-1],[428,"serve",0,-1],[439,"base","pastry",-1],[450,"add","potato",0],[464,"add","curry",0],[482,"cook-dish",0,-1],[496,"base","cup",-1],[512,"add","kopi",0],[524,"add","milk",0],[538,"serve",0,-1],[554,"base","cup",-1],[565,"add","kopi",0],[581,"add","milk",0],[597,"add","ice",0],[609,"serve",0,-1],[619,"take","wok",-1],[635,"serve",0,-1],[652,"base","pastry",-1],[669,"add","potato",0],[684,"add","curry",0],[702,"cook-dish",0,-1],[715,"base","cup",-1],[727,"add","teh",0],[741,"add","milk",0],[753,"serve",0,-1],[771,"base","pastry",-1],[786,"add","potato",0],[799,"add","curry",0],[813,"cook-dish",0,-1],[824,"take","wok",-1],[842,"serve",0,-1],[853,"cook","pot",-1],[870,"base","plate",-1],[886,"add","rice",0],[902,"add","chicken",0],[919,"add","cucumber",0],[932,"add","chilli",0],[946,"serve",0,-1],[960,"take","wok",-1],[972,"serve",0,-1],[989,"base","bowl",-1],[1004,"add","eggs",0],[1019,"add","soy",0],[1035,"serve",0,-1],[1048,"base","cup",-1],[1063,"add","teh",0],[1075,"add","milk",0],[1089,"serve",0,-1],[1102,"base","cup",-1],[1118,"add","teh",0],[1132,"add","milk",0],[1145,"add","ice",0],[1156,"serve",0,-1],[1168,"base","cup",-1],[1180,"add","teh",0],[1193,"add","milk",0],[1210,"add","ice",0],[1227,"serve",0,-1],[1240,"cook","grill",-1],[1255,"base","plate",-1],[1272,"add","peanut",0],[1289,"base","cup",-1],[1301,"add","kopi",1],[1315,"serve",1,-1],[1328,"base","cup",-1],[1339,"add","kopi",1],[1350,"add","milk",1],[1368,"serve",1,-1],[1385,"add","satay",0],[1399,"serve",0,-1],[1413,"base","cup",-1],[1427,"add","kopi",0],[1444,"add","milk",0],[1455,"add","ice",0],[1471,"serve",0,-1],[1483,"base","dough",-1],[1497,"cook-dish",0,-1],[1509,"base","dough",-1],[1526,"cook-dish",0,-1],[1541,"base","dough",-1],[1557,"flip","griddle",-1],[1572,"add","egg",0],[1589,"flip","griddle",-1],[1605,"base","pastry",-1],[1621,"take","griddle",-1],[1632,"cook-dish",0,-1],[1646,"add","potato",1],[1663,"take","griddle",-1],[1676,"add","curry",1],[1691,"serve",0,-1],[1705,"flip","griddle",-1],[1720,"cook-dish",1,-1],[1732,"base","pastry",-1],[1748,"add","potato",0],[1763,"add","curry",0],[1781,"take","griddle",-1],[1791,"serve",1,-1],[1803,"cook-dish",0,-1],[1818,"cook","pot",-1],[1833,"base","bowl",-1],[1845,"take","wok",-1],[1862,"serve",1,-1],[1874,"add","soy",0],[1889,"base","cup",-1],[1905,"add","kopi",1],[1917,"add","milk",1],[1933,"serve",1,-1],[1944,"take","wok",-1],[1960,"serve",1,-1],[1975,"add","eggs",0],[1991,"serve",0,-1],[2006,"base","dough",-1],[2023,"cook-dish",0,-1],[2040,"base","dough",-1],[2050,"cook-dish",0,-1],[2065,"base","dough",-1],[2078,"add","egg",0],[2096,"flip","griddle",-1],[2111,"serve",2,-1],[2125,"flip","griddle",-1],[2138,"cook","toaster",-1],[2149,"base","plate",-1],[2164,"take","griddle",-1],[2178,"cook-dish",0,-1],[2193,"take","griddle",-1],[2210,"add","rice",1],[2226,"add","chicken",1],[2244,"flip","griddle",-1],[2261,"add","cucumber",1],[2276,"serve",1,-1],[2289,"base","cup",-1],[2301,"add","kopi",1],[2313,"add","milk",1],[2323,"serve",1,-1],[2341,"take","griddle",-1],[2352,"serve",1,-1],[2366,"base","cup",-1],[2376,"add","teh",1],[2389,"add","milk",1],[2405,"serve",1,-1],[2417,"cook","toaster",-1],[2428,"base","plate",-1],[2440,"add","kaya",1],[2457,"add","butter",1],[2469,"bin-burnt","toaster",-1],[2482,"cook","toaster",-1],[2496,"bin-dish",0,-1],[2513,"base","plate",-1],[2527,"add","rice",0],[2539,"add","chicken",0],[2550,"add","cucumber",0],[2565,"serve",0,-1],[2576,"add","toast",1],[2587,"serve",1,-1],[2602,"base","cup",-1],[2619,"add","teh",0],[2631,"add","milk",0],[2649,"serve",0,-1],[2661,"base","plate",-1],[2672,"add","rice",0],[2685,"add","chicken",0],[2698,"add","cucumber",0],[2716,"add","chilli",0],[2730,"serve",0,-1],[2743,"cook","toaster",-1],[2756,"base","plate",-1],[2773,"add","kaya",0],[2787,"add","butter",0],[2798,"base","pastry",-1],[2811,"add","potato",1],[2827,"add","curry",1],[2842,"cook-dish",1,-1],[2856,"add","toast",0],[2867,"serve",0,-1],[2971,"take","wok",-1],[2984,"serve",0,-1]]


def test_a_whole_shift_with_the_wok_and_griddle_replays_and_saves(web):
    client, clock = web
    t = ticket(client, "daily")
    assert {a[1] for a in FULL_SHIFT} >= {"cook-dish", "flip", "take"}
    clock[0] += 125
    r = post(client, "score", {**t, "name": "Chef", "value": 27009, "actions": FULL_SHIFT})
    assert r.status_code == 200, r.text
    assert r.json()["saved"] and r.json()["entries"][0]["value"] == 27009
