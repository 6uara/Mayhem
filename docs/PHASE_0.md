# Phase 0 - Foundation

**Goal:** everything a gameplay feature needs to exist, and nothing else. No gameplay.

## Done

- **Repo hygiene** - Godot 4 `.gitignore`, `.gitattributes` with LFS filters for all art and audio
  formats (set up *before* the first art commit, as required).
- **Project settings** - Forward+, Jolt physics, 1920x1080, `canvas_items` stretch, 60 FPS cap,
  untyped-declaration warnings enabled.
- **Physics layers** - all 12 named in `project.godot`, mirrored as bit constants in
  `scripts/util/physics_layers.gd`. Never hardcode a mask integer.
- **Input map** - all 22 actions defined before any input code exists. See `CLAUDE.md` 4.5.
- **Folder structure** - per `CLAUDE.md` 4.1. `scripts/resources/` holds class definitions,
  `data/` holds `.tres` instances; these never mix.
- **Autoloads** - all 10 registered, in dependency order (EventBus first, gameplay managers last).
- **EventBus** - the full signal catalogue from `CLAUDE.md` 4.2, plus `game_state_changed` and
  `settings_applied`.
- **Resource classes** - `WeaponData`, `RecoilPattern`, `EnemyData`, `UpgradeData`,
  `StatModifier`, `UtilityData`, `WaveData`, `SpawnGroup`, `EconomyConfig`.
- **ObjectPool** - generic acquire/release/prewarm keyed by `PackedScene`, with `_on_acquired()` /
  `_on_released()` hooks on pooled scenes.
- **AudioPool** - 48 pooled 3D players, 16 2D, bus routing, reference-counted VO ducking.
  `default_bus_layout.tres` implements `Master -> {SFX -> {Weapons, Impacts, Enemies, World},
  Music, VO, UI}`.
- **GUT** 9.7.1 vendored, `.gutconfig.json`, 27 passing tests, GitHub Actions running them
  headless on every PR.

## Deviations from the handoff, flagged

1. **`ObjectPool` is an autoload.** `CLAUDE.md` 4.2 lists nine autoloads and does not include it,
   but section 2 calls for it as an early custom system and projectiles need a single shared pool
   across scenes. It holds pooling state only - no gameplay knowledge.
2. **Three addons are not installed** (Phantom Camera, Beehave, Debug Draw 3D). Reasoning and
   install instructions in `docs/ADDONS.md`. Phantom Camera is a Phase 1 blocker.
3. **`WaveManager` is a skeleton.** Sequencing, clear detection and bonus payout are implemented;
   spawning delegates to a `spawner` node that does not exist until Phase 3 (spawn doors).

## Open items for the next session

- Install Phantom Camera before starting Phase 1 camera work.
- Author the arena/game/menu scenes - `GameManager` references
  `res://scenes/main/game.tscn` and `res://scenes/main/main_menu.tscn`, which do not exist yet.
  It pushes an error and stays on the current scene rather than crashing.
- Weapon `.tres` instances (`data/weapons/`) are empty; the first one lands in Phase 1 with the
  rifle and the recoil pattern visualizer.

## Phase 1 exit criteria (reminder)

Shooting a wall and a dummy feels good with zero enemies in the game. Do not proceed past that
until it is true.
