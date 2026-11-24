"""Summarise a simulate.py run: python3 tools/sim_report.py OUT_DIR [--show TYPE] [--n 20]"""
import argparse
import collections
import json
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("out")
ap.add_argument("--show", default="")
ap.add_argument("--n", type=int, default=15)
a = ap.parse_args()
hs = [json.loads(l) for l in (Path(a.out) / "haggles.jsonl").read_text().splitlines() if l.strip()]

types, by_kind, turns, fallback, secs, clar_runs, repeats, results = (collections.Counter(), collections.Counter(), 0, 0,
                                                                       [], 0, 0, collections.Counter())
for h in hs:
    results[next((t["result"] for t in reversed(h["turns"]) if t.get("result")), "unfinished")] += 1
    for p in h["problems"]:
        types[p["type"]] += 1
        by_kind[h["kind"][:45]] += 1
    them = [t for t in h["turns"] if t["who"] == "them" and "secs" in t]
    turns += len(them)
    fallback += sum(not t["ai"] for t in them)
    secs += [t["secs"] for t in them]
    run = 0
    for t in them:
        run = run + 1 if t["event"] == "clarify" else 0
        clar_runs += run == 2
    texts = [t["text"] for t in them]
    repeats += len(texts) - len(set(texts))

secs.sort()
print(f"{len(hs)} haggles, {turns} replies. Endings: {dict(results)}")
print(f"Haggles with no problems: {sum(not h['problems'] for h in hs)} ({sum(not h['problems'] for h in hs) / len(hs):.0%})")
print(f"Problems by type: {dict(types.most_common())}")
print(f"Ready-made (non-AI) replies: {fallback} ({fallback / max(turns, 1):.1%}); identical replies in a haggle: {repeats}")
print(f"Asked back twice in a row: {clar_runs} times")
print(f"Reply time: median {secs[len(secs) // 2]:.1f}s, 90% under {secs[int(len(secs) * .9)]:.1f}s, max {secs[-1]:.1f}s")
print("Customer types with the most problems:")
for k, v in by_kind.most_common(8):
    print(f"  {v:3}  {k}")
if a.show:
    shown = 0
    for h in hs:
        for p in h["problems"]:
            if p["type"] != a.show or shown >= a.n:
                continue
            shown += 1
            you = [t for t in h["turns"] if t["who"] == "you"]
            them = [t for t in h["turns"] if t["who"] == "them"]
            i = int(p.get("turn") or 1)
            print(f"\n--- {h['stall']}/{h['item']} {h['kind'][:40]}  turn {i}")
            if 0 < i <= len(you):
                print(f"  YOU : {you[i - 1]['text']}\n  READ: {you[i - 1]['move']}"
                      + (f" + {you[i - 1]['also']}" if you[i - 1].get("also") else ""))
                if i < len(them):
                    print(f"  HER : {them[i]['text']}  [{them[i]['event']}]")
            print(f"  !! {p.get('detail', '')[:300]}" + (f"  (should be {p['should_be']})" if p.get("should_be") else ""))
