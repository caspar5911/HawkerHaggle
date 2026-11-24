"""The haggling engine: plain code that owns every number. The AI never decides prices.

A session is one haggle over one item with one stallholder. Each move returns an Outcome: an `event` (what
happened, used to pick or write the stallholder's line), the current asking price, and whether it's over.
All randomness comes from a seeded RNG, so a session replays exactly in tests."""
from __future__ import annotations

import math
import random
from dataclasses import asdict, dataclass, field

MOVES = ("offer", "plead", "compliment", "competitor", "bulk", "regular", "smalltalk", "rude", "walk", "accept")
ONCE = ("competitor", "bulk", "regular")    # tactics that only work once per haggle
MAX_ROUNDS = 12


@dataclass(frozen=True)
class Personality:
    stubborn: float     # 0..1: how slowly they come down, and whether "next stall cheaper" works
    flattery: float     # 0..1: how much compliments soften them
    temper: float       # 0..1: how fast patience runs out
    callback: float     # 0..1: chance they call you back when you walk away


@dataclass(frozen=True)
class Item:
    id: str
    name: str
    fair: float         # a fair price; 2 stars at or below
    ask: float          # opening asking price
    floor: float        # the stallholder's secret lowest price; 3 stars near it


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
    last_offer: float | None = None
    done: bool = False
    result: str = ""            # "deal", "walked", "refused"
    deal: float | None = None


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

    def to_dict(self) -> dict:
        return asdict(self)


def nice(price: float) -> float:
    """Prices people actually say: 50-cent steps under $20, whole dollars above."""
    step = 0.5 if price < 20 else 1.0
    return round(round(price / step) * step, 2)


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

    def _tire(self, amount: float) -> None:
        self.s.patience -= amount * (0.5 + self.p.temper)

    def _concede(self, toward: float, share: float) -> None:
        """Move the asking price `share` of the way toward `toward`, never below the floor."""
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
        return 2 if self.s.deal <= self.item.fair else 1

    def _out(self, event: str, offer: float | None = None) -> Outcome:
        saved = 1 - self.s.deal / self.s.opening if self.s.deal else 0.0
        return Outcome(event=event, ask=self.s.ask, done=self.s.done, result=self.s.result, deal=self.s.deal,
                       offer=offer, stars=self.stars(), saved=round(saved, 3))

    # ------------------------------------------------------------------ moves
    def move(self, kind: str, price: float | None = None) -> Outcome:
        if self.s.done:
            return self._out("over")
        if kind not in MOVES:
            kind = "smalltalk"
        if kind in ONCE and kind in self.s.used:
            kind = "smalltalk"
        self.s.rounds += 1
        out = getattr(self, f"_{kind}")(price) if kind == "offer" else getattr(self, f"_{kind}")()
        if not self.s.done and self.s.patience <= 0:
            self._finish("refused")
            return self._out("refuse")
        if not self.s.done and self.s.rounds >= MAX_ROUNDS:
            self._finish("refused")
            return self._out("refuse")
        return out

    def _offer(self, price: float | None) -> Outcome:
        if price is None or not math.isfinite(price) or price <= 0:
            self._tire(6)
            return self._out("confused")
        x = nice(price)
        self.s.last_offer = x
        f = self.floor_now()
        if x >= self.s.ask:
            self._finish("deal", self.s.ask)
            return self._out("accept", x)
        # How far below their current ask they'll still say yes: a share of the item's whole bargaining range
        # (not of the remaining gap, or an offer at the floor could never be accepted).
        give = (self.item.ask - self.item.floor) * clamp(0.25 + 0.06 * self.s.mood - 0.15 * self.p.stubborn, 0.05, 0.5)
        if x >= f and x >= self.s.ask - give:
            self._finish("deal", x)
            return self._out("accept", x)
        if x < f * 0.7:
            self._tire(22)
            self.s.mood = clamp(self.s.mood - 1, -3, 3)
            return self._out("insulted", x)
        before = self.s.ask
        self._concede(x, 0.25 + 0.08 * self.s.mood - 0.15 * self.p.stubborn)
        self._tire(7)
        return self._out("final" if self.s.ask >= before else "counter", x)

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
        self.s.used.append("competitor")
        if self.rng.random() > self.p.stubborn:
            self._concede(self.floor_now(), 0.3)
            self._tire(5)
            return self._out("competitor_drop")
        self.s.mood = clamp(self.s.mood - 0.5, -3, 3)
        self._tire(14)
        return self._out("competitor_annoyed")

    def _bulk(self, _=None) -> Outcome:
        self.s.used.append("bulk")
        self.s.qty = 2
        self._concede(self.floor_now(), 0.35 * (1.2 - self.p.stubborn))
        self._tire(4)
        return self._out("bulk")

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

    def _walk(self, _=None) -> Outcome:
        f = self.floor_now()
        room = self.s.ask - f
        if room > f * 0.04 and self.rng.random() < self.p.callback * (0.6 + 0.15 * self.s.mood):
            self.s.ask = max(nice((self.s.ask + f) / 2), nice(f))
            self._tire(10)
            return self._out("callback")
        self._finish("walked")
        return self._out("letgo")

    def _accept(self, _=None) -> Outcome:
        self._finish("deal", self.s.ask)
        return self._out("accept", self.s.ask)

    # ------------------------------------------------------------------ tap mode
    def suggestions(self) -> list[dict]:
        """Three moves for tap mode: two offers (bold, safer) and one tactic. Amounts come from the asking
        price only, so they never reveal the secret floor."""
        if self.s.done:
            return []
        a = self.s.ask
        bold, safer = nice(a * 0.6), nice(a * 0.82)
        if safer >= a:
            safer = nice(a - (0.5 if a < 20 else 1))
        out = [{"move": "offer", "price": bold}, {"move": "offer", "price": safer}]
        tactics = [m for m in ("compliment", "competitor", "bulk", "regular")
                   if m not in self.s.used and not (m == "compliment" and self.s.compliments >= 2)]
        out.append({"move": self.rng.choice(tactics) if tactics else "smalltalk", "price": None})
        return out
