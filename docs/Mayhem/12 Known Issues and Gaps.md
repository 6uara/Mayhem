---
tags: [mayhem, todo, gaps]
estado: referencia
actualizado: 2026-10-21
---

# Known Issues and Gaps

Technical debts and fragile spots in the code as it stands. **The backlog —
what is left to build, decide or record — lives in
[ESTADO.md](../ESTADO.md)**, and proposals in
[PLAN_MEJORAS.md](../planes/PLAN_MEJORAS.md). This note keeps only what a person
touching the code needs to know so as not to trip on it. Resolved items are
deleted, not struck through: git history keeps them.

## Performance

`tools/profile_elite_wave.gd` forces wave 10 with every enemy alive, makes the
player invincible, lifts the FPS cap and vsync, and samples real frame rate:

```
godot --path . -s tools/profile_elite_wave.gd -- 20
```

**Must run with real rendering, never `--headless`** — headless skips the
renderer and measures only script/physics.

**Last measured** (2026-10-09, Radeon 680M integrated, Ryzen 5 7535HS, native
fullscreen): wave 10 (42 enemies) ~40 FPS, ~43 with the integrated-GPU defaults;
empty arena ~46 FPS. **Below 60.** With the horde the limit is the CPU — the
physics step costs ~13 ms (Beehave, enemy movement, navigation, Jolt). Before
and after, and what is left: [PLAN_MEJORAS §4.0](../planes/PLAN_MEJORAS.md). The
profiler now prints ms per frame for process, physics and GPU.

`tools/profile_scene_cost.gd` measures the arena without a wave and with parts
removed (`nocrowd`, `novenue`, `noshadows`, `noglow`, `noviewmodel`,
`freeze=<node>`...). `tools/profile_damage_numbers.gd` isolates damage numbers
and hurt VFX. Still not covered: a real firefight with the camera moving.

## Needs a human, not another unattended pass

- **Audio mix.** `tools/configure_audio_mix.gd` applies a gain hierarchy and a
  Master limiter. That is mechanical, not a mix: loudness balance, EQ, reverb and
  a headphones-and-speakers listening pass still need ears.
- **Things only testable on screen or by hand:** the fast-fall landing camera punch, FSR at
  50-67%, MSAA/TAA, shadows on Low, a full wave on a gamepad.

## Fragile

- **Godot auto-resaves open scenes** when the project loads (even headless
  `--import`), and can silently revert hand edits to a `.tscn` open in a stale
  editor. It has destroyed content once. `git diff` every scene before
  committing if any Godot process ran. `tools/run_tests.ps1` restores files the
  run re-serialised.
- **Tests that read `SettingsManager`** see the `user://settings.cfg` of the
  machine running the suite. Rule: set every key the test reads, and restore it
  — `tests/settings_guard.gd` does both.
- **Navmesh connectivity flake** —
  `test_navigation_connectivity.gd::test_the_map_has_a_navmesh_at_all` can fail
  alone and intermittently under load. Failing *always* means a real break.
- **Leap test flake** —
  `test_enemy_stuck_recovery.gd::test_an_attack_leap_is_not_judged_as_a_failed_jump`
  failed once in a full run (2026-10-23: "esta parado" / "el salto sale") and
  passed 3/3 alone. The rusher spawns 1 m from the player, so its own tree can
  leap before the test does. Same rule as above.
- **`enemy.gd` is ~2400 lines**, and the locomotion/navigation block (`_steer`
  to `_stop_horizontal`, ~900 lines) is the part most edits touch. Splitting it
  is planned, after the playtest, on its own branch.

## Minor drift

- **Shader `tint`/`glow_color` uniforms are set by hand** in `.tscn` files, not
  read from `Tokens` at runtime ([[08 VFX and Shaders#Color law tie-in]]). If
  `Tokens.SPAWN` changes, the portal shader does not follow, and no test catches
  it.

  ⚠ **The hazard pool's green is not an instance of this.** `hazard_zone.tscn`
  glows `#C6FF3D` while `Tokens.HAZARD` is `#FC3A00`, on purpose — see
  [[09 Design Tokens and Color Law#Accent colors and their shapes]].
- **`data/surfaces/metal.tres` reuses `impact_world.wav`**, and every
  `SurfaceMaterialData.decal_texture` is null: the per-surface system is real,
  the samples and decals are placeholders. Arena pieces resolve to the
  `concrete` default.
- **Two sources of truth for kill rewards.** The game pays
  `EnemyData.reward_currency` (`enemy.gd` → `kill_credited`). The balance
  editor's economy curve (`balance_editor/core/curve_evaluator.gd`) reads
  `EconomyConfig.get_kill_reward()` instead, which only knows five of the eight
  archetypes and returns 0 for Bomber, Environmental and Flyer. The two agree
  today for the original five by coincidence of values; the curve under-counts
  every wave from 6 on. Tuning `EconomyConfig.kill_reward_*` changes the curve
  and not the game.
- **`test_arena_navigation.gd` still loads `greybox_arena.tscn`**, the
  hand-built arena that no longer ships. The tests are valid against that
  scene, but they no longer cover the arena the game actually loads.

## Housekeeping

- Seven shaders in `assets/shaders/` are referenced by no scene (`vhs`,
  `glitch`, `hologram`, `aurora_sky`, `dissolve`, `lightning`, `ui_onfire`).
  They cost nothing until wired; any full-screen one gets profiled before it
  merges.
- `addons/phantom_camera/` is on disk but **not enabled and not used** — see
  [ADDONS.md](../ADDONS.md).
