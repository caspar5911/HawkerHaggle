"""Synthesise the game's sound effects (original, no samples). Run: python3 tools/make_sounds.py

Writes small mono 16-bit WAVs to app/assets/sfx/.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "app" / "assets" / "sfx"


def env(i, n, attack=0.01, release=0.6):
    t = i / RATE
    a = min(1.0, t / attack) if attack else 1.0
    r = max(0.0, 1 - (i / n)) ** (1 / release) if release else 1.0
    return a * r


def tone(freq, dur, vol=0.5, shape="sine", slide=0.0, attack=0.005, release=0.5, vibrato=0.0):
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        f = freq * (1 + slide * i / n)
        if vibrato:
            f *= 1 + 0.03 * math.sin(2 * math.pi * vibrato * i / RATE)
        phase += 2 * math.pi * f / RATE
        if shape == "square":
            s = 0.6 if math.sin(phase) >= 0 else -0.6
        elif shape == "tri":
            s = 2 / math.pi * math.asin(math.sin(phase))
        else:
            s = math.sin(phase) + 0.25 * math.sin(2 * phase)
        out.append(s * vol * env(i, n, attack, release))
    return out


def noise(dur, vol=0.3, lowpass=0.2, sweep=0.0):
    n = int(RATE * dur)
    out, y = [], 0.0
    for i in range(n):
        a = min(0.95, max(0.01, lowpass + sweep * i / n))
        y += a * (random.uniform(-1, 1) - y)
        out.append(y * vol * math.sin(math.pi * i / n))
    return out


def silence(dur):
    return [0.0] * int(RATE * dur)


def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def cat(*parts):
    return [s for p in parts for s in p]


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    k = 0.85 / peak if peak > 0.85 else 1.0
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * k)) * 32767)) for s in samples))


def main():
    random.seed(7)
    # soft bubble pop for taps
    write("pop", tone(520, 0.07, 0.45, slide=0.9, release=0.3))
    # cute chirp when a stallholder speaks
    write("chat", cat(tone(660, 0.05, 0.3, "tri", slide=0.15), tone(880, 0.07, 0.3, "tri", slide=-0.1)))
    # coin clink
    write("coin", cat(tone(1318, 0.06, 0.35, "square", release=0.4), tone(1760, 0.22, 0.35, "square", release=0.5)))
    # happy little deal jingle (C E G C')
    notes = [523.25, 659.25, 783.99, 1046.5]
    write("deal", cat(*[tone(f, 0.11 if i < 3 else 0.35, 0.4, "tri", release=0.6) for i, f in enumerate(notes)]))
    # cartoon boing when insulted
    write("huff", mix(tone(180, 0.38, 0.55, "tri", slide=1.2, vibrato=18), noise(0.12, 0.15, 0.3)))
    # down-slide when the stallholder gets annoyed / patience drops
    write("hmm", tone(420, 0.25, 0.4, "tri", slide=-0.35, vibrato=7))
    # whoosh when walking away
    write("whoosh", noise(0.35, 0.6, 0.05, sweep=0.5))
    # sparkly star ding
    write("star", mix(tone(1568, 0.3, 0.3, release=0.4), cat(silence(0.04), tone(2093, 0.28, 0.2, release=0.4))))
    # sad trombone-ish for no sale
    write("aww", cat(*[tone(f, d, 0.4, "tri", vibrato=6) for f, d in [(392, 0.18), (370, 0.18), (349, 0.18), (330, 0.45)]]))


if __name__ == "__main__":
    main()
