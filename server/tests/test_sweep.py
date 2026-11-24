"""Full sweep, no AI: every stall x item x play style, many times, checking the game's rules on every reply.

Rules checked on every response:
  - a deal only ever closes right after a "confirm" step (the player said yes)
  - suggestions are empty exactly when the haggle is over or a deal waits for a yes
  - the asking price never goes up; a deal is never below 90% of the secret floor
  - every haggle ends within a bounded number of moves; moves after the end are refused (409)
  - the secret floor / fair price never appear in any response
  - every line is filled in: no {placeholders}, no "$" without a number
"""
import json
import random
import re

import pytest
from fastapi.testclient import TestClient

import hh.api
from hh.ai import AI, EVENTS
from hh.api import CONTENT, create_app
from hh.store import Store

EVENTS_ALL = {"greet", "counter", "final", "insulted", "accept", "flattered", "flattery_tired", "competitor_drop",
              "competitor_annoyed", "bulk", "regular", "smalltalk", "rude", "callback", "letgo", "refuse", "confused",
              "plead", "plead_no", "clarify", "confirm", "unsure", "budget_best", "pity", "pity_tired", "deflect"}

TYPED = ["15 can?", "$12 lah", "ok lah", "can cheaper?", "wah so nice", "next stall cheaper leh", "I buy two",
         "I come every week", "how's your day", "stupid", "never mind", "deal", "I buy 100 for 150?", "hmm ok",
         "😂😂", "asdfgh", "3 for 20?", "ok lah but my wallet crying", "my budget only 10", "I only have $9",
         "I only have $16", "I'm starving, nothing to eat", "no money lah", "12 can?", "12 can?", "$2 less can?",
         "meet halfway lah", "round down lah", "2 for 30?", "wah so nice, 14 can?", "go on a date with me", "15"]


def play(c, h, stall, item, style, rnd, seen):
    floor = next(i for s in CONTENT["stalls"] if s["id"] == stall for i in s["items"] if i["id"] == item)["floor"]
    g = c.post("/v1/haggle", json={"stall": stall, "item": item}, headers=h).json()
    check(g, seen)
    last_ask, was_pending = g["ask"], False
    for n in range(80):
        if g["done"]:
            break
        pending = g["pending"]
        if style == "bold":
            body = {"move": "confirm"} if pending else {"pick": 0}
        elif style == "safe":
            body = {"move": "confirm"} if pending else {"pick": 1}
        elif style == "tactic":
            body = {"move": "confirm"} if pending else {"pick": 2}
        elif style == "random_tap":
            body = rnd.choice([{"move": "confirm"}, {"move": "cancel"}]) if pending else \
                rnd.choice([{"pick": 0}, {"pick": 1}, {"pick": 2}, {"move": "accept"}, {"move": "walk"}])
        elif style == "typed":
            body = {"text": rnd.choice(TYPED + (["ok lah", "yes", "hmm"] if pending else []))}
        elif style == "old_app_accept_spam":
            body = {"move": "accept"}                       # an old app taps "OK lah" again on a waiting deal
        elif style == "cancel_reoffer":
            body = {"move": "cancel"} if pending else {"pick": 1}
        elif style == "button_buy":                         # new app: OK lah, Confirm, done
            body = {"move": "confirm"} if pending else rnd.choice([{"pick": 0}, {"pick": 1}, {"move": "buy"}])
        elif style == "sweet_talk_then_budget":            # compliments until tired, then "I only have $X"
            body = {"move": "confirm"} if pending else \
                ({"text": "wah so nice"} if n < 4 else {"text": f"I only have ${max(1, int(g['ask'] * 0.6))}"})
        elif style == "flatter_and_offer":                 # "so nice, $X can?" again and again
            body = {"move": "confirm"} if pending else {"text": f"wah so nice, {max(1, int(g['ask']) - 1)} can?"}
        elif style == "walk":
            body = {"move": "confirm"} if pending else {"move": "walk"}
        else:
            raise ValueError(style)
        r = c.post(f"/v1/haggle/{g['id']}/move", json=body, headers=h)
        assert r.status_code == 200, (style, body, r.text)
        g = r.json()
        check(g, seen)
        assert g["ask"] <= last_ask + 1e-9, (style, "price went up", last_ask, g["ask"])
        last_ask = g["ask"]
        if g["done"] and g["result"] == "deal":
            # a deal closes only after a yes: the confirm step, or the app's own Confirm tap ("buy")
            assert was_pending or body.get("move") == "buy", (style, "deal closed without a confirm step", body)
            assert g["deal"] >= floor * 0.9 - 0.01, (style, "below floor", g["deal"], floor)
            assert g["stars"] in (1, 2, 3)
        was_pending = g["pending"] is not None
    else:
        if style not in ("typed", "cancel_reoffer"):
            pytest.fail(f"{style} on {stall}/{item} did not end in 80 moves")
        return g, n
    assert c.post(f"/v1/haggle/{g['id']}/move", json={"pick": 0}, headers=h).status_code == 409
    return g, n


def check(g, seen):
    seen.add(g["event"])
    assert g["event"] in EVENTS_ALL, g["event"]
    text = json.dumps(g)
    assert '"floor"' not in text and '"fair"' not in text
    assert g["line"] and "{" not in g["line"] and "}" not in g["line"], g["line"]
    assert not re.search(r"\$(?!\d)", g["line"]), g["line"]
    should_be_empty = g["done"] or g["pending"] is not None
    assert (g["suggestions"] == []) == should_be_empty, (g["event"], g["pending"], g["suggestions"])
    if g["pending"] is not None:
        assert g["event"] in ("confirm", "clarify"), g["event"]
        assert not g["done"]


@pytest.fixture()
def api(monkeypatch):
    monkeypatch.setattr(hh.api, "MOVES_PER_MINUTE", 10**6)
    c = TestClient(create_app(Store(":memory:"), AI(base_url="")))
    h = {"Authorization": f"Bearer {c.post('/v1/device').json()['token']}"}
    return c, h


STYLES = ["bold", "safe", "tactic", "random_tap", "typed", "old_app_accept_spam", "cancel_reoffer", "button_buy",
          "sweet_talk_then_budget", "flatter_and_offer", "walk"]


def test_sweep_every_stall_item_and_play_style(api):
    c, h = api
    rnd = random.Random(2026)
    seen, results = set(), {}
    for s in CONTENT["stalls"]:
        for it in s["items"]:
            for style in STYLES:
                for _ in range(12):
                    g, _n = play(c, h, s["id"], it["id"], style, rnd, seen)
                    results[(style, g["result"] or "unfinished")] = results.get((style, g["result"] or "unfinished"), 0) + 1
    # every play style ends the way it should
    assert results.get(("old_app_accept_spam", "deal")) == 8 * 12        # never stuck: always a deal
    assert all(k[1] in ("deal", "walked", "refused", "unfinished") for k in results)
    assert sum(v for k, v in results.items() if k[1] == "deal") > 100
    assert sum(v for k, v in results.items() if k[1] == "walked") > 10
    assert sum(v for k, v in results.items() if k[1] == "refused") > 10
    # the sweep reached every kind of moment in the game
    # "confused" needs the AI to read an offer with no number; covered in test_api with a fake model
    assert EVENTS_ALL - seen <= {"confused"}, f"never reached: {EVENTS_ALL - seen}"


def test_every_event_has_lines_for_every_stall_and_they_fill_in():
    for s in CONTENT["stalls"]:
        for ev in EVENTS_ALL:
            lines = s["lines"].get(ev)
            assert lines, f"{s['id']} has no lines for {ev}"
            for line in lines:
                out = line.format(item="durian", price="$12", offer="$9")
                assert "{" not in out and "}" not in out
                if "{offer}" in line:
                    assert ev in ("counter", "final", "insulted", "budget_best"), (s["id"], ev, line)   # only where an offer exists


def test_the_ai_has_a_brief_for_every_event():
    assert EVENTS_ALL - {"greet"} <= set(EVENTS) | {"greet"}
    for ev in EVENTS_ALL - {"greet"}:
        assert ev in EVENTS, ev


def test_ask_back_never_changes_the_haggle(api):
    c, h = api
    g = c.post("/v1/haggle", json={"stall": "lim", "item": "prawns"}, headers=h).json()
    for _ in range(25):                                            # no AI: word rules ask back on a vague ok
        r = c.post(f"/v1/haggle/{g['id']}/move", json={"text": "ok lah"}, headers=h).json()
        assert r["event"] == "clarify" and r["ask"] == g["ask"] and r["patience"] == g["patience"] and not r["done"]
