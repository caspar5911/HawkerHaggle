"""Haggling should take skill: no fixed recipe gets the best price every time, but a player who builds goodwill and
bargains properly can still get there. Scripted players over every stall and item, with the real engine."""
import json
from pathlib import Path

import pytest

from hh.engine import Haggle, Item, Personality, nice

CONTENT = json.loads((Path(__file__).resolve().parents[2] / "content" / "stalls.json").read_text())
CASES = [(s, i) for s in CONTENT["stalls"] for i in s["items"]]


def play(stall, item, script, seed=0):
    """Plays `script` (a list of (move, price-or-function-of-ask)); confirms any deal on the table at once.
    Returns the stars (0 = no deal)."""
    h = Haggle(Item(**{k: item[k] for k in ("id", "name", "fair", "ask", "floor")}),
               Personality(**stall["personality"]), seed=seed)
    for kind, price in script:
        if h.s.done:
            break
        out = h.move(kind, price(h.s.ask) if callable(price) else price)
        if out.event == "confirm":
            out = h.move("confirm")
    if not h.s.done:
        out = h.move("accept")
        if out.event == "confirm":
            out = h.move("confirm")
    return h.stars() if h.s.done else 0


def lowball(item, share=0.75):
    return nice(item["floor"] * share)


RECIPES = {
    # Someone who knows her lowest price from last time just says it twice.
    "the floor, twice": lambda item: [("offer", item["floor"])] * 2,
    # A low number twice: she says her best price, and you take it.
    "a lowball, twice": lambda item: [("offer", lowball(item))] * 2,
    # "I only have $X" is firm in one message.
    "a low budget": lambda item: [("budget", lowball(item))],
    # Chatting for ages first, then the floor twice.
    "chat, then the floor": lambda item: [("smalltalk", None)] * 6 + [("offer", item["floor"])] * 2,
    "chat a lot, then the floor": lambda item: [("smalltalk", None)] * 9 + [("offer", item["floor"])] * 2,
    # Inching up from a lowball, number after number.
    "inch up, then the floor": lambda item: [("offer", lowball(item, 0.75 + 0.02 * k)) for k in range(8)]
    + [("offer", item["floor"])] * 2,
}


def skilled(item):
    """Goodwill first, then real bargaining from a bold offer up, and only then a firm price."""
    lo = lowball(item, 0.85)
    return [("compliment", None), ("offer", lo), ("regular", None), ("compliment", None),
            ("offer", nice((lo + item["floor"]) / 2)), ("offer", item["floor"]), ("offer", item["floor"])]


def no_goodwill(item):
    return [m for m in skilled(item) if m[0] not in ("compliment", "regular")]


def three_star_share(script_for, seeds=range(3)):
    results = [play(s, i, script_for(i), seed) for s, i in CASES for seed in seeds]
    return sum(r == 3 for r in results) / len(results)


@pytest.mark.parametrize("name", RECIPES)
def test_no_fixed_recipe_gets_the_best_price_every_time(name):
    assert three_star_share(RECIPES[name]) <= 0.2, name


def test_a_skilled_haggler_still_gets_the_best_price():
    assert three_star_share(skilled) >= 0.8


def test_bargaining_without_goodwill_rarely_gets_the_lowest_price():
    assert three_star_share(no_goodwill) <= 0.2
