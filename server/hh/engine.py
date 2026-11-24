"""The haggling engine: plain code that owns every number. The AI never decides prices.

A session is one haggle over one item with one stallholder. Each move returns an Outcome: an `event` (what
happened, used to pick or write the stallholder's line), the current asking price, and whether it's over.
All randomness comes from a seeded RNG, so a session replays exactly in tests."""
from __future__ import annotations

import math
import random
from dataclasses import asdict, dataclass, field

MOVES = ("offer", "budget", "plead", "pity", "compliment", "competitor", "bulk", "regular", "smalltalk", "rude", "walk", "accept")
ONCE = ("competitor", "bulk", "regular")    # tactics that only work once per haggle
MAX_ROUNDS = 12


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
                       offer=offer, stars=self.stars(), saved=round(saved, 3), pending=self.s.pending)

    def _agree(self, price: float, offer: float | None = None) -> Outcome:
        """The stallholder says yes at `price`; the haggle ends only when the player confirms."""
        self.s.pending = price
        return self._out("confirm", offer)

    # ------------------------------------------------------------------ moves
    def move(self, kind: str, price: float | None = None) -> Outcome:
        if self.s.done:
            return self._out("over")
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
                    self._finish("refused")
                    return self._out("refuse")
                return self._out("unsure")
        if self.s.pending is not None:
            # Any other move while a deal waits for confirmation: the player is still bargaining.
            self.s.ask, self.s.pending = min(self.s.ask, self.s.pending), None
        if kind not in MOVES:
            kind = "smalltalk"
        if kind in ONCE and kind in self.s.used:
            kind = "smalltalk"
        self.s.rounds += 1
        out = getattr(self, f"_{kind}")(price) if kind in ("offer", "budget") else getattr(self, f"_{kind}")()
        if out.event == "confirm":
            return out              # a deal on the table always gets its confirmation step
        if not self.s.done and self.s.patience <= 0:
            self._finish("refused")
            return self._out("refuse")
        if not self.s.done and self.s.rounds >= MAX_ROUNDS:
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
        firm = firm or x == self.s.last_offer       # saying the same number again means it
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
        if x >= f and (firm or x >= self.s.ask - give):
            return self._agree(x, x)                # a firm limit they can live with: yes
        if x < f * 0.7:
            self._tire(22)
            self.s.mood = clamp(self.s.mood - 1, -3, 3)
            return self._out("insulted", x)
        if firm:
            # A real limit below what they can do: no more $1 steps. Once, they say their real best price.
            self._tire(9)
            if not self.s.best_given:
                self.s.best_given = True
                best = nice_up(f)                   # honest: this really is the lowest they'll go
                if best < self.s.ask:
                    self.s.ask = best
                    return self._out("budget_best", x)
            return self._out("final", x)
        before = self.s.ask
        self._concede(x, 0.25 + 0.08 * self.s.mood - 0.15 * self.p.stubborn)
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
        return self._agree(self.s.ask, self.s.ask)

    # ------------------------------------------------------------------ tap mode
    def suggestions(self) -> list[dict]:
        """Three moves for tap mode: two offers (bold, safer) and one tactic. Amounts come from the asking
        price only, so they never reveal the secret floor."""
        if self.s.done or self.s.pending is not None:
            return []           # a deal is waiting for confirmation: the app shows Deal / Not yet instead
        a = self.s.ask
        bold, safer = nice(a * 0.6), nice(a * 0.82)
        if safer >= a:
            safer = nice(a - (0.5 if a < 20 else 1))
        out = [{"move": "offer", "price": bold}, {"move": "offer", "price": safer}]
        tactics = [m for m in ("compliment", "competitor", "bulk", "regular")
                   if m not in self.s.used and not (m == "compliment" and self.s.compliments >= 2)]
        out.append({"move": self.rng.choice(tactics) if tactics else "smalltalk", "price": None})
        return out
