"""The haggling engine: plain code that owns every number. The AI never decides prices.

A session is one haggle over one item with one stallholder. Each move returns an Outcome: an `event` (what
happened, used to pick or write the stallholder's line), the current asking price, and whether it's over.
All randomness comes from a seeded RNG, so a session replays exactly in tests."""
from __future__ import annotations

import math
import random
from dataclasses import asdict, dataclass, field

MOVES = ("offer", "budget", "plead", "pity", "flirt", "compliment", "competitor", "bulk", "one", "regular", "smalltalk", "rude", "walk",
         "accept")
ONCE = ("competitor", "bulk", "regular")    # tactics that only work once per haggle
MIN_GIVE = 0.1      # the least share of the gap a fair (not insulting) offer moves her, even when cross
MAX_ROUNDS = 40     # a safety net only: patience (shown on screen) is the real limit and always runs out first
# A firm price gets their real lowest only when earned by both goodwill and bargaining (see Haggle.firm_line).
FIRM_ROOM = 0.35    # unearned, a firm price must be this share of the bargaining range above their lowest
FIRM_COME = 0.7     # ...until they've come down this share of the range by real bargaining
FIRM_MOOD = 3.0     # ...and their mood is this good (the most it can be)


@dataclass(frozen=True)
class Personality:
    stubborn: float     # 0..1: how slowly they come down, and whether "next stall cheaper" works
    flattery: float     # 0..1: how much compliments soften them
    temper: float       # 0..1: how fast patience runs out
    callback: float     # 0..1: chance they call you back when you walk away
    kind: float = 0.5   # 0..1: how much a sad story ("no money, very hungry") softens them


@dataclass(frozen=True)
class Item:
    id: str
    name: str
    fair: float         # a fair price; 2 stars at or below
    ask: float          # opening asking price
    floor: float        # the stallholder's secret lowest price; 3 stars near it
    single: bool = False    # one of a kind (an antique, a pre-loved pair, a legendary item): "buy two" can't happen


@dataclass
class State:
    ask: float
    opening: float
    patience: float = 100.0
    mood: float = 0.0           # -3 .. +3
    rounds: int = 0
    qty: int = 1
    used: list = field(default_factory=list)
    compliments: int = 0
    pleads: int = 0
    pities: int = 0
    budget: float | None = None     # "I only have $16": the player's stated limit
    best_given: bool = False        # they already said their real best price for a too-small budget
    last_offer: float | None = None
    done: bool = False
    result: str = ""            # "deal", "walked", "refused"
    deal: float | None = None
    pending: float | None = None    # the stallholder agreed at this price; waiting for the player to confirm
    bulk_gave: float = 0.0          # what buying two took off the price per piece (back on if they want just one)


@dataclass
class Outcome:
    event: str
    ask: float
    done: bool = False
    result: str = ""
    deal: float | None = None
    offer: float | None = None
    stars: int = 0
    saved: float = 0.0          # fraction below the opening price
    pending: float | None = None

    def to_dict(self) -> dict:
        return asdict(self)


def nice(price: float) -> float:
    """Prices people actually say: 50-cent steps under $20, whole dollars above."""
    step = 0.5 if price < 20 else 1.0
    return round(round(price / step) * step, 2)


def nice_up(price: float) -> float:
    """The nearest price people say that is not below `price`."""
    step = 0.5 if price < 20 else 1.0
    return round(math.ceil(round(price / step, 6)) * step, 2)


def clamp(x: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, x))


class Haggle:
    def __init__(self, item: Item, persona: Personality, seed: int = 0, state: State | None = None):
        self.item, self.p = item, persona
        self.rng = random.Random(seed)
        self.s = state or State(ask=item.ask, opening=item.ask)

    # ------------------------------------------------------------------ helpers
    def floor_now(self) -> float:
        """Their real lowest price right now: a good mood shaves a little off, buying two shaves more."""
        f = self.item.floor * (1 - 0.02 * self.s.mood) * (0.95 if self.s.qty > 1 else 1.0)
        return max(f, self.item.floor * 0.9)

    def firm_line(self) -> float:
        """The lowest firm price ("this is my final", "I only have $X", the same number twice) they'll say yes to.
        Being firm only gets their real lowest price once it's earned: they're in a good mood AND they have already
        come down a good way by real bargaining (either one alone isn't enough). Rushing to a firm number, or knowing the number from last time,
        gets a higher "best price" (and that one is final)."""
        f = self.floor_now()
        come = clamp((self.item.ask - self.s.ask) / max(self.item.ask - self.item.floor, 0.01), 0.0, 1.0)
        m = FIRM_ROOM * max(clamp(1 - come / FIRM_COME, 0.0, 1.0), clamp(1 - self.s.mood / FIRM_MOOD, 0.0, 2.0))
        return f + (self.item.ask - self.item.floor) * m

    def _tire(self, amount: float) -> None:
        self.s.patience -= amount * (0.5 + self.p.temper)

    def _concede(self, toward: float, share: float) -> None:
        """Move the asking price `share` of the way toward `toward`, never below the floor, and never again once
        they've said their real best price (a sob story or a compliment afterwards doesn't change that)."""
        if self.s.best_given:
            return
        f = self.floor_now()
        target = max(toward, f)
        new = nice(self.s.ask - (self.s.ask - target) * clamp(share, 0.0, 1.0))
        self.s.ask = max(new, nice(f)) if new < self.s.ask else self.s.ask

    def _finish(self, result: str, deal: float | None = None) -> None:
        self.s.done, self.s.result, self.s.deal = True, result, deal

    def stars(self) -> int:
        if self.s.result != "deal" or self.s.deal is None:
            return 0
        if self.s.deal <= self.item.floor * 1.06:
            return 3
        # 2 stars: a fair price, or a real discount (a fifth off the item's price); 1: any deal, even at full price
        return 2 if self.s.deal <= self.item.fair or self.s.deal <= self.item.ask * 0.8 + 1e-9 else 1

    def _out(self, event: str, offer: float | None = None) -> Outcome:
        saved = 1 - self.s.deal / self.s.opening if self.s.deal else 0.0
        return Outcome(event=event, ask=self.s.ask, done=self.s.done, result=self.s.result, deal=self.s.deal,
                       offer=offer, stars=self.stars(), saved=round(saved, 3), pending=self.s.pending)

    def _agree(self, price: float, offer: float | None = None) -> Outcome:
        """The stallholder says yes at `price`; the haggle ends only when the player confirms."""
        self.s.pending = price
        return self._out("confirm", offer)

    # ------------------------------------------------------------------ moves
    def can_call_back(self) -> bool:
        """Could they call a leaving customer back with one final-final price? Only with real room left, not after
        they've already given their best price, and not for someone who was rude."""
        f = self.floor_now()
        return not self.s.done and not self.s.best_given and self.s.ask - f > f * 0.04 and self.s.mood > -1.5

    def move(self, kind: str, price: float | None = None, call_back: bool | None = None) -> Outcome:
        if self.s.done:
            return self._out("over")
        ask_start = self.s.ask         # a no-sale ending keeps the price from before this move
        if kind == "buy":
            # The app's "OK lah, $X" button after its own "Confirm $X" tap: the player has already confirmed.
            deal, self.s.pending = self.s.pending if self.s.pending is not None else self.s.ask, None
            self._finish("deal", deal)
            return self._out("accept", deal)
        if self.s.pending is not None and (kind == "accept" or (
                kind in ("offer", "budget") and price is not None and math.isfinite(price)
                and nice(price) >= self.s.pending)):
            kind = "confirm"        # "OK lah" or the agreed price again, while a deal waits: that's a yes
        if kind == "confirm":
            if self.s.pending is None:
                kind = "smalltalk"
            else:
                deal, self.s.pending = self.s.pending, None
                self._finish("deal", deal)
                return self._out("accept", deal)
        if kind == "cancel":
            if self.s.pending is None:
                kind = "smalltalk"
            else:
                # "Wait, not yet": the price they agreed stays on the table, but it costs a little patience.
                self.s.ask, self.s.pending = min(self.s.ask, self.s.pending), None
                self._tire(6)
                if self.s.patience <= 0:
                    self.s.ask = ask_start
                    self._finish("refused")
                    return self._out("refuse")
                return self._out("unsure")
        if self.s.pending is not None:
            # Any other move while a deal waits for confirmation: the player is still bargaining.
            self.s.ask, self.s.pending = min(self.s.ask, self.s.pending), None
        if kind not in MOVES:
            kind = "smalltalk"
        if kind in ONCE and kind in self.s.used:
            kind = "offer" if price is not None else "smalltalk"   # "2 for $40" again: still an offer
        self.s.rounds += 1
        if kind == "walk":
            out = self._walk(call_back)
        else:
            out = getattr(self, f"_{kind}")(price) if kind in ("offer", "budget", "bulk") else getattr(self, f"_{kind}")()
        if out.event == "confirm":
            return out              # a deal on the table always gets its confirmation step
        if not self.s.done and (self.s.patience <= 0 or self.s.rounds >= MAX_ROUNDS):
            self.s.ask = ask_start      # she's refusing: the price doesn't improve on the way out
            self._finish("refused")
            return self._out("refuse")
        return out

    def _budget(self, price: float | None) -> Outcome:
        """"I only have $16": a firm limit, not an opening bid."""
        if price is not None and math.isfinite(price) and price > 0:
            self.s.budget = nice(price)
        return self._offer(price, firm=True)

    def _offer(self, price: float | None, firm: bool = False) -> Outcome:
        if price is None or not math.isfinite(price) or price <= 0:
            self._tire(6)
            return self._out("confused")
        x = nice(price)
        # Saying the same number again is pressure, not a promise: if they've earned it (her firm line is at or
        # below it), holding firm gets a yes; otherwise she just holds her price. Only a stated limit ("I only have
        # $16") makes her name a best price for the rest of the haggle.
        repeat = not firm and x == self.s.last_offer
        self.s.last_offer = x
        f = self.floor_now()
        if x >= self.s.ask:
            return self._agree(self.s.ask, x)
        # How far below their current ask they'll still say yes: a share of the item's whole bargaining range
        # (not of the remaining gap, or an offer at the floor could never be accepted).
        give = (self.item.ask - self.item.floor) * clamp(0.25 + 0.06 * self.s.mood - 0.15 * self.p.stubborn, 0.05, 0.5)
        if self.s.best_given and x < self.s.ask:
            self._tire(9)
            return self._out("final", x)            # they already said their real best price
        if x >= f and (((firm or repeat) and x >= self.firm_line()) or x >= self.s.ask - give):
            return self._agree(x, x)                # a firm limit they can live with: yes
        if x < f * 0.7:
            self._tire(22)
            self.s.mood = clamp(self.s.mood - 1, -3, 3)
            return self._out("insulted", x)
        if repeat:
            self._tire(9)                           # the same number again, too early: she holds, a bit impatient
            return self._out("same_offer", x)
        if firm:
            # A real limit below what they'll do: no more $1 steps. Once, they say their best price (their real
            # lowest only if the customer has earned it), and it's final for this haggle.
            self._tire(9)
            if not self.s.best_given:
                self.s.best_given = True
                best = nice_up(self.firm_line())
                if best < self.s.ask:
                    self.s.ask = best
                    return self._out("budget_best", x)
            return self._out("final", x)
        before = self.s.ask
        # an offer that isn't an insult always moves her a little, however cross she is (crossness costs you, it
        # never freezes the haggle)
        self._concede(x, max(MIN_GIVE, 0.25 + 0.08 * self.s.mood - 0.15 * self.p.stubborn))
        self._tire(7)
        return self._out("final" if self.s.ask >= before else "counter", x)

    def _pity(self, _=None) -> Outcome:
        """A sad story. Soft-hearted stallholders soften once; nobody goes below their secret lowest price."""
        self.s.pities += 1
        if self.s.pities > 1:
            self._tire(8 + 10 * (1 - self.p.kind))
            return self._out("pity_tired")
        self.s.mood = clamp(self.s.mood + 2 * self.p.kind, -3, 3)
        self._concede(self.floor_now(), 0.35 * self.p.kind)
        self._tire(3)
        return self._out("pity")

    def _compliment(self, _=None) -> Outcome:
        self.s.compliments += 1
        if self.s.compliments > 2:
            self._tire(12)
            return self._out("flattery_tired")
        self.s.mood = clamp(self.s.mood + 1.5 * self.p.flattery, -3, 3)
        self._concede(self.floor_now(), 0.12 * self.p.flattery)
        self._tire(3)
        return self._out("flattered")

    def _plead(self, _=None) -> Outcome:
        """'Can cheaper?' with no number: a small give the first couple of times, then they want a real offer."""
        self.s.pleads += 1
        if self.s.pleads > 2:
            self._tire(10)
            return self._out("plead_no")
        before = self.s.ask
        self._concede(self.floor_now(), (0.18 if self.s.pleads == 1 else 0.1) * (1.1 - self.p.stubborn))
        self._tire(6)
        return self._out("plead" if self.s.ask < before else "plead_no")

    def _competitor(self, _=None) -> Outcome:
        """"The next stall is cheaper": a skill, not luck. It works while her price is still well above her lowest
        (she'd rather not lose the sale); once she has come down a good way it only annoys her. Stubborn ones put
        up with it for less of the way."""
        self.s.used.append("competitor")
        come = (self.item.ask - self.s.ask) / max(self.item.ask - self.item.floor, 0.01)
        if come <= 0.6 - 0.4 * self.p.stubborn:
            self._concede(self.floor_now(), 0.3)
            self._tire(5)
            return self._out("competitor_drop")
        self.s.mood = clamp(self.s.mood - 0.5, -3, 3)
        self._tire(14)
        return self._out("competitor_annoyed")

    def _bulk(self, price: float | None = None) -> Outcome:
        self.s.used.append("bulk")
        if self.item.single:
            # There's only one: no two-piece price. Asked again, it's a plain offer (or chat), like any used tactic.
            self._tire(3)
            return self._out("only_one")
        self.s.qty = 2
        before = self.s.ask
        self._concede(self.floor_now(), 0.35 * (1.2 - self.p.stubborn))
        self.s.bulk_gave = before - self.s.ask
        self._tire(4)
        if price is not None:
            return self._offer(price)        # "2 for $40": $20 each, judged against the two-piece price
        return self._out("bulk")

    def _one(self, _=None) -> Outcome:
        """"Actually, just one": back to a single piece. What buying two took off goes back on the price (never
        below their lowest for one), so switching back and forth wins nothing. They may still ask about two later."""
        if self.s.qty == 1:
            return self._smalltalk()
        self.s.qty = 1
        self.s.used.remove("bulk")
        self.s.ask = min(self.s.opening, max(nice(self.s.ask + self.s.bulk_gave), nice(self.floor_now())))
        self.s.bulk_gave = 0.0
        self._tire(4)
        return self._out("back_to_one")

    def _flirt(self, _=None) -> Outcome:
        """Flirting or creepy talk: they laugh it off and steer back to business. It doesn't help."""
        self.s.mood = clamp(self.s.mood - 0.5, -3, 3)
        self._tire(8)
        return self._out("deflect")

    def side(self, kind: str) -> None:
        """The mood part of a second thing said in the same message ("so nice, 20 can?"): no round, no event,
        and the same limits as saying it on its own (compliments wear off, a regular or a sad story counts once)."""
        if self.s.done:
            return
        if kind == "compliment" and self.s.compliments < 2:
            self.s.compliments += 1
            self.s.mood = clamp(self.s.mood + 1.0 * self.p.flattery, -3, 3)
        elif kind == "regular" and "regular" not in self.s.used:
            self.s.used.append("regular")
            self.s.mood = clamp(self.s.mood + 0.7, -3, 3)
        elif kind == "pity" and self.s.pities < 1:
            self.s.pities += 1
            self.s.mood = clamp(self.s.mood + 1.5 * self.p.kind, -3, 3)
        elif kind == "flirt":
            self.s.mood = clamp(self.s.mood - 0.5, -3, 3)
            self._tire(4)
        elif kind == "rude":
            self.s.mood = clamp(self.s.mood - 1, -3, 3)
            self._tire(12)

    def _regular(self, _=None) -> Outcome:
        self.s.used.append("regular")
        self.s.mood = clamp(self.s.mood + 1, -3, 3)
        self._concede(self.floor_now(), 0.1)
        self._tire(4)
        return self._out("regular")

    def _smalltalk(self, _=None) -> Outcome:
        self.s.mood = clamp(self.s.mood + 0.3, -3, 3)
        self._tire(5)
        return self._out("smalltalk")

    def _rude(self, _=None) -> Outcome:
        self.s.mood = clamp(self.s.mood - 2, -3, 3)
        self._tire(30)
        return self._out("rude")

    def _walk(self, call_back: bool | None = None) -> Outcome:
        """Walking away. If it's the right moment (the AI judges the conversation; without it, personality and mood
        decide), they call you back once with a final-final price, which really is final: walk again and they let
        you go."""
        f = self.floor_now()
        if self.can_call_back():
            yes = call_back if call_back is not None else \
                self.rng.random() < self.p.callback * (0.6 + 0.15 * self.s.mood)
            if yes:
                self.s.ask = max(nice((self.s.ask + f) / 2), nice(f))
                self.s.best_given = True
                self._tire(10)
                return self._out("callback")
        self._finish("walked")
        return self._out("letgo")

    def _accept(self, _=None) -> Outcome:
        return self._agree(self.s.ask, self.s.ask)

    # ------------------------------------------------------------------ tap mode
    def suggestions(self) -> list[dict]:
        """Three moves for tap mode: two offers (bold, safer) and one tactic. Amounts come from the asking
        price only, so they never reveal the secret floor."""
        if self.s.done or self.s.pending is not None:
            return []           # a deal is waiting for confirmation: the app shows Deal / Not yet instead
        a = self.s.ask
        # Amounts vary a little from turn to turn so they don't feel mechanical (never from the secret floor).
        r = self.s.rounds % 5
        bold, safer = nice(a * (0.6, 0.57, 0.63, 0.55, 0.62)[r]), nice(a * (0.74, 0.72, 0.76, 0.7, 0.75)[r])
        if safer >= a:
            safer = nice(a - (0.5 if a < 20 else 1))
        offers = [bold, safer]
        lo = self.s.last_offer
        if lo is not None and lo < a:
            # After an offer of their own, the player never goes backwards, and the safer offer comes a third of the
            # way to her price, so following it closes the gap (from her price, it chased her down and never met).
            # Never their last number exactly: the same number twice means a firm price.
            step = 0.5 if a < 20 else 1.0
            safer = nice(lo + (a - lo) / 3)
            if safer <= lo or safer >= a:
                safer = a                       # nothing left in between: her price
            bold = max(bold, nice(lo + step))
            offers = [bold, safer] if bold < safer else [safer]
        out = [{"move": "offer", "price": x} for x in offers]
        tactics = [m for m in ("compliment", "competitor", "bulk", "regular")
                   if m not in self.s.used and not (m == "compliment" and self.s.compliments >= 2)
                   and not (m == "bulk" and self.item.single)]
        out.append({"move": self.rng.choice(tactics) if tactics else "smalltalk", "price": None})
        return out
