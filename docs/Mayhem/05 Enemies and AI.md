---
tags: [mayhem, enemies, ai]
---

# Enemies and AI

## One scene, five archetypes

`scenes/enemies/enemy.tscn` + `scripts/actors/enemy.gd` (~725 lines, the largest
script in the codebase) is shared by every archetype. `EnemyData`
(`scripts/resources/enemy_data.gd`) supplies everything that makes a Rusher a
Rusher: silhouette, stats, behavior tree, audio. `Enemy` itself is architecture-
agnostic — it reads `data.*` and never branches on archetype by name.

`Archetype` enum: `RUSHER, RANGER, ELITE, HEALER, SUMMONER`.

`EnemyData` field groups: **Stats** (health/speed/damage/range/cooldown/mass,
`stagger_resistance` — 0 = staggered by every hit, 1 = immovable, elites sit
high), **Movement** (see below), **Attack** (`attack_windup` — telegraphing is
mandatory, `projectile_scene` for ranged archetypes, `preferred_distance`),
**Support** (Healer's `heal_amount`/`heal_radius`, Summoner's `summon_data`/
`summon_count`/`summon_interval`), **Presentation** (`mesh`, `body_color`,
`has_halo`/`has_tether` — Healer-only, since Ranger and Healer share body
proportions and the halo is what separates their silhouettes at range),
**Audio**, **Economy** (`reward_currency`).

Data instances: `data/enemies/{rusher,ranger,elite,healer,summoner}.tres`.
Behavior trees: `scenes/enemies/ai/tree_{archetype}.tscn`.

## Movement fields — a contract, not taste

```gdscript
@export var max_auto_step: float = 0.6   # must be >= the navmesh bake's agent_max_climb
@export var can_jump: bool = true
@export var jump_velocity: float = 8.0
@export var max_step_height: float = 1.2  # must stay under jump_velocity^2 / (2*GRAVITY)
```

Both constraints are enforced by tests
(`tests/integration/test_enemy_obstacles.gd`), because both were real bugs once:
a navmesh promising a step the physics body couldn't climb, and a `max_step_height`
that exceeded the real ballistic apex under the archetype's own jump velocity.

## Obstruction handling (`_check_obstruction`)

Runs every physics frame while an enemy wants to move but isn't making progress.
In order:

1. **Step-up** (`_try_step_up()`) — tried every frame, since a ledge is far more
   common than a real obstacle and stepping is instant. Raycasts ahead at
   `max_auto_step` height for headroom, then down from above to find the ledge
   top, then validates the destination with `test_move()` before committing
   (an earlier version teleported blind and bounced back out via depenetration).
2. **Link traversal** (`_try_traverse_link()`) — see [[#Jump links]] below.
3. **Jump** (`_try_jump_obstacle()`) — only after `STUCK_TIME = 0.3s` of no
   progress, gated by `JUMP_COOLDOWN = 0.9s`. Probes at shin height (0.12m) for
   an obstacle and at `max_step_height` for clearance.

## Jump links

`scripts/systems/jump_link.gd` (`class_name JumpLink extends NavigationLink3D`),
placed in `scenes/arena/jump_link.tscn`. Bridges navmesh islands the ramps used
to connect — the arena's raised platforms are otherwise unreachable once a level
has no walkable path up to it.

`get_launch_velocity(from, to, gravity)` solves the ballistic arc from the link's
own endpoints and a configured `flight_time`, rather than a tuned constant — it
stays correct if the link's placement or length changes later. `Enemy._try_traverse_link()`
finds the nearest link ahead (`_find_link_ahead()` — a single scan answers both
"is a link the next step" and "which one," a redundant double-scan here was
removed as dead-weight cost, see repo history), sets `velocity` to the solved
launch vector, and `_tick_link_traversal()` just rides it out until landing —
the arc is solved once at launch, nothing steers mid-flight.

`Enemy.deal_melee_damage()` gates the actual hit landing with a line-of-sight
raycast (`_can_see()`) — added after enemies wedged under a platform could hit a
player standing on top through solid floor geometry. This does **not** change
the "enemies always know player position" perception rule; it only gates whether
a landed hit connects.

## Enemy meshes

`EnemyData.mesh` is typed `Mesh` (not `PackedScene`) — an imported `.fbx` scene
can't be assigned directly, since Godot's fbx importer produces a full node
hierarchy with a root-level transform (rotation from the Z-up→Y-up conversion,
plus whatever scale the source file's units imply), not a standalone mesh
resource. SpiderBot (Rusher) and UAL1_Standard (Elite) were baked offline:
`SurfaceTool.append_from(mesh, surface, transform)` walks the composed local
transform down to the mesh node and bakes it into a new `ArrayMesh`, then the
result is recentred on its own AABB and rescaled to the archetype's
`collision_height` (this matches how the box/capsule placeholders were already
authored — pivot at the shape's own center). Saved as `.res` files under
`assets/models/meshes/`.

## Beehave

Behavior trees live under `scenes/enemies/ai/`, built from leaves in
`scripts/ai/actions/` and `scripts/ai/conditions/`:

- **Actions**: `action_chase_player`, `action_keep_distance`, `action_melee_attack`,
  `action_ranged_attack`, `action_telegraph`, `action_heal_allies`,
  `action_summon_adds`, `action_elite_slam`.
- **Conditions**: `condition_player_in_range`, `condition_attack_ready`,
  `condition_not_staggered`.

`BeehaveGlobalMetrics` / `BeehaveGlobalDebugger` are addon autoloads, registered
last in `project.godot` load order.

## Stagger, slow, stun

`Enemy.apply_stun(duration)`, `apply_slow(multiplier)` / `clear_slow()`,
`is_staggered()` — `stagger_resistance` (0–1) on `EnemyData` scales how much a
hit actually staggers a given archetype (Elites resist almost entirely).

## Navmesh baking

Offline only — `tools/bake_navmesh.gd`, run manually, output committed to
`scenes/arena/greybox_arena_navmesh.tres`. `ArenaNavigation`
(`scripts/systems/arena_navigation.gd`, a `NavigationRegion3D` subclass) loads
the committed bake at runtime; `bake_on_ready` is a dev-only escape hatch for
iterating on layout and must stay `false` in anything committed — baking CSG
geometry at runtime pulls meshes back from the GPU, which Godot itself warns is
a real cost. `AGENT_RADIUS = 0.85` in the bake tool is sized for the largest
archetype (Elite, 0.75).
