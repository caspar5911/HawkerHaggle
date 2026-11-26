"""Export the Python game's answers for many inputs, so the app's Dart port can be checked against them.

    server/.venv/bin/python tools/export_fixtures.py  ->  app/test/fixtures/reference.json"""
import itertools
import json
import random
import sys
from dataclasses import asdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
sys.path.insert(0, str(ROOT / "server" / "tests"))
from hh import ai, engine  # noqa: E402
from live_matrix import CASES  # noqa: E402
from test_sweep import TYPED  # noqa: E402

content = json.loads((ROOT / "content" / "stalls.json").read_text())

messages = sorted({m for m, *_ in CASES} | set(TYPED) | {
    "便宜15", "15块", "15块可以吗", "$1.50", "$ 15", "15.5 can", "1,000", "😂", "👍 deal", "ok", "OK LAH", "can can",
    "  ok lah  ", "deal!!", "no deal", "I only have $16", "wallet only left $20", "16 is all I got", "my budget 18.50",
    "actually just one", "one enough lah", "don't want two", "no need two", "only 1 can?", "just one, $20 can?",
    "2 for 40", "two for $30", "2=40", "I buy 3", "give me 2", "take 2 for 30", "$2 less", "3 dollars off", "minus 1.50",
    "half half lah", "split the difference", "remove the cents", "round it down", "I love you 15 please", "marry me",
    "go on a date", "stupid uncle", "you cheat", "boss you very nice, $12 can?", "regular customer, 20?",
    "starving, 10 can?", "kesian me", "next stall $10", "shopee cheaper", "I come every week", "nvm", "bye bye",
    "forget it", "I think first", "pack for me", "wrap it", "I'll take it", "I will buy this", "I take it if you give bag",
    "ok but", "hmm", "hmmm ok", "ya lor", "yes deal", "sure or not", "okay then", "OK!", "boleh", "steady boss",
    "confirm plus chop", "15", "$12 can?", "15 lah", "3", "$3", "100", "15 for two", "12.50", "12.5", "$12.75 can or not",
    "15 dollars", "20 bucks pls", "ok lah 24", "24 ok?", "", "?", "$", "$$$", "0", "$0", "-5", "1e5", "15/2",
})

def heard(h):
    d = h._asdict()
    return {k: d[k] for k in ("move", "price", "also", "rel_op", "rel_amount", "per", "qty")}

nums = [0.1, 0.25, 0.5, 0.75, 1, 1.25, 4.75, 8.5, 9.25, 9.75, 10.25, 10.75, 12.25, 12.75, 13, 13.01, 13.25, 13.5, 13.75,
        14.999, 15.25, 17.75, 19.24, 19.25, 19.5, 19.75, 19.99, 20, 20.2, 20.5, 21.5, 22.5, 23.5, 24.5, 31.6, 32.5, 44.5,
        99.5, 100.5, 7.125, 7.375, 18.475, 18.525]
out = {
    "nice": [[x, engine.nice(x)] for x in nums],
    "nice_up": [[x, engine.nice_up(x)] for x in nums],
    "money": [[x, ai.money(x)] for x in nums + [16, 16.0, 0, 2.5, 2.05, 13.333]],
    "heard_by_rules": [[m, heard(ai.heard_by_rules(m))] for m in messages],
    "rules": [[m, list(ai.rules(m))] for m in messages],
    "plain_yes": [[m, ai.plain_yes(m)] for m in messages],
    "fast_offer": [[m, a, ai.fast_offer(m, a)] for m in messages for a in (6, 22, 45)],
}
checks = [
    ("OK lah, $12 for you", [12.0], [], False), ("OK lah, $5 for you", [12.0], [], False),
    ("Buy 2, I give $12 each", [12.0], [], False), ("", [12.0], [], False), ("FREE for you, $0!", [12.0], [], False),
    ("$1 only", [12.0], [], False), ("Plastic bag I throw in free, still $45", [45.0], [], False),
    ("Free for you lah", [45.0], [], False), ("You mean $20 for all three?", [45.0], [3, 20], True),
    ("OK $20 for you", [45.0], [20], False), ("Sold here 30 years already, $32 still", [32.0], [], False),
    ("Keep 3 days in fridge, 2 kg one", [32.0], [], False), ("OK 25 for you", [32.0], [], False),
    ("Open 7am, $32", [32.0], [], False), ("20000 mAh, charge 4 times, $45", [45.0], [20000, 4], False),
    ("50% off for you", [10.0], [], False), ("10 percent discount", [10.0], [], False),
    ("$12.50 lah", [12.5], [], False), ("$12.5 lah", [12.5], [], False), ("Line one\nline two $99", [12.0], [], False),
    ('"Quoted $12"', [12.0], [], False), ("$ 12 ok", [12.0], [], False), ("only 3 left, $12", [12.0], [], False),
    ("6 mangoes in a box, $18", [18.0], [6], False), ("I give you discount of $2", [12.0], [], False),
    ("Wah 100 pieces ah? Still $35 each lah", [35.0], [100, 150], False), ("x" * 300 + " $12", [12.0], [], False),
]
out["checked"] = [[t, a, c, d, ai.checked(t, a, counts=c, dollar_counts=d)] for t, a, c, d in checks]
out["mood_line"] = [[e, p, a, ai.mood_line(e, p, a)] for e in ("counter", "confirm", "plead", "greet", "smalltalk")
                    for p in (None, 10, 24.9, 25, 49.9, 50, 84.9, 85, 100) for a in ("", "compliment", "flirt", "rude")]
hist = [{"who": "them", "text": "Aiyo come come, $32!"}, {"who": "you", "text": "hi"},
        {"who": "them", "text": "Wah you so polite"}, {"who": "them", "text": "$32 only"},
        {"who": "them", "text": "aiyo again"}, {"who": "them", "text": "   "}, {"who": "them", "text": "Don't-worry lah"}]
out["opener_hint"] = [[hist[:n], ai.opener_hint(hist[:n])] for n in range(len(hist) + 1)]
out["transcript"] = [[hist, "Auntie Mei", ai.transcript(hist, "Auntie Mei")], [[], "X", ai.transcript([], "X")]]

# Engine traces (no randomness: competitor and walk use the RNG, so they are left out; suggestions' tactic too)
KINDS = ["offer", "budget", "plead", "pity", "flirt", "compliment", "bulk", "one", "regular", "smalltalk", "rude", "accept",
         "confirm", "cancel", "buy", "side:compliment", "side:regular", "side:pity", "side:flirt", "side:rude"]
traces, rnd = [], random.Random(11)
for st in content["stalls"]:
    for it in st["items"]:
        for run in range(25):
            h = engine.Haggle(engine.Item(**{k: it[k] for k in ("id", "name", "fair", "ask", "floor")}, single=bool(it.get("single"))),
                              engine.Personality(**st["personality"]), seed=1)
            steps = []
            for _ in range(rnd.randint(3, 16)):
                kind = rnd.choice(KINDS)
                price = None
                if kind in ("offer", "budget") or (kind == "bulk" and rnd.random() < 0.5):
                    price = round(rnd.choice([it["ask"], it["fair"], it["floor"], it["floor"] * 0.6, h.s.ask - 1,
                                              h.s.ask * rnd.uniform(0.4, 1.2), h.s.pending or h.s.ask]), 2)
                if kind.startswith("side:"):
                    h.side(kind[5:])
                    o = None
                else:
                    o = asdict(h.move(kind, price))
                sug = h.suggestions()
                steps.append({"kind": kind, "price": price, "out": o,
                              "state": {k: v for k, v in asdict(h.s).items()},
                              "floor_now": h.floor_now(), "stars": h.stars(),
                              "suggest": [[s["move"], s["price"]] for s in sug[:2]], "n_suggest": len(sug)})
                if h.s.done:
                    break
            traces.append({"stall": st["id"], "item": it["id"], "steps": steps})
out["engine"] = traces
p = ROOT / "app" / "test" / "fixtures" / "reference.json"
p.write_text(json.dumps(out, ensure_ascii=False))
print(f"wrote {p} ({p.stat().st_size // 1024} KB): {len(messages)} messages, {len(traces)} engine traces")
