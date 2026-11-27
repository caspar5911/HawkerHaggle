"""🏆 The arcade leaderboard (Ceiling Punch): the replay must match the browser's engine exactly, and only fair runs
are kept."""
import datetime as dt
import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from hh import arcade as A
from hh.accounts import Accounts
from hh.ai import AI
from hh.api import create_app
from hh.store import Store

FIX = json.loads((Path(__file__).parent / "fixtures" / "ceiling_punch.json").read_text())
GATEWAY = {"Tailscale-User-Login": "friend@example.com", "Origin": "https://caspar5911.github.io"}
TODAY = dt.date(2026, 12, 2)  # a Wednesday


# ------------------------------------------------------------------ the rules, exactly as the browser has them
def test_fixtures_are_for_this_engine():
    assert FIX["engine"] == A.ENGINE_VERSION


@pytest.mark.parametrize("tower", FIX["towers"], ids=lambda t: str(t["seed"]))
def test_every_ceiling_matches_the_browser(tower):
    for n, spans in enumerate(tower["ceilings"]):
        assert [list(s) for s in A.ceiling_at(tower["seed"], n)] == spans, f"seed {tower['seed']} ceiling {n}"


def test_next_seed_matches():
    for s, nxt in FIX["nextSeed"]:
        assert A.next_seed(s) == nxt


@pytest.mark.parametrize("run", FIX["runs"], ids=lambda r: f"{r['seed']}-{r['floor']}")
def test_every_whole_run_replays_to_the_same_floor(run):
    assert A.replay(run["seed"], run["taps"]) == run["floor"]


def test_the_runs_cover_real_play():
    floors = [r["floor"] for r in FIX["runs"]]
    assert max(floors) >= 50 and min(floors) == 0
    assert any(len(r["taps"]) > 40 for r in FIX["runs"])


def test_js_round_ties_go_up():
    assert [A._js_round(x) for x in (0.5, 1.5, 2.5, 2.4999, -0.5, 3.0)] == [1, 2, 3, 2, 0, 3]


def test_replay_refuses_nonsense():
    assert A.replay(1, [5, 3]) is None  # out of order
    assert A.replay(1, [1.5]) is None
    assert A.replay(1, [True]) is None
    assert A.replay(1, [-1]) is None
    assert A.replay(1, list(range(A.MAX_TAPS + 1))) is None
    assert A.replay(1, "nope") is None


def test_tampering_changes_the_floor():
    run = max(FIX["runs"], key=lambda r: r["floor"])
    shifted = [t + 7 for t in run["taps"]]  # tapping late every time
    assert A.replay(run["seed"], shifted) != run["floor"]
    assert A.replay(run["seed"] + 1, run["taps"]) != run["floor"]  # another tower


# ------------------------------------------------------------------ names
@pytest.mark.parametrize("raw,clean", [
    ("Caspar", "Caspar"), ("  ah   boy  ", "ah boy"), ("Mei-Ling O'Neil", "Mei-Ling O'Neil"), ("Robo 3000", "Robo 3000"),
    ("x", ""), ("<script>", "script"), ("a" * 40, "a" * 16), ("Fuck you", ""), ("f.u.c.k", ""), (12, ""), ("__", ""),
])
def test_names(raw, clean):
    assert A.clean_arcade_name(raw) == clean


# ------------------------------------------------------------------ tickets and the board
@pytest.fixture
def board(tmp_path):
    t = [1_800_000_000.0]
    return A.Arcade(tmp_path / "arcade.db", secret=b"k" * 32, clock=lambda: t[0]), t


def best_run():
    return max(FIX["runs"], key=lambda r: r["floor"])


def test_a_fair_run_is_saved_and_ranked(board):
    arc, _ = board
    run = best_run()
    ticket = arc.ticket(run["seed"])
    out = arc.submit("ceiling-punch", ticket["ticket"], run["seed"], run["taps"], run["floor"], "Caspar", 1, TODAY)
    assert out["saved"] and out["floor"] == run["floor"]
    assert out["week"][0] == {"place": 1, "name": "Caspar", "floor": run["floor"], "you": True}
    assert out["all"][0]["floor"] == run["floor"]


@pytest.mark.parametrize("change,why", [
    (dict(floor=+1), "didn't check out"),
    (dict(engine=2), "updated"),
    (dict(name="x"), "Pick a name"),
    (dict(ticket="1.2.3"), "wasn't started online"),
    (dict(seed=+1), "wasn't started online"),
])
def test_unfair_or_odd_runs_are_refused(board, change, why):
    arc, _ = board
    run = best_run()
    t = arc.ticket(run["seed"])["ticket"]
    args = dict(ticket=t, seed=run["seed"], taps=run["taps"], floor=run["floor"], name="Caspar", engine=1)
    for k, v in change.items():
        args[k] = args[k] + v if isinstance(v, int) and k in ("floor", "seed") else v
    with pytest.raises(ValueError, match=why):
        arc.submit("ceiling-punch", args["ticket"], args["seed"], args["taps"], args["floor"], args["name"],
                   args["engine"], TODAY)


def test_a_ticket_works_once_and_not_forever(board):
    arc, clock = board
    run = best_run()
    t = arc.ticket(run["seed"])["ticket"]
    arc.submit("ceiling-punch", t, run["seed"], run["taps"], run["floor"], "Caspar", 1, TODAY)
    with pytest.raises(ValueError, match="already saved"):
        arc.submit("ceiling-punch", t, run["seed"], run["taps"], run["floor"], "Caspar", 1, TODAY)
    old = arc.ticket(run["seed"])["ticket"]
    clock[0] += A.TICKET_HOURS * 3600 + 1
    with pytest.raises(ValueError, match="too old"):
        arc.submit("ceiling-punch", old, run["seed"], run["taps"], run["floor"], "Caspar", 1, TODAY)
    # a forged signature
    seed, issued, _ = arc.ticket(run["seed"])["ticket"].split(".")
    with pytest.raises(ValueError, match="started online"):
        arc.submit("ceiling-punch", f"{seed}.{issued}.{'0' * 32}", run["seed"], run["taps"], run["floor"], "C a", 1,
                   TODAY)


def test_the_board_keeps_each_names_best_and_resets_weekly(board):
    arc, _ = board
    runs = sorted((r for r in FIX["runs"] if r["floor"] > 0), key=lambda r: r["floor"])
    low, mid, high = runs[0], runs[len(runs) // 2], runs[-1]
    for run, name, day in [(low, "Ann", TODAY), (mid, "ann", TODAY), (high, "Bob", TODAY - dt.timedelta(days=7))]:
        t = arc.ticket(run["seed"])["ticket"]
        arc.submit("ceiling-punch", t, run["seed"], run["taps"], run["floor"], name, 1, day)
    b = arc.board("ceiling-punch", TODAY, "ANN")
    assert [(x["name"].lower(), x["floor"]) for x in b["week"]] == [("ann", mid["floor"])]  # Bob was last week
    assert b["week"][0]["you"] is True
    assert [x["floor"] for x in b["all"]] == [high["floor"], mid["floor"]]
    assert b["week_from"] == "2026-11-30"


def test_a_zero_floor_run_is_checked_but_not_listed(board):
    arc, _ = board
    t = arc.ticket(5)["ticket"]
    out = arc.submit("ceiling-punch", t, 5, [], 0, "Caspar", 1, TODAY)
    assert out["saved"] is False and out["week"] == []


def test_the_key_is_kept_outside_the_repo_and_private(tmp_path):
    arc = A.Arcade(tmp_path / "x" / "arcade.db")
    key = tmp_path / "x" / "arcade.key"
    assert key.exists() and len(key.read_bytes()) == 32
    assert oct(key.stat().st_mode & 0o777) == "0o600"
    assert A.Arcade(tmp_path / "x" / "arcade.db").secret == arc.secret  # (the same key next time)


# ------------------------------------------------------------------ over the web, from the public side
@pytest.fixture
def web(tmp_path):
    arc = A.Arcade(tmp_path / "arcade.db", secret=b"k" * 32)
    c = TestClient(create_app(Store(":memory:"), AI(base_url=""), Accounts(tmp_path / "acc.db"), gate=True,
                              gateway_logins={"friend@example.com"}, arcade=arc))
    return c, arc


def test_public_players_get_a_ticket_save_and_see_the_board(web):
    c, arc = web
    r = c.post("/ai/arcade/ceiling-punch/ticket", headers=GATEWAY)
    assert r.status_code == 200
    assert set(r.json()) == {"seed", "ticket", "engine"}
    assert r.headers["access-control-allow-origin"] == "https://caspar5911.github.io"
    run = best_run()
    t = arc.ticket(run["seed"])["ticket"]
    body = {"ticket": t, "seed": run["seed"], "taps": run["taps"], "floor": run["floor"], "name": "Caspar",
            "engine": 1}
    r = c.post("/ai/arcade/ceiling-punch/score", json=body, headers=GATEWAY)
    assert r.status_code == 200, r.text
    assert r.json()["all"][0]["name"] == "Caspar"
    r = c.post("/ai/arcade/ceiling-punch/score", json={**body, "floor": run["floor"] + 5}, headers=GATEWAY)
    assert r.status_code == 400
    r = c.post("/ai/arcade/ceiling-punch/top", json={"name": "caspar"}, headers=GATEWAY)
    assert r.json()["all"][0].get("you") is True
    # a preflight from the arcade's page is allowed
    r = c.options("/ai/arcade/ceiling-punch/score", headers={**GATEWAY, "Access-Control-Request-Method": "POST"})
    assert r.status_code == 204


def test_other_games_and_bad_bodies(web):
    c, _ = web
    assert c.post("/ai/arcade/snap-ruler/ticket", headers=GATEWAY).status_code == 404  # (not open to the public)
    assert c.post("/ai/arcade/ceiling-punch/score", content=b"[1]", headers=GATEWAY).status_code == 400
    assert c.post("/ai/arcade/ceiling-punch/score", json={"seed": "1", "floor": 1, "engine": 1},
                  headers=GATEWAY).status_code == 400
    assert c.post("/ai/arcade/ceiling-punch/score", content=b"x" * (65 * 1024), headers=GATEWAY).status_code == 413
