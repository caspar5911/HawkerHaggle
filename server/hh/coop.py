"""Live co-op (tag-team haggles): two friends in the same haggle, each on their own phone.

The host's phone runs the haggle (the game and every AI call); this is only a mailbox between the two phones, kept in
memory. A room has a short code; the host creates it, a friend joins with the code. The host posts the haggle's state
after every move; the friend posts moves (a tap, a typed message, walk/buy...), which the host's game plays. Rooms
expire after a few idle minutes and are capped in size, so a restart or a stranger can't do much.
"""
from __future__ import annotations

import json
import secrets
import time

ROOM_IDLE = 10 * 60          # seconds without a message before a room is dropped
MAX_ROOMS = 200
MAX_MESSAGES = 300           # per room (older ones are dropped)
MAX_MESSAGE_BYTES = 8 * 1024
CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no 0/O or 1/I
FRIEND_MOVES = {"walk", "buy", "accept", "confirm", "cancel"}


class CoopError(Exception):
    def __init__(self, code: int, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


class Rooms:
    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.rooms: dict[str, dict] = {}

    def _sweep(self) -> None:
        now = self.clock()
        for code in [c for c, r in self.rooms.items() if now - r["last"] > ROOM_IDLE]:
            del self.rooms[code]

    def _room(self, code: str, account_id: int) -> tuple[dict, str]:
        self._sweep()
        r = self.rooms.get((code or "").strip().upper())
        if r is None:
            raise CoopError(404, "That room has closed. Ask your friend for a new code.")
        if r["host"] == account_id:
            return r, "host"
        if r["guest"] == account_id:
            return r, "guest"
        raise CoopError(403, "You're not in this room.")

    def create(self, account_id: int, name: str, stall: str, item: str) -> dict:
        self._sweep()
        for code, r in list(self.rooms.items()):        # one room per host at a time
            if r["host"] == account_id:
                del self.rooms[code]
        if len(self.rooms) >= MAX_ROOMS:
            raise CoopError(429, "The market is too busy for new rooms. Try again soon.")
        code = "".join(secrets.choice(CODE_LETTERS) for _ in range(5))
        while code in self.rooms:
            code = "".join(secrets.choice(CODE_LETTERS) for _ in range(5))
        self.rooms[code] = {"host": account_id, "host_name": name, "guest": None, "guest_name": "",
                            "stall": stall, "item": item, "messages": [], "seq": 0, "last": self.clock()}
        return {"code": code}

    def join(self, account_id: int, name: str, code: str) -> dict:
        self._sweep()
        r = self.rooms.get((code or "").strip().upper())
        if r is None:
            raise CoopError(404, "No room with that code. Check it with your friend.")
        if r["host"] == account_id:
            raise CoopError(400, "That's your own room: share the code with a friend.")
        if r["guest"] not in (None, account_id):
            raise CoopError(409, "Someone else already joined this room.")
        r["guest"], r["guest_name"], r["last"] = account_id, name, self.clock()
        self._add(r, "server", {"type": "joined", "name": name})
        return self._info(r, (code or "").strip().upper())

    def send(self, account_id: int, code: str, msg) -> dict:
        r, role = self._room(code, account_id)
        if not isinstance(msg, dict):
            raise CoopError(400, "Bad message.")
        if len(json.dumps(msg)) > MAX_MESSAGE_BYTES:
            raise CoopError(413, "Message too big.")
        kind = msg.get("type")
        if role == "host":
            if kind not in ("state", "end"):
                raise CoopError(400, "The host sends the haggle's state.")
        else:
            if kind != "move":
                raise CoopError(400, "A friend sends moves.")
            pick, move, text = msg.get("pick"), msg.get("move"), msg.get("text")
            given = [x for x in (pick, move, text) if x is not None]
            if len(given) != 1:
                raise CoopError(400, "One move at a time.")
            if pick is not None and not (isinstance(pick, int) and not isinstance(pick, bool) and 0 <= pick <= 2):
                raise CoopError(400, "No such suggestion.")
            if move is not None and move not in FRIEND_MOVES:
                raise CoopError(400, "No such move.")
            if text is not None and not (isinstance(text, str) and 0 < len(text.strip()) <= 300):
                raise CoopError(400, "Type something (up to 300 characters).")
            msg = {"type": "move", **({"pick": pick} if pick is not None else {}),
                   **({"move": move} if move is not None else {}), **({"text": text.strip()} if text else {})}
        r["last"] = self.clock()
        seq = self._add(r, role, msg)
        return {"seq": seq}

    def pull(self, account_id: int, code: str, after: int) -> dict:
        r, role = self._room(code, account_id)
        r["last"] = self.clock()
        after = after if isinstance(after, int) else 0
        return {**self._info(r, (code or "").strip().upper()), "you": role,
                "messages": [m for m in r["messages"] if m["seq"] > after]}

    def leave(self, account_id: int, code: str) -> dict:
        r, role = self._room(code, account_id)
        if role == "host":
            del self.rooms[(code or "").strip().upper()]
        else:
            r["guest"], r["guest_name"] = None, ""
            self._add(r, "server", {"type": "left"})
        return {"ok": True}

    @staticmethod
    def _add(r: dict, sender: str, msg: dict) -> int:
        r["seq"] += 1
        r["messages"].append({"seq": r["seq"], "from": sender, **msg})
        if len(r["messages"]) > MAX_MESSAGES:
            del r["messages"][: len(r["messages"]) - MAX_MESSAGES]
        return r["seq"]

    @staticmethod
    def _info(r: dict, code: str) -> dict:
        return {"code": code, "host_name": r["host_name"], "guest_name": r["guest_name"],
                "joined": r["guest"] is not None, "stall": r["stall"], "item": r["item"]}
