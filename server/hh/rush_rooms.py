"""Hawker Rush co-op rooms: up to four friends share one hawker stall, each on their own phone.

The host's phone runs the shift (the game's rules live in the game); this is only a fast mailbox between the phones,
kept in memory. The host posts the shift's setup, then several times a second the actions it has applied so far
("frames": every tap, its own and its friends', with the tick it happened on), so every phone replays the same shift.
Friends post their taps, which the host plays. Each phone waits for news with a short long-poll.

No accounts: joining gives a random token for a seat in the room. Names are cleaned like leaderboard names, and the only
messages are game actions and a fixed set of cheers, so there is no free text to police. Rooms close after a few idle
minutes (or when the host leaves); sizes are capped. A server restart closes every room.
"""
from __future__ import annotations

import asyncio
import json
import re
import secrets
import time

from .arcade import clean_arcade_name

ROOM_IDLE = 10 * 60          # seconds without any message or pull before a room closes
MAX_ROOMS = 100
MAX_PLAYERS = 4
MAX_LOG = 4000               # messages kept per room (a 2-minute shift is ~1,000)
MAX_MESSAGE_BYTES = 4 * 1024
MAX_PULL = 600               # messages returned by one pull
WAIT = 10                    # seconds a pull waits for news (short: proxies on the way may cut long requests)
MAX_TICKS = 30 * 60 * 30
CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no 0/O or 1/I
KINDS = {"base", "add", "cook", "serve", "bin-dish", "bin-burnt", "cook-dish", "flip", "take"}
EMOTES = {"nice", "help", "drinks", "cooking", "hurry", "thanks"}
HOST_ONLY = {"start", "frames", "pause", "resume", "over", "lobby", "day"}
TOKEN = re.compile(r"^[A-Za-z0-9_-]{16,40}$")
WORD = re.compile(r"^[a-zA-Z][a-zA-Z0-9-]{0,19}$")


class RoomError(Exception):
    def __init__(self, code: int, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def _int(v, lo, hi) -> bool:
    return type(v) is int and lo <= v <= hi


def _operand(v) -> bool:
    return (isinstance(v, str) and bool(WORD.match(v))) or _int(v, 0, 20)


def _clean(msg, seat: int):
    """A message in its checked shape (only known fields), or a RoomError."""
    if not isinstance(msg, dict) or not isinstance(msg.get("t"), str):
        raise RoomError(400, "Bad message.")
    t = msg["t"]
    if t in HOST_ONLY and seat != 0:
        raise RoomError(403, "Only the host can do that.")
    if t == "act":
        kind, a, b = msg.get("kind"), msg.get("a"), msg.get("b", -1)
        if seat == 0 or kind not in KINDS or not _operand(a) or not _int(b, -1, 20):
            raise RoomError(400, "Bad move.")
        return {"t": t, "kind": kind, "a": a, "b": b}
    if t == "emote":
        if msg.get("e") not in EMOTES:
            raise RoomError(400, "Bad cheer.")
        return {"t": t, "e": msg["e"]}
    if t == "start":
        spec = msg.get("spec")
        if not isinstance(spec, dict):
            raise RoomError(400, "Bad shift.")
        day, seed, upgrades, players = spec.get("day"), spec.get("seed"), spec.get("upgrades", {}), spec.get("players")
        rules = spec.get("rules")  # (the host's rules version: friends on another version are told to update)
        stall = spec.get("stall")  # (which stall: kopitiam, drinks... ; none on older versions)
        if (not _int(day, 1, 9999) or not isinstance(seed, str) or not re.match(r"^[A-Za-z0-9-]{1,40}$", seed)
                or spec.get("mode") != "day" or not _int(players, 1, MAX_PLAYERS) or not isinstance(upgrades, dict)
                or len(upgrades) > 10 or not all(WORD.match(k) and _int(v, 0, 9) for k, v in upgrades.items())
                or (rules is not None and not _int(rules, 1, 999))
                or (stall is not None and not (isinstance(stall, str) and WORD.match(stall)))):
            raise RoomError(400, "Bad shift.")
        out = {"day": day, "seed": seed, "mode": "day", "upgrades": dict(upgrades), "players": players}
        if rules is not None:
            out["rules"] = rules
        if stall is not None:
            out["stall"] = stall
        return {"t": t, "spec": out}
    if t == "frames":
        up_to, actions = msg.get("upTo"), msg.get("actions", [])
        if not _int(up_to, 0, MAX_TICKS) or not isinstance(actions, list) or len(actions) > 120:
            raise RoomError(400, "Bad frames.")
        last = 0
        for a in actions:
            if (not isinstance(a, list) or len(a) != 5 or not _int(a[0], last, up_to) or a[1] not in KINDS
                    or not _operand(a[2]) or not _int(a[3], -1, 20) or not _int(a[4], 0, MAX_PLAYERS - 1)):
                raise RoomError(400, "Bad frames.")
            last = a[0]
        return {"t": t, "upTo": up_to, "actions": [list(a) for a in actions]}
    if t == "day":
        stall = msg.get("stall")
        if not _int(msg.get("day"), 1, 9999) or (stall is not None and not (isinstance(stall, str) and WORD.match(stall))):
            raise RoomError(400, "Bad day.")
        return {"t": t, "day": msg["day"], **({"stall": stall} if stall is not None else {})}
    if t in ("pause", "resume", "over", "lobby"):
        return {"t": t}
    raise RoomError(400, "Bad message.")


class RushRooms:
    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.rooms: dict[str, dict] = {}

    # ------------------------------------------------------------------------------------------------ rooms and seats
    def _sweep(self) -> None:
        now = self.clock()
        for code in [c for c, r in self.rooms.items() if now - r["last"] > ROOM_IDLE]:
            self._close(code)

    def _close(self, code: str) -> None:
        room = self.rooms.pop(code, None)
        if room:
            room["closed"] = True
            room["event"].set()

    def _name(self, raw) -> str:
        name = clean_arcade_name(raw)
        if not name:
            raise RoomError(400, "Choose a name: 2 to 16 letters or numbers.")
        return name

    def _seat(self, room: dict, name: str) -> dict:
        token = secrets.token_urlsafe(18)
        seat = room["seats"].index(None)
        room["seats"][seat] = {"token": token, "name": name}
        return {"code": room["code"], "token": token, "seat": seat, **self._info(room)}

    def create(self, raw_name) -> dict:
        self._sweep()
        name = self._name(raw_name)
        if len(self.rooms) >= MAX_ROOMS:
            raise RoomError(429, "The hawker centre is full right now. Try again soon.")
        code = "".join(secrets.choice(CODE_LETTERS) for _ in range(5))
        while code in self.rooms:
            code = "".join(secrets.choice(CODE_LETTERS) for _ in range(5))
        room = {"code": code, "seats": [None] * MAX_PLAYERS, "log": [], "seq": 0, "since": 0, "state": "lobby",
                "last": self.clock(), "event": asyncio.Event(), "closed": False}
        self.rooms[code] = room
        return self._seat(room, name)

    def join(self, code, raw_name) -> dict:
        self._sweep()
        name = self._name(raw_name)
        room = self.rooms.get(str(code or "").strip().upper()[:10])
        if room is None:
            raise RoomError(404, "No stall with that code. Check it with your friend.")
        if None not in room["seats"]:
            raise RoomError(409, "That stall already has four cooks.")
        out = self._seat(room, name)
        self._add(room, -1, {"t": "roster"})
        return out

    def _member(self, code, token) -> tuple[dict, int]:
        self._sweep()
        room = self.rooms.get(str(code or "").strip().upper()[:10])
        if room is None:
            raise RoomError(404, "The stall has closed.")
        if isinstance(token, str) and TOKEN.match(token):
            for seat, p in enumerate(room["seats"]):
                if p and secrets.compare_digest(p["token"], token):
                    return room, seat
        raise RoomError(403, "You're not in this stall.")

    def leave(self, code, token) -> dict:
        room, seat = self._member(code, token)
        if seat == 0:
            self._close(room["code"])
        else:
            room["seats"][seat] = None
            self._add(room, -1, {"t": "roster"})
        return {"ok": True}

    # ------------------------------------------------------------------------------------------------ messages
    def _add(self, room: dict, seat: int, msg: dict) -> int:
        room["seq"] += 1
        room["log"].append({"seq": room["seq"], "from": seat, **msg})
        if len(room["log"]) > MAX_LOG:
            del room["log"][: len(room["log"]) - MAX_LOG]
        room["last"] = self.clock()
        room["event"].set()
        room["event"] = asyncio.Event()
        return room["seq"]

    def send(self, code, token, msg) -> dict:
        room, seat = self._member(code, token)
        if len(json.dumps(msg, separators=(",", ":"))) > MAX_MESSAGE_BYTES:
            raise RoomError(413, "Too big.")
        clean = _clean(msg, seat)
        if clean["t"] == "start":
            room["state"] = "playing"
            room["since"] = room["seq"]   # (someone joining now catches up from here)
        elif clean["t"] in ("lobby", "over"):
            room["state"] = "lobby"
        return {"seq": self._add(room, seat, clean)}

    async def pull(self, code, token, after: int) -> dict:
        """News from the others since `after` (waits up to WAIT seconds for some)."""
        room, seat = self._member(code, token)
        if after <= 0 and room["state"] == "playing":
            after = room["since"]   # (a phone joining mid-shift gets the setup and every frame so far)
        deadline = self.clock() + WAIT
        while True:
            room["last"] = self.clock()
            news = [m for m in room["log"] if m["seq"] > after and m["from"] != seat][:MAX_PULL]
            remaining = deadline - self.clock()
            if news or remaining <= 0 or room["closed"]:
                if room["closed"]:
                    raise RoomError(404, "The stall has closed.")
                return {"messages": news, "seq": room["seq"], **self._info(room)}
            try:
                await asyncio.wait_for(room["event"].wait(), remaining)
            except asyncio.TimeoutError:
                pass

    @staticmethod
    def _info(room: dict) -> dict:
        return {"state": room["state"],
                "players": [{"seat": s, "name": p["name"]} for s, p in enumerate(room["seats"]) if p]}
