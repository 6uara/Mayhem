---
tags: [mayhem, todo, gaps]
---

# Known Issues and Gaps

State as of this writing. Update this note as items get resolved — it's meant
to stay current, not be a historical log (that's what `docs/PHASE_*.md` and git
history are for).

## Performance

Backlog tanda G2: does the game "hold 60 FPS on a full elite wave"?
`tools/profile_elite_wave.gd` forces wave 10 (27 enemies — the largest
authored wave), makes the player invincible (so it can't die and reset the
wave mid-measurement — a real risk, since nothing in the scenario fights
back), removes the video/fps_cap and vsync default (both would otherwise
silently ceiling the reading at 60), and samples `Engine.get_frames_per_second()`
for 20 real seconds once all 27 are alive.

```
godot --path . -s tools/profile_elite_wave.gd -- 20
```

**Must run with real rendering, not `--headless`** — headless skips the
renderer, so it would only ever measure script/physics cost and miss glow,
particles, decals and the panel shaders entirely.

**Last verified result** (2026-08-10, AMD Radeon RX 7700 XT, Windows, D3D12
Forward+, this repo's own dev machine): two runs, `min 519–547 / avg 590–599 /
max 619–636 FPS`, **0.0% of frames under 60** both times. Comfortably clears
the target on this hardware — by roughly 9-10x at the floor, not a marginal
pass.

**What this does NOT tell you**, and needs a person to actually check:
- **Lower-end / integrated GPUs.** One machine, one (strong, discrete) GPU.
  A number this far above target is a good sign, not a guarantee for a
  laptop iGPU.
- **Full combat load.** The player stands still — no player weapon fire, no
  muzzle flash/projectile/impact VFX from the player's side, no camera
  movement. It measures the enemy-density floor, not "worst frame during a
  real firefight."
- Rerun this after tanda D1 (arena dressing) and F1 (real enemy models) land
  — both add real cost this number doesn't include yet.

## Needs a human at the editor, not more unattended passes

- **Arena dressing/geometry pass** (backlog tanda D1) — un-started on purpose.
  Turning greybox into a dressed level is a visual-judgment task (does this
  read as a space, does the new geometry kill sightlines/flow) that has no
  meaningful unattended version; the safe thing to automate would just be
  guessing. See [[08 VFX and Shaders#Arena glow]] for what *did* ship
  unattended this pass (glow) and why that one was safe to guess at (it
  completes an already-decided, documented convention rather than choosing
  new geometry or color).
- **Lighting pass beyond glow** (tanda D2) — same reasoning. Glow shipped
  because it's mechanical completion of shader uniforms that already existed
  for this purpose; key/fill lighting, shadow baking decisions, and a
  per-zone "can I actually see the enemy here" check all need a person
  looking at the rendered arena.
- **Real audio mix** (tanda E3) — `tools/configure_audio_mix.gd` set a
  first-pass gain hierarchy (VO/Weapons highest priority down to UI lowest,
  see the tool's own docstring for the exact table) plus a Master limiter so
  a worst-case elite wave can't clip. That's mechanical - applying an
  already-decided priority order as relative dB offsets, and a safety net.
  What it explicitly is NOT: a real mix. Perceptual loudness balance, EQ,
  reverb sends, and the "does this actually sound right, on headphones AND
  speakers" listening pass all need a person with ears at a review, same
  reasoning as the arena/lighting items above.

## No test coverage

- **`StatsComponent`** — zero test files, despite being the read path *every*
  purchased upgrade in the game flows through (`get_stat_from()`, chained into
  from `WeaponComponent`, `MovementComponent`, `Player`). If this breaks, the
  shop silently stops mattering — no test would catch it.
- **`GameManager`**, **`AudioPool`** — also uncovered, lower risk (simpler,
  less state).
- ~~`GrappleComponent`, `BouncePad`~~ — this note was stale; both have covered
  (`tests/unit/test_grapple_component.gd`, `test_bounce_pad.gd`).

## Missing UI

- **No leaderboard screen.** `SaveManager` persists scores to
  `user://leaderboard.json` and `MatchDirector` writes to it, but nothing reads
  it back for display. The "run for time" loop the economy/scoring is built
  around has no visible payoff screen.
- **Main menu is an explicit placeholder.** `scripts/ui/main_menu.gd`'s own
  top-of-file comment: *"Placeholder menu so GameManager's scene transitions
  have somewhere to land. The real menu is built in Phase 5."* It was not
  rebuilt during the visual-identity pass — still plain `Control`/`Button`
  nodes, no theme, no `ChamferStyleBox`. Everything else in [[07 UI and HUD]]
  uses the shared theme system; this doesn't yet.

## Minor drift

- ~~`Tokens.CROSSHAIR_COLORS`~~ — fixed (backlog tanda G6): the stale preset
  swapped for `HAZARD` itself, so it can't drift again the same way.
- **Shader `tint`/`glow_color` uniforms are set once, at `.tscn` authoring
  time**, matching `Tokens.HAZARD` / `Tokens.SPAWN` by hand rather than being
  derived from the token live at runtime (see
  [[08 VFX and Shaders#Color law tie-in]]). If either token changes again, the
  lava and portal shaders need a manual update to follow — there's no test
  currently catching that specific drift, unlike the Elite/hazard coupling
  which *is* tested.
- **`data/surfaces/metal.tres` reuses `impact_world.wav`** — no metal-specific
  impact sample has been recorded yet, so metal currently sounds identical to
  concrete despite looking different (see
  [[08 VFX and Shaders#Impact VFX keyed to surface material]]). The variation
  system is real; only that one sample is a placeholder. Same story for every
  `SurfaceMaterialData.decal_texture` — all null, grey-box tint only, until
  real decal art exists. Only two world `StaticBody3D`s (the scifi containers
  in `greybox_arena.tscn`) are tagged `&"metal"` so far; the rest of the arena
  resolves to the `concrete` default until more geometry gets tagged.

## Housekeeping

- ~~`assets/materials/Lava.tres`~~ — removed (backlog tanda G6). Confirmed
  unreferenced anywhere (`hazard_zone.tscn` uses the `lava_pool.gdshader`
  `ShaderMaterial` directly) before deleting.
- `assets/shaders/vhs.gdshader` — this note used to describe it as a stray,
  empty stub (`shader_type spatial;`, nothing else), presumed editor debris.
  That's stale: as of this writing it's a real, substantial `canvas_item`
  VHS post-processing shader (signal distortion, glass-crack, tape-artifact
  uniform groups) — active work in progress on another branch, not debris.
  Left untouched; re-check before assuming either description next time.
- Godot's editor performs **auto-resaves of open scenes** when the project is
  loaded (e.g. via `--import`), which can silently revert recent hand-edits to
  a `.tscn` if that scene is open in a stale editor window — this has
  destroyed real content once (a floor-material fix and four `TargetDummy`
  nodes disappeared from `greybox_arena.tscn` in one such resave). Always
  `git diff` a scene file before committing if any Godot editor process ran
  during the session, even one only invoked headlessly for `--import` or
  `--quit-after`.
