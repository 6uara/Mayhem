"""Generate placeholder loop music for the grey-box build.

Same reasoning as generate_placeholder_sfx.py: synthesised stand-ins, not final
tracks, so MusicManager has something real to crossfade between before real music
gets licensed/composed (backlog tanda E1). Three loops, one per state MusicManager
follows: menu (calm), combat (driving), shop (arpeggiated, mid-energy).

Usage:
    python tools/generate_placeholder_music.py

Stdlib only. Rerunning overwrites the files deterministically (fixed RNG seed).
"""

from __future__ import annotations

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44100
OUT_DIR = os.path.join("assets", "audio", "music")


def _write(name: str, samples: list[float]) -> None:
    path = os.path.join(OUT_DIR, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in _normalise(samples)
    )
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(frames)
    print(f"  {path} ({len(samples) / SAMPLE_RATE:.2f}s)")


def _normalise(samples: list[float], peak: float = 0.85) -> list[float]:
    loudest = max((abs(s) for s in samples), default=0.0)
    if loudest <= 0.0:
        return samples
    scale = peak / loudest
    return [s * scale for s in samples]


def _sum(layers: list[list[float]]) -> list[float]:
    length = max((len(layer) for layer in layers), default=0)
    out = [0.0] * length
    for layer in layers:
        for i, sample in enumerate(layer):
            out[i] += sample
    return out


def _seamless_loop(build, duration_s: float, fade_s: float = 0.35) -> list[float]:
    """Renders `duration_s` worth of a continuous-phase signal via `build(n)`,
    plus a little extra, then crossfades that extra tail into the head - so the
    file can loop (stream.loop = true) with no click or seam at the wrap.

    `build` must produce a phase-continuous signal for the FULL length asked for
    (i.e. every oscillator keeps accumulating phase across the whole render) -
    this only smooths the seam, it does not make an arbitrary length loop.
    """
    total = int(SAMPLE_RATE * duration_s)
    fade = int(SAMPLE_RATE * fade_s)
    samples = build(total + fade)
    body = samples[:total]
    tail = samples[total:total + fade]
    for i in range(fade):
        t = i / fade
        body[i] = body[i] * (1.0 - t) + tail[i] * t
    return body


def _sine(n: int, freq: float, gain: float, phase: float = 0.0) -> list[float]:
    step = 2.0 * math.pi * freq / SAMPLE_RATE
    return [math.sin(phase + step * i) * gain for i in range(n)]


def _lowpass(samples: list[float], cutoff: float) -> list[float]:
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / SAMPLE_RATE)
    out = []
    value = 0.0
    for sample in samples:
        value += alpha * (sample - value)
        out.append(value)
    return out


def _kick(rng: random.Random) -> list[float]:
    """A short thump: pitched sine sweeping down, plus a click transient."""
    length = int(SAMPLE_RATE * 0.18)
    out = []
    phase = 0.0
    for i in range(length):
        t = i / length
        freq = 110.0 * (0.35 ** t)
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        env = math.exp(-t * 9.0)
        out.append(math.sin(phase) * env)
    click = [rng.uniform(-1.0, 1.0) * math.exp(-i / (SAMPLE_RATE * 0.004))
             for i in range(int(SAMPLE_RATE * 0.01))]
    for i, sample in enumerate(click):
        out[i] += sample * 0.5
    return [s * 0.9 for s in out]


def _hat(rng: random.Random) -> list[float]:
    length = int(SAMPLE_RATE * 0.05)
    noise = [rng.uniform(-1.0, 1.0) * math.exp(-i / (SAMPLE_RATE * 0.012)) for i in range(length)]
    return _lowpass(noise, 9000.0)


def _place(canvas: list[float], layer: list[float], offset: int) -> None:
    for i, sample in enumerate(layer):
        if offset + i >= len(canvas):
            break
        canvas[offset + i] += sample


# ---------------------------------------------------------------- tracks

def menu_track(rng: random.Random) -> list[float]:
    """Calm ambient pad. No percussion - this plays under a title screen."""
    def build(n: int) -> list[float]:
        base = 110.0  # A2 - the same root the other two tracks resolve toward
        layers = [
            _sine(n, base, 0.30),
            _sine(n, base * 1.5, 0.18, phase=0.4),          # fifth
            _sine(n, base * 2.0, 0.10, phase=1.1),          # octave
            _sine(n, base * 2.5, 0.06, phase=2.0),          # major third, up an octave
        ]
        pad = _sum(layers)
        # Slow breathing so a static drone doesn't read as a stuck note.
        for i in range(n):
            lfo = 0.75 + 0.25 * math.sin(2.0 * math.pi * i / n * 3.0)
            pad[i] *= lfo
        return pad
    return _seamless_loop(build, duration_s=24.0, fade_s=1.0)


def combat_track(rng: random.Random) -> list[float]:
    """Driving, 128 BPM. Kick on the beat, hats on the off-beat, a tense pad on top."""
    bpm = 128.0
    beat_s = 60.0 / bpm
    bars = 8
    duration_s = beat_s * 4 * bars

    def build(n: int) -> list[float]:
        base = 110.0
        pad = _sum([
            _sine(n, base * 2.0, 0.09),
            _sine(n, base * 2.98, 0.07, phase=0.7),   # slightly sharp fifth: tension, not consonance
        ])
        canvas = pad
        beat_samples = int(SAMPLE_RATE * beat_s)
        beats = int(math.ceil(n / beat_samples)) + 1
        for beat in range(beats):
            offset = beat * beat_samples
            _place(canvas, [s * 0.8 for s in _kick(rng)], offset)
            _place(canvas, [s * 0.35 for s in _hat(rng)], offset + beat_samples // 2)
        return canvas
    return _seamless_loop(build, duration_s=duration_s, fade_s=beat_s * 0.5)


def shop_track(rng: random.Random) -> list[float]:
    """Mid-energy arpeggio - browsing music, not combat music."""
    bpm = 100.0
    step_s = 60.0 / bpm / 2.0  # eighth notes
    bars = 4
    duration_s = (60.0 / bpm) * 4 * bars
    # A minor-leaning arpeggio resolving toward the same root the other tracks use.
    notes = [220.0, 261.63, 329.63, 392.0]  # A3, C4, E4, G4

    def build(n: int) -> list[float]:
        canvas = [0.0] * n
        step_samples = int(SAMPLE_RATE * step_s)
        steps = int(math.ceil(n / step_samples)) + 1
        for step in range(steps):
            freq = notes[step % len(notes)]
            offset = step * step_samples
            length = int(step_samples * 1.1)
            note = []
            phase = 0.0
            step_freq = 2.0 * math.pi * freq / SAMPLE_RATE
            for i in range(length):
                phase += step_freq
                env = math.exp(-i / (SAMPLE_RATE * 0.22))
                note.append(math.sin(phase) * env * 0.35)
            _place(canvas, note, offset)
        pad = _sine(n, 110.0, 0.08)
        return _sum([canvas, pad])
    return _seamless_loop(build, duration_s=duration_s, fade_s=step_s)


def main() -> None:
    rng = random.Random(20260810)
    print("Generating placeholder music:")
    _write("menu.wav", menu_track(rng))
    _write("combat.wav", combat_track(rng))
    _write("shop.wav", shop_track(rng))
    print("Done. These are placeholders - replace them with licensed/composed tracks.")


if __name__ == "__main__":
    main()
