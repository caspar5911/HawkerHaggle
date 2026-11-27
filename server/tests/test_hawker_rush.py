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
RUNS = {"daily_fast":[[130,"cook","grill",-1],[133,"base","plate",-1],[136,"add","rice",0],[139,"add","chicken",0],[142,"add","cucumber",0],[145,"serve",0,-1],[148,"base","plate",-1],[151,"add","rice",0],[154,"add","chicken",0],[157,"add","cucumber",0],[160,"add","chilli",0],[163,"serve",0,-1],[166,"base","plate",-1],[169,"add","rice",0],[172,"add","chicken",0],[175,"add","cucumber",0],[178,"add","chilli",0],[181,"serve",0,-1]],"daily_slow":[[280,"cook","grill",-1],[283,"base","plate",-1],[286,"add","rice",0],[289,"add","chicken",0],[292,"add","cucumber",0],[295,"serve",0,-1],[298,"base","plate",-1],[301,"add","rice",0],[304,"add","chicken",0],[307,"add","cucumber",0],[310,"add","chilli",0],[313,"serve",0,-1],[316,"base","plate",-1],[319,"add","rice",0],[322,"add","chicken",0],[325,"add","cucumber",0],[328,"add","chilli",0],[331,"serve",0,-1]],"speed_fast":[[130,"base","cup",-1],[133,"add","teh",0],[136,"add","milk",0],[139,"serve",0,-1]],"speed_slow":[[600,"base","cup",-1],[603,"add","teh",0],[606,"add","milk",0],[609,"serve",0,-1]]}
VALUES = {"daily_fast": 1667, "daily_slow": 1588, "speed_fast": 27190, "speed_slow": 27307}


def run(t, name="Chef", slow=False):
    key = f"{t['mode']}_{'slow' if slow else 'fast'}"
    return {**t, "name": name, "value": VALUES[key], "actions": RUNS[key]}


@pytest.mark.parametrize("mode,period,first,second", [
    ("daily", "2026-11-29", 1667, 1588), ("speed", "2026-11-23", 27190, 27307)])
def test_leaderboard_replays_and_keeps_each_nicknames_best(web, mode, period, first, second):
    client, clock = web
    bodies = [run(ticket(client, mode), "Bea", True), run(ticket(client, mode), "Chef", True),
              run(ticket(client, mode), "cHEF")]
    assert len({b["ticket"] for b in bodies}) == 3
    assert all(b["period"] == period and b["engine"] == 4 for b in bodies)
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
FULL_SHIFT = [[13,"cook","grill",-1],[25,"base","plate",-1],[36,"add","rice",0],[46,"add","chicken",0],[64,"add","cucumber",0],[80,"serve",0,-1],[92,"base","plate",-1],[109,"add","rice",0],[125,"add","chicken",0],[142,"add","cucumber",0],[156,"add","chilli",0],[166,"serve",0,-1],[177,"base","plate",-1],[187,"add","rice",0],[200,"add","chicken",0],[218,"add","cucumber",0],[231,"add","chilli",0],[242,"serve",0,-1],[256,"base","cup",-1],[272,"add","teh",0],[286,"add","milk",0],[297,"add","ice",0],[312,"serve",0,-1],[327,"cook","grill",-1],[342,"base","dough",-1],[355,"cook-dish",0,-1],[370,"base","dough",-1],[385,"cook-dish",0,-1],[403,"base","cup",-1],[415,"flip","griddle",-1],[428,"add","teh",0],[439,"add","milk",0],[450,"serve",0,-1],[464,"flip","griddle",-1],[482,"take","griddle",-1],[496,"cook","pot",-1],[512,"base","dough",-1],[524,"take","griddle",-1],[538,"cook-dish",1,-1],[554,"base","dough",-1],[565,"cook-dish",1,-1],[581,"base","dough",-1],[597,"add","egg",1],[609,"flip","griddle",-1],[619,"bin-burnt","grill",-1],[635,"flip","griddle",-1],[652,"cook","grill",-1],[669,"bin-burnt","grill",-1],[684,"bin-dish",0,-1],[702,"take","griddle",-1],[715,"cook-dish",1,-1],[727,"take","griddle",-1],[741,"bin-dish",0,-1],[753,"base","bowl",-1],[771,"add","eggs",0],[786,"flip","griddle",-1],[799,"add","soy",0],[813,"serve",0,-1],[824,"base","cup",-1],[842,"add","kopi",0],[853,"serve",1,-1],[870,"take","griddle",-1],[886,"serve",1,-1],[902,"add","milk",0],[919,"add","ice",0],[932,"serve",0,-1],[946,"cook","grill",-1],[960,"cook","pot",-1],[972,"base","plate",-1],[989,"add","peanut",0],[1004,"base","plate",-1],[1019,"add","rice",1],[1035,"add","chicken",1],[1048,"add","cucumber",1],[1063,"add","chilli",1],[1075,"serve",1,-1],[1089,"add","satay",0],[1102,"serve",0,-1],[1118,"base","pastry",-1],[1132,"add","potato",0],[1145,"add","curry",0],[1156,"cook-dish",0,-1],[1168,"base","bowl",-1],[1180,"add","eggs",0],[1193,"add","soy",0],[1210,"serve",0,-1],[1227,"base","cup",-1],[1240,"add","teh",0],[1255,"add","milk",0],[1272,"serve",0,-1],[1289,"take","wok",-1],[1301,"serve",0,-1],[1315,"base","cup",-1],[1328,"add","kopi",0],[1339,"serve",0,-1],[1350,"base","cup",-1],[1368,"add","kopi",0],[1385,"add","milk",0],[1399,"add","ice",0],[1413,"serve",0,-1],[1427,"base","pastry",-1],[1444,"add","potato",0],[1455,"add","curry",0],[1471,"cook-dish",0,-1],[1483,"base","pastry",-1],[1497,"add","potato",0],[1509,"add","curry",0],[1526,"cook-dish",0,-1],[1541,"base","cup",-1],[1557,"add","teh",0],[1572,"add","milk",0],[1589,"serve",0,-1],[1605,"take","wok",-1],[1621,"serve",0,-1],[1632,"base","cup",-1],[1646,"add","teh",0],[1663,"take","wok",-1],[1676,"serve",1,-1],[1691,"add","milk",0],[1705,"add","ice",0],[1720,"serve",0,-1],[1732,"base","cup",-1],[1748,"add","teh",0],[1763,"add","milk",0],[1781,"add","ice",0],[1791,"serve",0,-1],[1803,"base","cup",-1],[1818,"add","kopi",0],[1833,"serve",0,-1],[1845,"base","cup",-1],[1862,"add","kopi",0],[1874,"add","milk",0],[1889,"add","ice",0],[1905,"serve",0,-1],[1917,"base","cup",-1],[1933,"add","teh",0],[1944,"add","milk",0],[1960,"add","ice",0],[1975,"serve",0,-1],[1991,"cook","grill",-1],[2006,"base","plate",-1],[2023,"add","peanut",0],[2040,"base","cup",-1],[2050,"add","kopi",1],[2065,"add","milk",1],[2078,"serve",1,-1],[2096,"base","cup",-1],[2111,"add","kopi",1],[2125,"add","satay",0],[2138,"serve",0,-1],[2149,"add","milk",1],[2164,"add","ice",1],[2178,"serve",1,-1],[2193,"base","pastry",-1],[2210,"add","potato",0],[2226,"add","curry",0],[2244,"cook-dish",0,-1],[2261,"base","cup",-1],[2276,"add","kopi",0],[2289,"add","milk",0],[2301,"add","ice",0],[2313,"serve",0,-1],[2323,"base","cup",-1],[2341,"add","kopi",0],[2352,"add","milk",0],[2366,"take","wok",-1],[2376,"serve",1,-1],[2389,"add","ice",0],[2405,"serve",0,-1],[2417,"cook","toaster",-1],[2428,"base","dough",-1],[2440,"cook-dish",0,-1],[2457,"base","dough",-1],[2469,"cook-dish",0,-1],[2482,"base","dough",-1],[2496,"add","egg",0],[2513,"flip","griddle",-1],[2527,"base","cup",-1],[2539,"flip","griddle",-1],[2550,"add","kopi",1],[2565,"add","milk",1],[2576,"add","ice",1],[2587,"serve",1,-1],[2602,"take","griddle",-1],[2619,"cook-dish",0,-1],[2631,"take","griddle",-1],[2649,"cook","toaster",-1],[2661,"bin-dish",0,-1],[2672,"base","cup",-1],[2685,"flip","griddle",-1],[2698,"add","teh",0],[2716,"add","milk",0],[2730,"add","ice",0],[2743,"serve",0,-1],[2756,"take","griddle",-1],[2773,"serve",0,-1],[2787,"base","pastry",-1],[2798,"add","potato",0],[2811,"add","curry",0],[2827,"cook-dish",0,-1],[2842,"base","dough",-1],[2856,"cook-dish",0,-1],[2867,"base","dough",-1],[2881,"cook-dish",0,-1],[2892,"base","dough",-1],[2906,"add","egg",0],[2919,"flip","griddle",-1],[2935,"bin-burnt","toaster",-1],[2945,"flip","griddle",-1],[2956,"cook","toaster",-1],[2971,"bin-burnt","toaster",-1],[2984,"cook","toaster",-1],[2995,"bin-dish",1,-1],[3009,"take","wok",-1],[3027,"serve",1,-1],[3043,"take","griddle",-1],[3058,"cook-dish",0,-1],[3073,"serve",1,-1],[3087,"take","griddle",-1],[3099,"base","plate",-1],[3111,"add","toast",1],[3125,"flip","griddle",-1],[3140,"add","kaya",1],[3150,"add","butter",1],[3161,"serve",1,-1],[3178,"base","plate",-1],[3194,"add","rice",1],[3209,"add","chicken",1],[3224,"add","cucumber",1],[3241,"serve",1,-1],[3256,"take","griddle",-1],[3268,"serve",1,-1],[3285,"cook","toaster",-1],[3296,"base","cup",-1],[3312,"add","teh",1],[3326,"add","milk",1],[3339,"add","ice",1],[3353,"serve",1,-1],[3364,"base","pastry",-1],[3381,"add","potato",1],[3393,"add","curry",1],[3407,"cook-dish",1,-1],[3424,"base","plate",-1],[3442,"add","rice",1],[3453,"add","chicken",1],[3463,"add","cucumber",1],[3480,"serve",1,-1],[3494,"base","cup",-1],[3510,"add","teh",1],[3523,"add","milk",1],[3537,"add","ice",1],[3553,"serve",1,-1],[3567,"take","wok",-1],[3578,"serve",1,-1],[3596,"base","plate",-1]]


def test_a_whole_shift_with_the_wok_and_griddle_replays_and_saves(web):
    client, clock = web
    t = ticket(client, "daily")
    assert {a[1] for a in FULL_SHIFT} >= {"cook-dish", "flip", "take"}
    clock[0] += 125
    r = post(client, "score", {**t, "name": "Chef", "value": 21839, "actions": FULL_SHIFT})
    assert r.status_code == 200, r.text
    assert r.json()["saved"] and r.json()["entries"][0]["value"] == 21839
