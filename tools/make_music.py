"""Compose the game's background music (original, synthesised: no samples, no borrowed tunes).

Run: python3 -m venv /tmp/mus && /tmp/mus/bin/pip install numpy lameenc && /tmp/mus/bin/python tools/make_music.py

Writes two looping tunes to app/assets/music/:
  stroll.mp3  bright and bouncy, for walking around the market (C major, 100 bpm)
  calm.mp3    soft and slow, under a haggle so it never gets in the way (G major, 80 bpm)

Instruments are toy-like: a marimba / music-box lead, a plucked bass, ukulele-ish chord plucks, a shaker and a soft
kick. Echoes wrap around the end of the loop, so the tune loops without a jump.
"""
from pathlib import Path

import lameenc
import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "app" / "assets" / "music"
NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def hz(name):
    """'C5', 'F#4', 'Bb3' to Hz."""
    letter, rest = name[0], name[1:]
    shift = 0
    while rest and rest[0] in "#b":
        shift += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    midi = 12 * (int(rest) + 1) + NOTE[letter] + shift
    return 440.0 * 2 ** ((midi - 69) / 12)


def voice(freq, dur, partials, decay, attack=0.004):
    """One struck note: a few sine partials [(ratio, amp, decay scale)], each fading at its own speed."""
    n = int(RATE * dur)
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for ratio, amp, dk in partials:
        f = freq * ratio
        if f > RATE / 2.2:
            continue
        out += amp * np.sin(2 * np.pi * f * t) * np.exp(-t / (decay * dk))
    out *= np.minimum(1, t / attack)
    # a short fade at the very end so a cut-off note never clicks
    tail = min(n, int(RATE * 0.02))
    if tail:
        out[-tail:] *= np.linspace(1, 0, tail)
    return out


def marimba(f, dur):
    return voice(f, max(dur, 0.9), [(1, 1, 1), (3.93, 0.25, 0.2), (9.2, 0.05, 0.08)], 0.45)


def musicbox(f, dur):
    return voice(f, max(dur, 1.4), [(1, 1, 1), (2, 0.18, 0.6), (5.4, 0.06, 0.25)], 0.7, attack=0.002)


def bass(f, dur):
    return voice(f, max(dur, 0.5), [(1, 1, 1), (2, 0.45, 0.6), (3, 0.18, 0.4)], 0.32, attack=0.008)


def pluck(f, dur):
    return voice(f, 0.45, [(1, 1, 1), (2, 0.35, 0.5), (3, 0.12, 0.3)], 0.16, attack=0.003)


def kick():
    n = int(RATE * 0.16)
    t = np.arange(n) / RATE
    f = 50 + 70 * np.exp(-t / 0.03)
    return np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / 0.05)


def shaker(rng, length=0.05):
    n = int(RATE * length)
    t = np.arange(n) / RATE
    x = np.diff(rng.uniform(-1, 1, n + 1))  # brighter than plain noise
    return x * np.exp(-t / (length / 4)) * np.minimum(1, t / 0.004)


class Track:
    def __init__(self, bpm, beats):
        self.beat = 60 / bpm
        self.buf = np.zeros(int(RATE * self.beat * beats) + 1)

    def add(self, at_beat, sound, vol):
        """Adds a sound at a beat; anything past the end wraps to the start (so the loop is seamless)."""
        i = int(round(at_beat * self.beat * RATE)) % len(self.buf)
        s = sound * vol
        while len(s):
            room = len(self.buf) - i
            self.buf[i : i + min(room, len(s))] += s[:room]
            s, i = s[room:], 0

    def melody(self, start, notes, inst, vol, octave=0):
        """notes: [(name or 'r', beats)]."""
        b = start
        for name, beats in notes:
            if name != "r":
                self.add(b, inst(hz(name) * 2**octave, beats * self.beat), vol)
            b += beats
        return b

    def echo(self, delay_beats, gain, times=3):
        d = int(round(delay_beats * self.beat * RATE))
        dry = self.buf.copy()
        for k in range(1, times + 1):
            self.buf += np.roll(dry, d * k) * gain**k

    def mp3(self, name, loud=0.7):
        x = self.buf / max(1e-9, np.abs(self.buf).max()) * loud
        pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
        enc = lameenc.Encoder()
        enc.set_bit_rate(80)
        enc.set_in_sample_rate(RATE)
        enc.set_channels(1)
        enc.set_quality(2)
        data = enc.encode(pcm) + enc.flush()
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / f"{name}.mp3").write_bytes(data)
        print(f"{name}.mp3  {len(self.buf) / RATE:.1f}s  {len(data) // 1024} KB")


CHORDS = {
    "C": ["C3", "E4", "G4", "C5"],
    "Am": ["A2", "E4", "A4", "C5"],
    "F": ["F2", "F4", "A4", "C5"],
    "G": ["G2", "D4", "G4", "B4"],
    "Em": ["E3", "E4", "G4", "B4"],
    "Dm": ["D3", "D4", "F4", "A4"],
    "D": ["D3", "D4", "F#4", "A4"],
}


def comp_bouncy(t, start, bars, rng):
    """Bass on 1 and 3 with a pickup, chord plucks on the off-beats (2 and 4), shaker eighths, kick on 1 and 3."""
    for i, bar in enumerate(bars):
        halves = bar.split() if " " in bar else [bar, bar]
        for h, ch in enumerate(halves):
            b = start + i * 4 + h * 2
            root = hz(CHORDS[ch][0])
            t.add(b, bass(root, t.beat), 0.55)
            t.add(b + 1.5, bass(root * (1.5 if h == 0 else 2), t.beat / 2), 0.25)
            t.add(b, kick(), 0.35)
            for k, note in enumerate(CHORDS[ch][1:]):
                t.add(b + 1 + k * 0.012, pluck(hz(note), t.beat), 0.16)
        for e in range(8):
            t.add(start + i * 4 + e / 2, shaker(rng), 0.10 if e % 2 else 0.05)


# Stroll: A A' B A, 32 bars of C major pentatonic-ish
A = [
    [("E5", 0.5), ("G5", 0.5), ("A5", 0.5), ("G5", 0.5), ("E5", 1), ("C5", 1)],
    [("D5", 0.5), ("E5", 0.5), ("C5", 0.5), ("A4", 0.5), ("C5", 2)],
    [("A4", 0.5), ("C5", 0.5), ("D5", 0.5), ("C5", 0.5), ("A5", 1), ("G5", 1)],
    [("G5", 0.5), ("E5", 0.5), ("D5", 0.5), ("E5", 0.5), ("D5", 2)],
    [("E5", 0.5), ("G5", 0.5), ("A5", 0.5), ("C6", 0.5), ("A5", 1), ("G5", 1)],
    [("E5", 0.5), ("G5", 0.5), ("E5", 0.5), ("D5", 0.5), ("C5", 1), ("A4", 1)],
    [("C5", 0.5), ("D5", 0.5), ("E5", 1), ("D5", 0.5), ("C5", 0.5), ("D5", 1)],
    [("C5", 3), ("r", 1)],
]
A_CHORDS = ["C", "Am", "F", "G", "C", "Am", "F G", "C"]
B = [
    [("A5", 1.5), ("G5", 0.5), ("F5", 1), ("A5", 1)],
    [("G5", 1.5), ("D5", 0.5), ("B4", 1), ("D5", 1)],
    [("E5", 0.5), ("G5", 0.5), ("B5", 1), ("G5", 1), ("E5", 1)],
    [("A5", 0.5), ("G5", 0.5), ("E5", 0.5), ("D5", 0.5), ("C5", 1), ("E5", 1)],
    [("F5", 0.5), ("A5", 0.5), ("C6", 1), ("A5", 1), ("F5", 1)],
    [("G5", 0.5), ("B5", 0.5), ("D6", 1), ("B5", 1), ("G5", 1)],
    [("F5", 1), ("E5", 1), ("D5", 1), ("A4", 1)],
    [("D5", 0.5), ("E5", 0.5), ("G5", 0.5), ("A5", 0.5), ("B5", 2)],
]
B_CHORDS = ["F", "G", "Em", "Am", "F", "G", "Dm", "G"]


def stroll():
    rng = np.random.default_rng(7)
    t = Track(100, 32 * 4)
    flat = lambda bars: [n for bar in bars for n in bar]  # noqa: E731
    for section, (mel, chords, bell) in enumerate([(A, A_CHORDS, False), (A, A_CHORDS, True), (B, B_CHORDS, True), (A, A_CHORDS, False)]):
        s = section * 32
        t.melody(s, flat(mel), marimba, 0.5)
        if bell:  # a music box an octave up joins in the middle
            t.melody(s, flat(mel), musicbox, 0.14, octave=1)
        comp_bouncy(t, s, chords, rng)
    t.echo(0.75, 0.22)
    t.mp3("stroll")


# Calm: 16 bars of G major, a soft marimba rocking in eighths under a few music-box notes
CALM_CHORDS = ["G", "Em", "C", "D", "G", "Em", "C", "D", "Em", "C", "G", "D", "C", "D", "G", "G"]
CALM_TUNE = [
    ("B4", 2), ("D5", 2), ("E5", 3), ("D5", 1), ("E5", 2), ("G5", 2), ("A5", 3), ("r", 1),
    ("B5", 2), ("A5", 1), ("G5", 1), ("E5", 2), ("G5", 2), ("E5", 2), ("D5", 2), ("D5", 3), ("r", 1),
    ("G5", 2), ("B5", 2), ("C6", 2), ("A5", 1), ("G5", 1), ("B5", 2), ("D6", 2), ("A5", 3), ("r", 1),
    ("G5", 2), ("E5", 2), ("D5", 2), ("A4", 2), ("B4", 4), ("r", 4),
]


def calm():
    rng = np.random.default_rng(3)
    t = Track(80, 16 * 4)
    t.melody(0, CALM_TUNE, musicbox, 0.32)
    for i, ch in enumerate(CALM_CHORDS):
        root, *upper = [hz(n) for n in CHORDS[ch]]
        t.add(i * 4, bass(root, 4 * t.beat), 0.45)
        # rocking eighths: root, fifth, octave, third ... softly
        rock = [root * 2, upper[1], upper[2], upper[1]] * 2
        for e, f in enumerate(rock):
            t.add(i * 4 + e / 2, marimba(f, t.beat / 2), 0.16 if e % 2 else 0.2)
        for e in (1, 3):
            t.add(i * 4 + e, shaker(rng, 0.04), 0.035)
    t.echo(1.5, 0.25)
    t.mp3("calm", loud=0.6)


if __name__ == "__main__":
    stroll()
    calm()
