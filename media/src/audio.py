"""Make the sound for the Red Light video. No samples: every sound is synthesized.

Use: python3 audio.py <events.json> <out.wav> [duration_seconds]
"""
import json
import sys
import wave

import numpy as np

SR = 48000
events_path, out_path = sys.argv[1], sys.argv[2]
DUR = float(sys.argv[3]) if len(sys.argv) > 3 else 32.0
N = int(SR * DUR)
rng = np.random.default_rng(11)
L = np.zeros(N)
R = np.zeros(N)


def add(t, sig, pan=0.0, gain=1.0):
    i = int(t * SR)
    if i >= N:
        return
    sig = sig[: N - i] * gain
    L[i : i + len(sig)] += sig * (1 - max(0, pan))
    R[i : i + len(sig)] += sig * (1 + min(0, pan))


def tt(d):
    return np.arange(int(SR * d)) / SR


def lowpass(x, a):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y


def click():
    """One soft switch click: a short low thump and a small, dull top."""
    t = tt(0.16)
    thump = np.sin(2 * np.pi * (120 * np.exp(-t * 26) + 58) * t) * np.exp(-t * 30)
    top = lowpass(rng.standard_normal(len(t)), 0.22) * np.exp(-t * 210) * 0.45
    return (thump * 0.9 + top) * (1 - np.exp(-t * 2500))


def tick():
    """A small, quiet mark for each preset."""
    t = tt(0.08)
    return np.sin(2 * np.pi * 440 * t) * np.exp(-t * 70) * (1 - np.exp(-t * 900))


def chord(freqs, d, attack, release):
    t = tt(d)
    env = np.clip(t / attack, 0, 1) ** 2 * np.clip((d - t) / release, 0, 1) ** 2
    sig = np.zeros(len(t))
    for k, f in enumerate(freqs):
        sig += np.sin(2 * np.pi * f * t + k) + 0.2 * np.sin(2 * np.pi * f * 2 * t + k * 2)
    return sig / len(freqs) * env


# ---- the bed: a low, slow D drone ----
t = np.arange(N) / SR
bed = np.zeros(N)
for f, g, lfo in [(36.71, 0.7, 0.05), (73.42, 1.0, 0.06), (110.0, 0.5, 0.04), (146.83, 0.32, 0.08), (220.0, 0.1, 0.05)]:
    bed += g * np.sin(2 * np.pi * f * t + f) * (0.72 + 0.28 * np.sin(2 * np.pi * lfo * t + f))
bed *= np.clip(t / 3.0, 0, 1) ** 2 * np.clip((DUR - t) / 2.2, 0, 1) ** 2 * 0.09
L += bed
R += np.roll(bed, int(0.011 * SR))

# ---- the events ----
for i, e in enumerate(json.load(open(events_path))):
    k, at = e["type"], e["t"]
    if k == "click":
        add(at, click(), 0, 0.5)
    elif k == "tick":
        add(at, tick(), 0, 0.06)
    elif k == "end":
        add(at, chord([73.42, 110.0, 146.83, 220.0, 293.66], DUR - at, 1.6, 2.0), 0, 0.22)

mix = np.stack([L, R], axis=1)
peak = np.abs(mix).max()
mix = np.tanh(mix / max(peak, 1e-9) * 1.1) * 0.82
with wave.open(out_path, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((mix * 32767).astype("<i2").tobytes())
print("wrote", out_path, "peak before limit", round(float(peak), 3))
