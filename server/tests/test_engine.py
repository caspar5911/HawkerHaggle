import pytest

from hh.engine import Haggle, Item, Personality, nice

FISH = Item("pomfret", "Fresh pomfret", fair=15.0, ask=22.0, floor=13.0)
SOFT = Personality(stubborn=0.3, flattery=0.8, temper=0.3, callback=0.8)
HARD = Personality(stubborn=0.9, flattery=0.1, temper=0.8, callback=0.1)


def test_nice_prices():
    assert nice(13.26) == 13.5 and nice(13.2) == 13.0 and nice(23.4) == 23.0


def test_paying_the_asking_price_is_a_one_star_deal():
    h = Haggle(FISH, SOFT)
    out = h.move("accept")
    assert out.done and out.result == "deal" and out.deal == 22.0 and out.stars == 1 and out.saved == 0


def test_offer_at_or_above_ask_deals_at_the_ask_never_more():
    h = Haggle(FISH, SOFT)
    out = h.move("offer", 30)
    assert out.deal == 22.0


def test_counter_offers_come_down_but_never_below_the_secret_floor():
    h = Haggle(FISH, HARD, seed=1)
    asks = [h.s.ask]
    for _ in range(8):
        out = h.move("offer", 10.0)                  # stubbornly low, but not insulting (>= 70% of floor)
        if out.done:
            break
        asks.append(out.ask)
    assert all(a >= nice(FISH.floor * 0.9) for a in asks)
    assert asks == sorted(asks, reverse=True)       # never goes back up


def test_a_patient_player_can_reach_three_stars():
    h = Haggle(FISH, SOFT, seed=3)
    h.move("compliment")
    h.move("regular")
    out = None
    for _ in range(10):
        out = h.move("offer", nice(h.floor_now()))
        if out.done:
            break
    assert out.result == "deal" and out.stars == 3 and out.saved > 0.35


def test_lowballing_insults_and_burns_patience():
    h = Haggle(FISH, HARD)
    out = h.move("offer", 3.0)
    assert out.event == "insulted" and h.s.patience < 80 and h.s.mood < 0


def test_rudeness_and_running_out_of_patience_ends_the_haggle():
    h = Haggle(FISH, HARD)
    out = None
    for _ in range(5):
        out = h.move("rude")
        if out.done:
            break
    assert out.done and out.result == "refused" and out.event == "refuse" and out.stars == 0


def test_tactics_work_once_then_count_as_smalltalk():
    h = Haggle(FISH, SOFT, seed=2)
    first = h.move("bulk")
    assert first.event == "bulk" and h.s.qty == 2
    assert h.move("bulk").event == "smalltalk"


def test_compliments_wear_off():
    h = Haggle(FISH, SOFT)
    assert h.move("compliment").event == "flattered"
    assert h.move("compliment").event == "flattered"
    assert h.move("compliment").event == "flattery_tired"


def test_walking_away_either_gets_a_callback_or_ends():
    called = [Haggle(FISH, SOFT, seed=s).move("walk").event for s in range(20)]
    assert "callback" in called
    h = Haggle(FISH, HARD, seed=0)
    out = h.move("walk")
    assert out.event in ("callback", "letgo")
    if out.event == "letgo":
        assert out.done and out.result == "walked"


def test_same_seed_same_story():
    a, b = Haggle(FISH, SOFT, seed=7), Haggle(FISH, SOFT, seed=7)
    moves = [("competitor", None), ("offer", 12), ("walk", None), ("offer", 14)]
    assert [a.move(*m).to_dict() for m in moves] == [b.move(*m).to_dict() for m in moves]


def test_suggestions_never_reveal_the_floor_and_skip_used_tactics():
    h = Haggle(FISH, SOFT, seed=4)
    sug = h.suggestions()
    assert len(sug) == 3 and [s["move"] for s in sug[:2]] == ["offer", "offer"]
    assert sug[0]["price"] == nice(22 * 0.6) and sug[1]["price"] == nice(22 * 0.82)
    for t in ("competitor", "bulk", "regular"):
        h.move(t)
    h.move("compliment"); h.move("compliment")
    assert h.suggestions()[2]["move"] == "smalltalk"


def test_garbage_input_is_harmless():
    h = Haggle(FISH, SOFT)
    assert h.move("offer", float("nan")).event == "confused"
    assert h.move("hack the planet").event == "smalltalk"
    assert h.move("offer", -5).event == "confused"
    h.move("accept")
    assert h.move("offer", 1).event == "over"


@pytest.mark.parametrize("seed", range(30))
def test_every_haggle_ends_within_the_round_limit(seed):
    import random
    rnd = random.Random(seed)
    h = Haggle(FISH, Personality(*(rnd.random() for _ in range(4))), seed=seed)
    for _ in range(20):
        kind = rnd.choice(["offer", "compliment", "competitor", "bulk", "smalltalk", "walk"])
        out = h.move(kind, rnd.uniform(5, 25) if kind == "offer" else None)
        if out.done:
            break
    assert h.s.done and h.s.rounds <= 12
    if h.s.result == "deal":
        assert h.s.deal >= nice(FISH.floor * 0.9) - 0.01


def test_can_cheaper_gives_a_little_then_asks_for_a_number():
    h = Haggle(FISH, SOFT, seed=1)
    first = h.move("plead")
    assert first.event == "plead" and h.s.ask < FISH.ask
    h.move("plead")
    assert h.move("plead").event == "plead_no"
    assert h.s.ask >= nice(h.floor_now())
