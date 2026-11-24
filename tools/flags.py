"""List "she misunderstood me" reports for review. Run: server/.venv/bin/python tools/flags.py [path/to/hh.db]

Each report shows what the player typed, how the game read it, and her reply. Decide what the right reading was,
then add the message to server/tests/live_matrix.py with that expected move."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "server"))
from hh.store import Store  # noqa: E402

db = sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).resolve().parents[1] / "server" / "var" / "hh.db")
for f in Store(db).flags():
    e = f["exchange"]
    print(f"#{f['id']} {f['created_at'][:16]} {f['stall']}/{f['item']}")
    for m in e.get("context", [])[-4:]:
        print(f"    {'them' if m.get('who') == 'them' else 'you '}: {m.get('text')}")
    print(f"  YOU : {e['you']}\n  READ: {e['read_as']}{' + ' + e['also'] if e.get('also') else ''}"
          f"  ({e.get('reading') or 'word rules / fast path'})\n  HER : {e['reply']}\n")
