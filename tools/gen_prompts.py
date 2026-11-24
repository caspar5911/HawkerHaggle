"""Regenerate app/lib/core/prompts.dart from server/hh/ai.py (the prompts are kept identical on both sides).
Run from the repo root: server/.venv/bin/python tools/gen_prompts.py"""
import json
import sys

sys.path.insert(0, "server")
from hh import ai  # noqa: E402


def dq(s):
    assert "'''" not in s
    return "r'''" + s + "'''"


events = ",\n".join(f"  {json.dumps(k)}: {json.dumps(v).replace(chr(36), chr(92) + chr(36))}" for k, v in ai.EVENTS.items())
src = f"""/// The AI prompts and event briefs, generated from server/hh/ai.py by tools/gen_prompts.py. Do not edit by hand.
library;

const events = <String, String>{{
{events},
}};

const understandPrompt = {dq(ai.UNDERSTAND)};

const sayPrompt = {dq(ai.SAY)};
"""
open("app/lib/core/prompts.dart", "w").write(src)
print("wrote app/lib/core/prompts.dart")
