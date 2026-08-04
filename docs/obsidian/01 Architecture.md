---
tags: [mayhem, architecture]
---

# Architecture

## Layers

```
scripts/actors/       Player, Enemy, TargetDummy — thin, delegate to components
scripts/components/   Composable pieces attached as sibling Node children
scripts/systems/       Standalone world objects (hazards, platforms, pickups, doors)
scripts/resources/      Data schemas (WeaponData, EnemyData, WaveData, ...)
scripts/autoload/     Global singletons — see [[02 Autoloads]]
scripts/ui/            HUD, menus, screens
scripts/ai/            Beehave leaf nodes (actions/conditions) — see [[05 Enemies and AI]]
data/                   .tres instances of the resource schemas — the actual balance data
scenes/                 .tscn files wiring scripts to node trees
tests/                  GUT tests, mirrors scripts/ — see [[10 Testing]]
```

## Composition over inheritance

`Player` (`scripts/actors/player.gd`) is a `CharacterBody3D` that owns **look and
weapon input only**. Everything else is a sibling `Node` component, wired by
`@export` NodePath in the `.tscn`:

```
Player (CharacterBody3D)
├─ HeadPivot
│  └─ ViewBob (CameraFeelComponent output node — see 03)
│     └─ CameraRig (CameraRecoilComponent output node)
│        └─ Camera3D
├─ MovementComponent      — all physics: ground/air/slide/dash/grapple state machine
├─ CameraFeelComponent    — step bob, strafe lean, landing punch (cosmetic only)
├─ CameraRecoilComponent  — weapon recoil: aim offset (real) vs visual kick (cosmetic)
├─ GrappleComponent
├─ HealthComponent
├─ StatsComponent          — upgrade-modified stat lookups
├─ UtilityComponent
└─ WeaponHolder
   └─ WeaponComponent × N (one per owned weapon, always instantiated, visibility toggled)
```

`Enemy` (`scripts/actors/enemy.gd`) follows the same idea in reverse: **one scene,
five archetypes**. `EnemyData` (a `Resource`) supplies mesh, stats, behavior tree
and audio per archetype; the `Enemy` script is architecture-agnostic and reads
everything from `data`.

**Why this matters for editing:** a new weapon is a new `.tres` + a node in
`player.tscn`, not new code. A new enemy archetype is a new `EnemyData` resource +
a new Beehave tree scene, not a new script.

## EventBus

`scripts/autoload/event_bus.gd` — signals only, zero logic, zero state. Anything
that crosses a system boundary (combat → HUD, waves → economy, weapon →
recoil-visualizer) goes through here rather than a direct reference. See the full
signal list in [[02 Autoloads#EventBus]].

Two consequences worth knowing:

- **Nothing polls.** The HUD in particular never reads gameplay state in `_process`
  — every number on screen arrives via a signal. See [[07 UI and HUD]].
- **Adding a new cross-system effect is "add a signal + connect it,"** not "reach
  into another node." If you're tempted to `get_node("../../SomeOtherSystem")`
  across an actor/system boundary, that's the signal you're missing.

## Data-driven design

Every tunable game entity is a `Resource` subclass with `@export` fields, instanced
as a `.tres` in `data/`:

| Resource | Schema | Instances |
|---|---|---|
| `WeaponData` | `scripts/resources/weapon_data.gd` | `data/weapons/*.tres` |
| `EnemyData` | `scripts/resources/enemy_data.gd` | `data/enemies/*.tres` |
| `WaveData` + `SpawnGroup` | `scripts/resources/wave_data.gd`, `spawn_group.gd` | `data/waves/*.tres` |
| `UpgradeData` | `scripts/resources/upgrade_data.gd` | shop catalogue |
| `UtilityData` | `scripts/resources/utility_data.gd` | grenades/utilities |
| `RecoilPattern` | `scripts/resources/recoil_pattern.gd` | per-weapon recoil curve |
| `StatModifier` | `scripts/resources/stat_modifier.gd` | runtime, produced by upgrades |
| `EconomyConfig` | `scripts/resources/economy_config.gd` | `data/economy/economy_config.tres` |

None of this data is read at build time — it loads at runtime via `load()`/`preload()`
and is validated by tests (`tests/unit/test_wave_content.gd`,
`tests/unit/test_enemy_data.gd`, `tests/unit/test_weapon_data.gd`) rather than by
the type system, since `.tres` authoring mistakes (a null `projectile_scene`, an
empty `spawn_door_ids`) are otherwise silent.

## The telegraph contract

Every interactive/dangerous object in the arena — grapple anchors, zip lines,
moving/disappearing platforms, hazard pools, spawn doors — runs through the same
`TelegraphComponent`: one mesh, one unlit emissive material, one state enum
(`IDLE` / `AVAILABLE` / `WARNING` / `ACTIVE`), one of four meanings (`TRAVERSAL` /
`HAZARD` / `PICKUP` / `SPAWN`), each meaning permanently bound to one color. See
[[09 Design Tokens and Color Law]] and [[07 UI and HUD#TelegraphComponent]].

## Object pooling

`ObjectPool` (autoload) hands out and recycles projectiles, enemies and VFX rather
than `instantiate()`/`queue_free()` per spawn. See [[02 Autoloads#ObjectPool]].

## Physics layers

Named in `project.godot` under `[layer_names]` (`world`, `player`, `enemy`,
`player_projectile`, `enemy_projectile`, `hitbox`, `hurtbox`, `pickup`,
`grapple_anchor`, `hazard`, `interactable`, `trigger`). Code references these via
`PhysicsLayers` constants (`scripts/util/` or similar) — never raw bitmask integers.
