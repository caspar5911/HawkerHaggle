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
RUNS = {"daily_fast":[[280,"cook","pot",-1],[283,"cook","toaster",-1],[286,"base","cup",-1],[289,"add","teh",0],[292,"add","milk",0],[295,"serve",0,-1],[298,"base","bowl",-1],[301,"add","soy",0],[304,"base","cup",-1],[307,"add","teh",1],[310,"add","milk",1],[313,"add","ice",1],[316,"serve",1,-1],[319,"base","pastry",-1],[322,"add","potato",1],[325,"add","curry",1],[328,"cook-dish",1,-1],[331,"base","plate",-1],[334,"add","kaya",1],[337,"add","butter",1],[340,"base","dough",-1],[343,"add","egg",2],[346,"cook-dish",2,-1],[349,"base","plate",-1],[352,"add","rice",2],[355,"add","chicken",2],[358,"add","cucumber",2],[361,"add","chilli",2],[364,"serve",2,-1],[382,"add","toast",1],[385,"serve",1,-1],[391,"add","eggs",0],[394,"serve",0,-1]],"daily_slow":[[130,"cook","pot",-1],[133,"base","cup",-1],[136,"add","teh",0],[139,"add","milk",0],[142,"serve",0,-1],[145,"base","bowl",-1],[148,"add","soy",0],[151,"base","cup",-1],[154,"add","teh",1],[157,"add","milk",1],[160,"add","ice",1],[163,"serve",1,-1],[166,"base","pastry",-1],[169,"add","potato",1],[172,"add","curry",1],[175,"cook-dish",1,-1],[241,"add","eggs",0],[244,"serve",0,-1],[253,"cook","toaster",-1],[256,"base","plate",-1],[259,"add","kaya",0],[262,"add","butter",0],[265,"base","plate",-1],[268,"add","rice",1],[271,"add","chicken",1],[274,"add","cucumber",1],[277,"add","chilli",1],[280,"serve",1,-1],[298,"take","wok",-1],[301,"serve",1,-1]],"speed_fast":[[130,"base","cup",-1],[133,"add","teh",0],[136,"add","milk",0],[139,"serve",0,-1],[142,"base","plate",-1],[145,"add","rice",0],[148,"add","chicken",0],[151,"add","cucumber",0],[154,"add","chilli",0],[157,"serve",0,-1],[160,"base","cup",-1],[163,"add","teh",0],[166,"add","milk",0],[169,"add","ice",0],[172,"serve",0,-1],[175,"base","dough",-1],[178,"add","egg",0],[181,"cook-dish",0,-1],[184,"base","cup",-1],[187,"add","kopi",0],[190,"add","milk",0],[193,"add","ice",0],[196,"serve",0,-1],[211,"base","cup",-1],[214,"add","teh",0],[217,"add","milk",0],[220,"add","ice",0],[223,"serve",0,-1]],"speed_slow":[[600,"base","cup",-1],[603,"add","teh",0],[606,"add","milk",0],[609,"serve",0,-1],[612,"base","cup",-1],[615,"add","teh",0],[618,"add","milk",0],[621,"add","ice",0],[624,"serve",0,-1],[627,"base","plate",-1],[630,"add","rice",0],[633,"add","chicken",0],[636,"add","cucumber",0],[639,"add","chilli",0],[642,"serve",0,-1],[645,"base","dough",-1],[648,"cook-dish",0,-1],[651,"base","cup",-1],[654,"add","teh",0],[657,"add","milk",0],[660,"add","ice",0],[663,"serve",0,-1]]}
VALUES = {"daily_fast": 1542, "daily_slow": 1176, "speed_fast": 23500, "speed_slow": 24297}


def run(t, name="Chef", slow=False):
    key = f"{t['mode']}_{'slow' if slow else 'fast'}"
    return {**t, "name": name, "value": VALUES[key], "actions": RUNS[key]}


@pytest.mark.parametrize("mode,period,first,second", [
    ("daily", "2026-11-29", 1542, 1176), ("speed", "2026-11-23", 23500, 24297)])
def test_leaderboard_replays_and_keeps_each_nicknames_best(web, mode, period, first, second):
    client, clock = web
    bodies = [run(ticket(client, mode), "Bea", True), run(ticket(client, mode), "Chef", True),
              run(ticket(client, mode), "cHEF")]
    assert len({b["ticket"] for b in bodies}) == 3
    assert all(b["period"] == period and b["engine"] == 7 for b in bodies)
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
FULL_SHIFT = [[13,"base","cup",-1],[25,"add","teh",0],[36,"add","milk",0],[46,"serve",0,-1],[64,"cook","pot",-1],[80,"base","bowl",-1],[92,"add","soy",0],[109,"base","cup",-1],[125,"add","teh",1],[142,"add","milk",1],[156,"add","ice",1],[166,"serve",1,-1],[177,"add","eggs",0],[187,"serve",0,-1],[200,"base","pastry",-1],[218,"add","potato",0],[231,"add","curry",0],[242,"cook-dish",0,-1],[256,"cook","toaster",-1],[272,"base","plate",-1],[286,"add","kaya",0],[297,"add","butter",0],[312,"base","plate",-1],[327,"add","rice",1],[342,"add","chicken",1],[355,"add","toast",0],[370,"serve",0,-1],[385,"take","wok",-1],[403,"serve",0,-1],[415,"add","cucumber",1],[428,"serve",1,-1],[439,"base","dough",-1],[450,"add","egg",0],[464,"cook-dish",0,-1],[482,"base","pastry",-1],[496,"add","potato",0],[512,"add","curry",0],[524,"flip","griddle",-1],[538,"cook-dish",0,-1],[554,"base","cup",-1],[565,"add","kopi",0],[581,"add","milk",0],[597,"serve",0,-1],[609,"take","griddle",-1],[619,"serve",0,-1],[635,"base","cup",-1],[652,"add","kopi",0],[669,"take","wok",-1],[684,"serve",1,-1],[702,"add","milk",0],[715,"add","ice",0],[727,"serve",0,-1],[741,"base","pastry",-1],[753,"add","potato",0],[771,"add","curry",0],[786,"cook-dish",0,-1],[799,"base","cup",-1],[813,"add","teh",0],[824,"add","milk",0],[842,"serve",0,-1],[853,"base","pastry",-1],[870,"add","potato",0],[886,"add","curry",0],[902,"cook-dish",0,-1],[919,"take","wok",-1],[932,"serve",0,-1],[946,"base","plate",-1],[960,"add","rice",0],[972,"add","chicken",0],[989,"add","cucumber",0],[1004,"add","chilli",0],[1019,"serve",0,-1],[1035,"take","wok",-1],[1048,"serve",0,-1],[1063,"cook","pot",-1],[1075,"base","plate",-1],[1089,"add","rice",0],[1102,"add","chicken",0],[1118,"add","cucumber",0],[1132,"add","chilli",0],[1145,"serve",0,-1],[1156,"base","bowl",-1],[1168,"add","soy",0],[1180,"add","eggs",0],[1193,"serve",0,-1],[1210,"base","cup",-1],[1227,"add","teh",0],[1240,"add","milk",0],[1255,"serve",0,-1],[1272,"base","cup",-1],[1289,"add","teh",0],[1301,"add","milk",0],[1315,"add","ice",0],[1328,"serve",0,-1],[1339,"base","cup",-1],[1350,"add","teh",0],[1368,"add","milk",0],[1385,"add","ice",0],[1399,"serve",0,-1],[1413,"base","cup",-1],[1427,"add","kopi",0],[1444,"serve",0,-1],[1455,"cook","grill",-1],[1471,"base","plate",-1],[1483,"add","peanut",0],[1497,"base","cup",-1],[1509,"add","kopi",1],[1526,"add","milk",1],[1541,"add","ice",1],[1557,"serve",1,-1],[1572,"base","dough",-1],[1589,"add","satay",0],[1605,"serve",0,-1],[1621,"add","egg",1],[1632,"cook-dish",1,-1],[1646,"base","pastry",-1],[1663,"add","potato",0],[1676,"add","curry",0],[1691,"cook-dish",0,-1],[1705,"flip","griddle",-1],[1720,"base","cup",-1],[1732,"add","kopi",0],[1748,"add","milk",0],[1763,"serve",0,-1],[1781,"take","griddle",-1],[1791,"serve",0,-1],[1803,"base","pastry",-1],[1818,"take","wok",-1],[1833,"serve",1,-1],[1845,"add","potato",0],[1862,"add","curry",0],[1874,"cook-dish",0,-1],[1889,"base","dough",-1],[1905,"cook-dish",0,-1],[1917,"cook","pot",-1],[1933,"base","bowl",-1],[1944,"add","soy",0],[1975,"flip","griddle",-1],[2006,"take","wok",-1],[2023,"serve",1,-1],[2040,"take","griddle",-1],[2050,"serve",1,-1],[2065,"add","eggs",0],[2078,"serve",0,-1],[2096,"base","cup",-1],[2111,"add","kopi",0],[2125,"add","milk",0],[2138,"serve",0,-1],[2149,"base","dough",-1],[2164,"add","egg",0],[2178,"cook-dish",0,-1],[2193,"base","plate",-1],[2210,"add","rice",0],[2226,"add","chicken",0],[2244,"flip","griddle",-1],[2261,"add","cucumber",0],[2276,"serve",0,-1],[2301,"cook","toaster",-1],[2313,"take","griddle",-1],[2323,"serve",0,-1],[2341,"base","plate",-1],[2352,"add","kaya",0],[2366,"add","butter",0],[2376,"base","cup",-1],[2389,"add","kopi",1],[2405,"add","toast",0],[2417,"serve",0,-1],[2428,"add","milk",1],[2440,"serve",1,-1],[2457,"base","dough",-1],[2469,"cook-dish",0,-1],[2482,"base","plate",-1],[2496,"add","rice",0],[2513,"add","chicken",0],[2527,"add","cucumber",0],[2539,"flip","griddle",-1],[2550,"add","chilli",0],[2565,"serve",0,-1],[2576,"base","cup",-1],[2587,"add","teh",0],[2602,"take","griddle",-1],[2619,"serve",1,-1],[2631,"add","milk",0],[2649,"serve",0,-1]]


def test_a_whole_shift_with_the_wok_and_griddle_replays_and_saves(web):
    client, clock = web
    t = ticket(client, "daily")
    assert {a[1] for a in FULL_SHIFT} >= {"cook-dish", "flip", "take"}
    clock[0] += 125
    r = post(client, "score", {**t, "name": "Chef", "value": 25846, "actions": FULL_SHIFT})
    assert r.status_code == 200, r.text
    assert r.json()["saved"] and r.json()["entries"][0]["value"] == 25846
