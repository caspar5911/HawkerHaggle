import pytest

from hh.engine import Haggle, Item, Personality, nice

FISH = Item("pomfret", "Fresh pomfret", fair=15.0, ask=22.0, floor=13.0)
SOFT = Personality(stubborn=0.3, flattery=0.8, temper=0.3, callback=0.8)
HARD = Personality(stubborn=0.9, flattery=0.1, temper=0.8, callback=0.1)


def test_nice_prices():
    assert nice(13.26) == 13.5 and nice(13.2) == 13.0 and nice(23.4) == 23.0


def test_paying_the_asking_price_is_a_one_star_deal():
    h = Haggle(FISH, SOFT)
    agreed = h.move("accept")
    assert agreed.event == "confirm" and not agreed.done and agreed.pending == 22.0   # nothing ends without a yes
    out = h.move("confirm")
    assert out.done and out.result == "deal" and out.deal == 22.0 and out.stars == 1 and out.saved == 0


def test_offer_at_or_above_ask_deals_at_the_ask_never_more():
    h = Haggle(FISH, SOFT)
    out = h.move("offer", 30)
    assert out.pending == 22.0
    assert h.move("confirm").deal == 22.0


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
    h.move("offer", 11)                             # real bargaining first: a bold offer, then up step by step
    h.move("regular")
    h.move("compliment")
    h.move("offer", 12)
    out = None
    for _ in range(10):
        out = h.move("offer", nice_up(h.floor_now()))
        if out.event == "confirm":
            out = h.move("confirm")
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
    assert h.move("confirm").event == "smalltalk"            # nothing to confirm yet
    h.move("accept")
    h.move("confirm")
    assert h.move("offer", 1).event == "over"


@pytest.mark.parametrize("seed", range(30))
def test_every_haggle_ends_within_the_round_limit(seed):
    import random
    rnd = random.Random(seed)
    h = Haggle(FISH, Personality(*(rnd.random() for _ in range(4))), seed=seed)
    for _ in range(20):
        kind = rnd.choice(["offer", "compliment", "competitor", "bulk", "smalltalk", "walk"])
        out = h.move(kind, rnd.uniform(5, 25) if kind == "offer" else None)
        if out.event == "confirm":
            out = h.move("confirm")
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


def test_not_yet_keeps_the_agreed_price_and_bargaining_goes_on():
    h = Haggle(FISH, SOFT)
    agreed = h.move("offer", 21)
    assert agreed.event == "confirm" and agreed.pending == 21
    out = h.move("cancel")
    assert out.event == "unsure" and not out.done and h.s.ask == 21 and h.s.pending is None
    assert h.suggestions()                                     # back to normal bargaining
    again = h.move("offer", 20)
    assert again.event in ("confirm", "counter", "final")


def test_a_new_move_while_a_deal_waits_cancels_it_first():
    h = Haggle(FISH, SOFT)
    assert h.move("offer", 21).event == "confirm"
    assert h.suggestions() == []                               # app shows Deal / Not yet
    h.move("walk")
    assert h.s.pending is None


from hh.engine import nice_up  # noqa: E402

KIND = Personality(stubborn=0.3, flattery=0.5, temper=0.3, callback=0.5, kind=0.85)
GRUFF = Personality(stubborn=0.75, flattery=0.2, temper=0.6, callback=0.35, kind=0.25)


def test_a_budget_she_can_live_with_is_a_yes():
    h = Haggle(FISH, SOFT)
    out = h.move("budget", 17)                      # floor is 13; straight away, a firm 17 is fine
    assert out.event == "confirm" and out.pending == 17


def test_being_firm_only_gets_her_real_lowest_price_once_it_is_earned():
    rushed = Haggle(FISH, SOFT)
    assert rushed.move("offer", 13).event == "counter"
    out = rushed.move("offer", 13)                  # her lowest, twice, straight away: a higher "best price"
    assert out.event == "budget_best" and rushed.s.ask > FISH.floor * 1.06 and rushed.s.best_given
    assert rushed.move("offer", 13).event == "final"
    earned = Haggle(FISH, SOFT)
    for kind, price in (("compliment", None), ("offer", 11), ("regular", None), ("compliment", None),
                        ("offer", 12), ("offer", 13)):
        out = earned.move(kind, price)
    assert earned.firm_line() <= 13 < rushed.firm_line()
    assert out.event == "confirm" or earned.move("offer", 13).event == "confirm"
    assert Haggle(FISH, SOFT).firm_line() > FISH.floor


def test_a_budget_a_bit_too_small_gets_her_best_price_once_then_no_more_dollar_steps():
    h = Haggle(FISH, SOFT)
    first = h.move("budget", 11)                    # below the floor (13), not insulting
    assert first.event == "budget_best" and h.s.ask == nice_up(h.firm_line()) and h.s.ask > FISH.floor
    best = h.s.ask
    for _ in range(3):                              # "I only have 11" again and again: she holds
        again = h.move("budget", 11)
        if again.done:
            break
        assert again.event == "final" and h.s.ask == best
    h2 = Haggle(FISH, SOFT)
    h2.move("budget", 11)
    assert h2.move("offer", h2.s.ask - 1).event == "final"     # her best really is her best


def test_repeating_the_same_offer_counts_as_a_firm_limit():
    h = Haggle(FISH, SOFT)
    h.move("offer", 12)
    assert h.move("offer", 12).event in ("budget_best", "confirm")


def test_pity_softens_kind_stallholders_more_and_wears_off():
    kind, gruff = Haggle(FISH, KIND), Haggle(FISH, GRUFF)
    kind.move("pity"); gruff.move("pity")
    assert kind.s.ask < gruff.s.ask <= FISH.ask
    assert kind.move("pity").event == "pity_tired"
    for _ in range(5):
        kind.move("pity")
    assert kind.s.ask >= nice(FISH.floor * 0.9)     # never below the secret minimum


def test_nice_up_never_rounds_below():
    assert nice_up(13.01) == 13.5 and nice_up(13.0) == 13.0 and nice_up(20.2) == 21.0


def test_two_for_a_total_is_judged_as_a_per_piece_offer_in_one_round():
    h = Haggle(FISH, SOFT)
    out = h.move("bulk", 14)                        # "2 for $28" -> $14 each
    assert h.s.qty == 2 and h.s.rounds == 1
    assert out.event in ("confirm", "counter", "final", "budget_best") and out.offer == 14
    again = h.move("bulk", 13.5)                    # bulk only once, but a price is still an offer
    assert again.event in ("confirm", "counter", "final", "insulted", "budget_best")


def test_side_effects_respect_the_same_limits():
    h = Haggle(FISH, SOFT)
    for _ in range(6):
        h.side("compliment")
    assert h.s.compliments == 2                     # can't farm mood with "so nice, 20 can?" x 6
    mood = h.s.mood
    h.side("regular"); h.side("regular")
    assert h.s.mood == min(3, mood + 0.7)
    assert h.move("compliment").event == "flattery_tired"     # the side compliments counted
    rounds = h.s.rounds
    h.side("pity")
    assert h.s.rounds == rounds                     # side effects never use a round


def test_flirting_gets_deflected_and_does_not_help():
    h = Haggle(FISH, SOFT)
    out = h.move("flirt")
    assert out.event == "deflect" and h.s.ask == FISH.ask and h.s.mood < 0


def test_once_she_says_her_best_nothing_moves_her_lower():
    for persona in (SOFT, KIND, GRUFF):
        h = Haggle(FISH, persona, seed=4)
        assert h.move("budget", 11).event == "budget_best"
        best = h.s.ask
        for kind in ("pity", "compliment", "plead", "regular", "competitor", "bulk", "walk"):
            if h.s.done:
                break
            h.move(kind)
            assert h.s.ask >= best, (kind, h.s.ask, best)


def test_walking_away_at_the_right_moment_gets_one_final_final_price():
    h = Haggle(FISH, SOFT)
    h.move("offer", 15)                              # some bargaining, a friendly chat
    out = h.move("walk", call_back=True)
    assert out.event == "callback" and not out.done and h.s.best_given
    final = h.s.ask
    assert final >= nice(h.floor_now()) and final < FISH.ask
    assert h.move("offer", final - 1).event == "final"   # final-final really is final
    assert h.move("walk", call_back=True).event == "letgo"   # and walking again ends it


def test_no_callback_when_the_moment_is_wrong_or_they_were_rude():
    h = Haggle(FISH, SOFT)
    assert h.move("walk", call_back=False).event == "letgo"
    h = Haggle(FISH, SOFT)
    h.move("rude")
    assert not h.can_call_back()
    assert h.move("walk", call_back=True).event == "letgo"


def test_a_refusal_never_comes_with_a_better_price():
    for seed in range(40):
        h = Haggle(FISH, HARD, seed=seed)
        last = h.s.ask
        for _ in range(12):
            out = h.move("offer", 10.0)
            if out.done:
                assert out.event == "refuse" and out.ask == last, (seed, last, out.ask)
                break
            last = out.ask
