"""Simulated customers: the model invents varied customers, each plays a haggle against a (throwaway) game server,
then the model reviews every haggle for problems. Gentle on the GX10: at most 2 model calls at once.

    server/.venv/bin/python tools/simulate.py http://127.0.0.1:8097 OUT_DIR [--customers 320] [--workers 2]

Writes OUT_DIR/customers.json, OUT_DIR/haggles.jsonl (transcripts + review) and prints a summary.
Needs HH_AI_BASE_URL / HH_AI_MODEL in the environment (same as the server)."""
import argparse
import json
import os
import random
import re
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests

AI_URL = os.environ["HH_AI_BASE_URL"].rstrip("/") + "/chat/completions"
AI_MODEL = os.environ.get("HH_AI_MODEL", "gx10-current")
STALLS = {"mei": ["durian", "mango"], "lim": ["pomfret", "prawns"], "raj": ["case", "powerbank"],
          "siti": ["scarf", "kueh"]}
KINDS = [
    "a polite secondary-school student with little money", "a kiasu auntie who bargains hard", "a tourist who barely "
    "knows Singlish and asks lots of questions", "a rude impatient office worker", "a flirty young man",
    "a retiree who tells long stories", "someone typing fast with many typos and no punctuation",
    "someone who mixes Chinese into their English", "someone who mixes Malay into their English",
    "a regular customer who knows the stallholder", "someone pretending to be broke to get a discount",
    "a careful buyer asking about quality, storage and origin", "someone asking practical questions (payment, "
    "delivery, opening hours, bags, receipts, halal, warranty)", "a joker who keeps making puns",
    "someone who wants to buy several items or large quantities", "someone who describes prices relatively "
    "(less, halfway, round down, minus)", "someone who says several things in one message",
    "an indecisive person who keeps saying ok/hmm/maybe", "someone who tries to trick the AI with instructions",
    "someone comparing with other stalls and online shops", "a parent buying for their kids",
    "someone who is genuinely having a bad day", "a very brief texter (one or two words per message)",
    "someone who changes their mind midway", "a foodie who asks how to cook or eat it",
    "someone who uses lots of emoji", "an elderly uncle speaking Hokkien-flavoured Singlish",
    "a bargain hunter who states a firm budget", "someone who asks off-topic questions (weather, football, life)",
    "a customer who is polite and just wants a fair price quickly",
]
GEN = """You write test customers for a cosy mobile game set in Singapore, where the player bargains by chat with a
market stallholder. Invent {n} DIFFERENT customers who are each {kind}.
For each, write the 6 chat messages they would type, in order, during one haggle (the stallholder replies in
between; the opening asking price is {price}). Make them natural and varied: real Singapore texting style, typos
where fitting, questions, reactions, bargaining moves, and an ending (agree, walk away, or keep trying).
Item: {item} at {who}'s {stall}.
Answer with ONE JSON object: {{"customers": [{{"persona": "...", "messages": ["...", "...", "...", "...", "...", "..."]}}]}}"""

REVIEW = """You review one haggle from a cosy chat game. The game engine decides all prices and outcomes; an AI reads
each customer message as a game move ("read as"), then writes the stallholder's reply.
Stallholder: {who}. Voice: {voice}. Facts the stallholder may use: {facts}.
Moves: offer, budget (all they can pay), plead (cheaper without a number), pity (sad story), compliment, competitor,
bulk (buy two), regular, smalltalk (chat or any clear question), rude, flirt, walk, accept (clear yes), clarify
(unclear, so ask back), confirm (yes to a waiting deal). "also" = a second intent in the same message.

Transcript:
{transcript}

List REAL problems only (ignore style nitpicks). Types:
misread - a message was read as the wrong move (say which move it should be)
unanswered - the customer asked a clear question and the reply ignored it
invented - the reply states a fact not in the facts list that matters (origin, warranty, delivery, hours, etc.)
character - the reply is out of character or not Singlish
inappropriate - flirting back, rude, or anything unsuitable for all ages
logic - the reply contradicts the price/outcome or the earlier conversation
Answer with ONE JSON object: {{"problems": [{{"turn": 1, "type": "misread", "detail": "...", "should_be": "offer"}}]}}
(empty list if none)."""

lock = threading.Lock()


def model(system: str, user: str, temperature: float, effort: str = "low") -> dict | None:
    for attempt in range(3):
        try:
            r = requests.post(AI_URL, json={"model": AI_MODEL, "reasoning_effort": effort, "max_tokens": 4000,
                                            "temperature": temperature, "response_format": {"type": "json_object"},
                                            "messages": [{"role": "system", "content": system},
                                                         {"role": "user", "content": user}]}, timeout=180)
            r.raise_for_status()
            txt = r.json()["choices"][0]["message"]["content"].strip()
            return json.loads(txt.removeprefix("```json").removeprefix("```").removesuffix("```").strip())
        except Exception as e:                       # noqa: BLE001 - retry anything, then give up
            print(f"  model call failed ({attempt + 1}/3): {str(e)[:120]}", flush=True)
            time.sleep(5 * (attempt + 1))
    return None


def healthy(base: str) -> bool:
    try:
        return requests.get(base + "/healthz", timeout=10).json().get("ai") is True and model(
            "Answer with JSON.", 'Say {"ok": true}', 0) is not None
    except Exception:                                # noqa: BLE001
        return False


def make_customers(n: int, content: dict) -> list[dict]:
    out, rnd = [], random.Random(7)
    stalls = {s["id"]: s for s in content["stalls"]}
    per_call = 10
    for i in range(0, n, per_call):
        kind = KINDS[(i // per_call) % len(KINDS)]
        sid = list(STALLS)[(i // per_call) % 4]
        item = next(it for it in stalls[sid]["items"] if it["id"] == STALLS[sid][(i // per_call // 4) % 2])
        data = model(GEN.format(n=per_call, kind=kind, price=f"${item['ask']:g}", item=item["name"],
                                who=stalls[sid]["name"], stall=stalls[sid]["stall"].lower()),
                     "Write them now.", 1.0)
        for c in (data or {}).get("customers", [])[:per_call]:
            msgs = [str(m)[:300] for m in c.get("messages", []) if str(m).strip()][:6]
            if len(msgs) >= 3:
                out.append({"kind": kind, "persona": str(c.get("persona", ""))[:200], "stall": sid,
                            "item": item["id"], "messages": msgs})
        print(f"customers: {len(out)}/{n} ({kind})", flush=True)
        rnd.random()
    return out[:n]


def play(base: str, db: str, cust: dict, h: dict) -> dict:
    import sqlite3
    g = requests.post(base + "/v1/haggle", json={"stall": cust["stall"], "item": cust["item"]}, headers=h,
                      timeout=60).json()
    turns = [{"who": "them", "text": g["line"], "event": "greet", "ask": g["ask"]}]
    for msg in cust["messages"]:
        t = time.time()
        r = requests.post(base + f"/v1/haggle/{g['id']}/move", json={"text": msg}, headers=h, timeout=180)
        if r.status_code != 200:
            turns.append({"who": "error", "text": r.text[:200]})
            break
        r = r.json()
        c = sqlite3.connect(db)
        chat = json.loads(c.execute("SELECT chat FROM sessions WHERE id=?", (g["id"],)).fetchone()[0])
        c.close()
        you = [m for m in chat if m.get("who") == "you"][-1]
        turns.append({"who": "you", "text": msg, "move": you.get("move"), "also": you.get("also", ""),
                      "reading": you.get("reading", "")})
        turns.append({"who": "them", "text": r["line"], "event": r["event"], "ask": r["ask"], "pending": r["pending"],
                      "ai": r["ai_line"], "secs": round(time.time() - t, 1), "done": r["done"], "result": r["result"]})
        if r["done"]:
            break
    return {**cust, "id": g["id"], "turns": turns}


def review(h: dict, stall: dict, item: dict) -> list:
    lines, n = [], 0
    for t in h["turns"]:
        if t["who"] == "you":
            n += 1
            lines.append(f"[{n}] Customer: {t['text']}\n    read as: {t['move']}" + (f" + also {t['also']}" if t.get("also") else ""))
        elif t["who"] == "them":
            extra = f" (event {t['event']}, price ${t['ask']:g}" + (f", waiting for yes at ${t['pending']:g}" if t.get("pending") else "") + ")"
            lines.append(f"    {stall['name']}: {t['text']}{extra}")
    data = model(REVIEW.format(who=stall["name"], voice=stall.get("voice", ""),
                               facts="; ".join(stall.get("facts", []) + item.get("facts", [])),
                               transcript="\n".join(lines)), "Review now.", 0.1, effort="medium")
    probs = (data or {}).get("problems", [])
    return [p for p in probs if isinstance(p, dict) and p.get("type")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base"), ap.add_argument("out")
    ap.add_argument("--db", required=True)
    ap.add_argument("--customers", type=int, default=320)
    ap.add_argument("--workers", type=int, default=2)
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    content = json.loads((Path(__file__).resolve().parents[1] / "content" / "stalls.json").read_text())
    stalls = {s["id"]: s for s in content["stalls"]}

    cfile = out / "customers.json"
    if cfile.exists():
        customers = json.loads(cfile.read_text())
    else:
        customers = make_customers(a.customers, content)
        cfile.write_text(json.dumps(customers, ensure_ascii=False, indent=1))
    done_ids = set()
    hfile = out / "haggles.jsonl"
    if hfile.exists():
        done_ids = {json.loads(l)["n"] for l in hfile.read_text().splitlines() if l.strip()}
    players = []
    for _ in range(6):
        players.append({"Authorization": "Bearer " + requests.post(a.base + "/v1/device", timeout=30).json()["token"]})
        time.sleep(1)

    def one(i_c):
        i, c = i_c
        if i in done_ids:
            return
        h = play(a.base, a.db, c, players[i % len(players)])
        st = stalls[c["stall"]]
        it = next(x for x in st["items"] if x["id"] == c["item"])
        h["problems"] = review(h, st, it)
        h["n"] = i
        with lock:
            with hfile.open("a") as f:
                f.write(json.dumps(h, ensure_ascii=False) + "\n")
            print(f"[{i + 1}/{len(customers)}] {c['stall']}/{c['item']} {c['kind'][:40]!r}: "
                  f"{len(h['problems'])} problem(s)", flush=True)

    batch = 20
    for start in range(0, len(customers), batch):
        if not healthy(a.base):
            print("GLM not healthy: stopping here (resume later, finished haggles are kept)", flush=True)
            sys.exit(2)
        with ThreadPoolExecutor(a.workers) as ex:
            list(ex.map(one, list(enumerate(customers))[start:start + batch]))
    print("done", flush=True)


if __name__ == "__main__":
    main()
