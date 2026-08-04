"""Generate placeholder weapon, impact and UI sounds for the grey-box build.

These are synthesised stand-ins, not final audio - the point is that every audio hook in
the game is wired, audible and testable before real samples exist, the same way grey-box
geometry stands in for the arena. Section 6 of CLAUDE.md: audio carries roughly half of
"gunplay feel", so it does not get deferred to the art phase.

Fire sounds are layered the way the handoff asks for - transient + body + tail - rather
than one flat sample, so the layering is already in place when real samples replace these.

Usage:
    python tools/generate_placeholder_sfx.py

Stdlib only. Rerunning overwrites the files deterministically (fixed RNG seed).
"""

from __future__ import annotations

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44100
OUT_DIR = os.path.join("assets", "audio", "sfx")


def _env(index: int, length: int, attack: float, decay: float) -> float:
    """Percussive envelope: fast attack, exponential decay."""
    attack_samples = max(int(attack * SAMPLE_RATE), 1)
    if index < attack_samples:
        return index / attack_samples
    remaining = (index - attack_samples) / max(length - attack_samples, 1)
    return math.exp(-remaining / max(decay, 1e-4))


def _noise(length: int, attack: float, decay: float, gain: float, rng: random.Random) -> list[float]:
    return [rng.uniform(-1.0, 1.0) * _env(i, length, attack, decay) * gain for i in range(length)]


def _tone(length: int, freq: float, attack: float, decay: float, gain: float,
          sweep: float = 1.0) -> list[float]:
    """Sine with an optional frequency sweep (sweep = end freq / start freq)."""
    out = []
    phase = 0.0
    for i in range(length):
        t = i / max(length - 1, 1)
        current = freq * (sweep ** t)
        phase += 2.0 * math.pi * current / SAMPLE_RATE
        out.append(math.sin(phase) * _env(i, length, attack, decay) * gain)
    return out


def _lowpass(samples: list[float], cutoff: float) -> list[float]:
    """One-pole low pass, enough to take the fizz off white noise."""
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / SAMPLE_RATE)
    out = []
    value = 0.0
    for sample in samples:
        value += alpha * (sample - value)
        out.append(value)
    return out


def _mix(*layers: tuple[list[float], int]) -> list[float]:
    """Sum layers, each placed at a sample offset."""
    length = max((offset + len(data) for data, offset in layers), default=0)
    out = [0.0] * length
    for data, offset in layers:
        for i, sample in enumerate(data):
            out[offset + i] += sample
    return out


def _normalise(samples: list[float], peak: float = 0.89) -> list[float]:
    loudest = max((abs(s) for s in samples), default=0.0)
    if loudest <= 0.0:
        return samples
    scale = peak / loudest
    return [s * scale for s in samples]


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


def ms(milliseconds: float) -> int:
    return int(SAMPLE_RATE * milliseconds / 1000.0)


def rifle_fire(rng: random.Random) -> list[float]:
    transient = _noise(ms(18), 0.0004, 0.10, 1.0, rng)
    body = _lowpass(_noise(ms(130), 0.001, 0.22, 0.85, rng), 2600.0)
    thump = _tone(ms(150), 190.0, 0.001, 0.25, 0.7, sweep=0.45)
    tail = _lowpass(_noise(ms(420), 0.02, 0.5, 0.16, rng), 900.0)
    return _mix((transient, 0), (body, 0), (thump, 0), (tail, ms(60)))


def rifle_reload(rng: random.Random) -> list[float]:
    """Three tactile stages: magazine out, magazine in, bolt release."""
    mag_out = _mix(
        (_noise(ms(60), 0.001, 0.12, 0.6, rng), 0),
        (_tone(ms(70), 320.0, 0.001, 0.15, 0.35, sweep=0.7), 0),
    )
    mag_in = _mix(
        (_noise(ms(80), 0.001, 0.1, 0.8, rng), 0),
        (_tone(ms(90), 150.0, 0.001, 0.18, 0.6, sweep=0.6), 0),
    )
    bolt = _mix(
        (_noise(ms(70), 0.0005, 0.09, 0.9, rng), 0),
        (_tone(ms(60), 620.0, 0.001, 0.12, 0.3, sweep=0.5), 0),
    )
    return _mix((mag_out, 0), (mag_in, ms(820)), (bolt, ms(1620)))


def empty_click(rng: random.Random) -> list[float]:
    return _mix(
        (_noise(ms(22), 0.0003, 0.06, 0.9, rng), 0),
        (_tone(ms(30), 900.0, 0.0005, 0.07, 0.25, sweep=0.5), 0),
    )


def impact_world(rng: random.Random) -> list[float]:
    return _mix(
        (_noise(ms(35), 0.0005, 0.09, 1.0, rng), 0),
        (_lowpass(_noise(ms(120), 0.002, 0.18, 0.4, rng), 1800.0), 0),
        (_tone(ms(90), 240.0, 0.001, 0.14, 0.35, sweep=0.5), 0),
    )


def impact_flesh(rng: random.Random) -> list[float]:
    """Constructs, not flesh - a duller metallic knock so hits on enemies read differently."""
    return _mix(
        (_lowpass(_noise(ms(90), 0.001, 0.14, 0.9, rng), 1100.0), 0),
        (_tone(ms(130), 130.0, 0.001, 0.2, 0.6, sweep=0.55), 0),
    )


def hitmarker(freq: float, length_ms: float, gain: float) -> list[float]:
    return _tone(ms(length_ms), freq, 0.0008, 0.13, gain, sweep=0.85)


def kill_marker() -> list[float]:
    return _mix(
        (hitmarker(880.0, 70, 0.8), 0),
        (hitmarker(1320.0, 90, 0.6), ms(55)),
    )


def dash(rng: random.Random) -> list[float]:
    """Short air-rush whoosh."""
    return _mix(
        (_lowpass(_noise(ms(160), 0.015, 0.3, 0.9, rng), 1400.0), 0),
        (_tone(ms(140), 220.0, 0.01, 0.25, 0.3, sweep=1.8), 0),
    )


def jump(rng: random.Random) -> list[float]:
    return _mix(
        (_lowpass(_noise(ms(60), 0.004, 0.12, 0.5, rng), 1600.0), 0),
        (_tone(ms(80), 260.0, 0.003, 0.14, 0.4, sweep=1.4), 0),
    )


def land(rng: random.Random) -> list[float]:
    return _mix(
        (_lowpass(_noise(ms(70), 0.001, 0.12, 0.8, rng), 900.0), 0),
        (_tone(ms(110), 120.0, 0.001, 0.18, 0.6, sweep=0.6), 0),
    )


def slide(rng: random.Random) -> list[float]:
    """Gritty scrape burst - stands in for a loop until the audio pass."""
    return _lowpass(_noise(ms(300), 0.02, 0.45, 0.8, rng), 2400.0)


def grapple_fire(rng: random.Random) -> list[float]:
    return _mix(
        (_noise(ms(30), 0.0006, 0.07, 0.8, rng), 0),
        (_tone(ms(180), 340.0, 0.002, 0.3, 0.5, sweep=2.2), 0),
    )


def grapple_release(rng: random.Random) -> list[float]:
    return _mix(
        (_noise(ms(25), 0.0008, 0.06, 0.5, rng), 0),
        (_tone(ms(120), 520.0, 0.002, 0.2, 0.4, sweep=0.55), 0),
    )


def bounce_pad(rng: random.Random) -> list[float]:
    return _mix(
        (_tone(ms(180), 180.0, 0.001, 0.3, 0.8, sweep=2.6), 0),
        (_lowpass(_noise(ms(80), 0.002, 0.14, 0.4, rng), 1200.0), 0),
    )


def enemy_spawn(rng: random.Random, pitch: float) -> list[float]:
    """Servo whine - each archetype gets its own pitch so spawns are identifiable."""
    return _mix(
        (_tone(ms(260), 300.0 * pitch, 0.01, 0.4, 0.6, sweep=1.7), 0),
        (_lowpass(_noise(ms(120), 0.005, 0.2, 0.35, rng), 2000.0), 0),
    )


def enemy_windup(rng: random.Random, pitch: float) -> list[float]:
    """Rising tell. This is the audio half of the telegraph - it must be obvious."""
    return _mix(
        (_tone(ms(420), 190.0 * pitch, 0.05, 0.9, 0.75, sweep=2.4), 0),
        (_lowpass(_noise(ms(200), 0.05, 0.4, 0.2, rng), 1500.0), ms(200)),
    )


def enemy_attack(rng: random.Random, pitch: float) -> list[float]:
    return _mix(
        (_noise(ms(40), 0.0008, 0.09, 0.9, rng), 0),
        (_tone(ms(140), 260.0 * pitch, 0.001, 0.2, 0.6, sweep=0.5), 0),
    )


def enemy_death(rng: random.Random, pitch: float) -> list[float]:
    """Construct collapsing - metallic clatter, falling pitch."""
    return _mix(
        (_lowpass(_noise(ms(280), 0.002, 0.35, 0.8, rng), 1600.0), 0),
        (_tone(ms(320), 340.0 * pitch, 0.002, 0.4, 0.5, sweep=0.3), 0),
        (_noise(ms(160), 0.02, 0.25, 0.4, rng), ms(120)),
    )


def door_open(rng: random.Random) -> list[float]:
    """Gate tell: a low horn plus servo grind, audible across the arena."""
    return _mix(
        (_tone(ms(700), 110.0, 0.03, 0.8, 0.85, sweep=1.25), 0),
        (_lowpass(_noise(ms(600), 0.08, 0.6, 0.4, rng), 1100.0), ms(120)),
    )


def heal_pulse() -> list[float]:
    return _mix(
        (_tone(ms(300), 520.0, 0.02, 0.5, 0.6, sweep=1.5), 0),
        (_tone(ms(240), 780.0, 0.03, 0.45, 0.35, sweep=1.5), ms(60)),
    )


def utility_throw(rng: random.Random) -> list[float]:
    return _mix(
        (_lowpass(_noise(ms(90), 0.01, 0.16, 0.5, rng), 1800.0), 0),
        (_tone(ms(70), 300.0, 0.005, 0.12, 0.25, sweep=1.4), 0),
    )


def stun_pop(rng: random.Random) -> list[float]:
    """Bright crack then ring-out - unmistakably 'that did something'."""
    return _mix(
        (_noise(ms(50), 0.0005, 0.09, 1.0, rng), 0),
        (_tone(ms(500), 900.0, 0.001, 0.6, 0.45, sweep=0.55), 0),
        (_tone(ms(420), 1350.0, 0.002, 0.5, 0.3, sweep=0.6), ms(30)),
    )


def wall_deploy(rng: random.Random) -> list[float]:
    return _mix(
        (_tone(ms(320), 150.0, 0.005, 0.4, 0.7, sweep=2.0), 0),
        (_lowpass(_noise(ms(200), 0.01, 0.3, 0.35, rng), 1200.0), 0),
    )


def slow_deploy(rng: random.Random) -> list[float]:
    """Descending pitch - the sound of things getting slower."""
    return _mix(
        (_tone(ms(520), 620.0, 0.02, 0.6, 0.6, sweep=0.35), 0),
        (_lowpass(_noise(ms(300), 0.05, 0.4, 0.25, rng), 900.0), 0),
    )


def ammo_pickup() -> list[float]:
    return _mix(
        (_tone(ms(90), 620.0, 0.002, 0.16, 0.55, sweep=1.3), 0),
        (_tone(ms(110), 930.0, 0.003, 0.18, 0.4, sweep=1.3), ms(60)),
    )


def purchase() -> list[float]:
    return _mix(
        (_tone(ms(110), 520.0, 0.002, 0.2, 0.5, sweep=1.25), 0),
        (_tone(ms(140), 780.0, 0.003, 0.24, 0.4, sweep=1.25), ms(70)),
    )


def denied() -> list[float]:
    return _tone(ms(160), 220.0, 0.002, 0.25, 0.6, sweep=0.75)


def main() -> None:
    rng = random.Random(20260802)
    print("Generating placeholder SFX:")
    _write("weapons/rifle_fire.wav", rifle_fire(rng))
    _write("weapons/rifle_reload.wav", rifle_reload(rng))
    _write("weapons/rifle_empty.wav", empty_click(rng))
    _write("impacts/impact_world.wav", impact_world(rng))
    _write("impacts/impact_flesh.wav", impact_flesh(rng))
    _write("ui/hitmarker_body.wav", hitmarker(760.0, 60, 0.7))
    _write("ui/hitmarker_headshot.wav", hitmarker(1180.0, 70, 0.85))
    _write("ui/hitmarker_kill.wav", kill_marker())
    _write("world/dash.wav", dash(rng))
    _write("world/jump.wav", jump(rng))
    _write("world/land.wav", land(rng))
    _write("world/slide.wav", slide(rng))
    _write("world/grapple_fire.wav", grapple_fire(rng))
    _write("world/grapple_release.wav", grapple_release(rng))
    _write("world/bounce_pad.wav", bounce_pad(rng))
    # Per-archetype pitches, so threats are identifiable without looking.
    for name, pitch in [("rusher", 1.25), ("ranger", 1.0), ("elite", 0.6),
                        ("healer", 1.5), ("summoner", 0.8)]:
        _write("enemies/%s_spawn.wav" % name, enemy_spawn(rng, pitch))
        _write("enemies/%s_windup.wav" % name, enemy_windup(rng, pitch))
        _write("enemies/%s_death.wav" % name, enemy_death(rng, pitch))
        _write("enemies/%s_attack.wav" % name, enemy_attack(rng, pitch))
    _write("enemies/healer_pulse.wav", heal_pulse())
    _write("world/spawn_door.wav", door_open(rng))
    _write("world/utility_throw.wav", utility_throw(rng))
    _write("world/stun_grenade.wav", stun_pop(rng))
    _write("world/temp_wall.wav", wall_deploy(rng))
    _write("world/slow_field.wav", slow_deploy(rng))
    _write("world/ammo_pickup.wav", ammo_pickup())
    _write("ui/purchase.wav", purchase())
    _write("ui/denied.wav", denied())
    print("Done. These are placeholders - replace them in Phase 5.")


if __name__ == "__main__":
    main()
