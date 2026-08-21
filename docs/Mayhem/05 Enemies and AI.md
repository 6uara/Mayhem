---
tags: [mayhem, enemies, ai]
---

# Enemies and AI

## One scene, six archetypes

`scenes/enemies/enemy.tscn` + `scripts/actors/enemy.gd` (~1275 lines, the largest
script in the codebase by a wide margin) is shared by every archetype. `EnemyData`
(`scripts/resources/enemy_data.gd`) supplies everything that makes a Rusher a
Rusher: silhouette, stats, behavior tree, audio. `Enemy` itself is architecture-
agnostic — it reads `data.*` and never branches on archetype by name.

`Archetype` enum: `RUSHER, RANGER, ELITE, HEALER, SUMMONER, BOMBER`.

`EnemyData` field groups: **Stats** (health/speed/damage/range/cooldown/mass,
`stagger_resistance` — 0 = staggered by every hit, 1 = immovable, elites sit
high), **Movement** (see below), **Attack** (`attack_windup` — telegraphing is
mandatory, `attack_cooldown_jitter` and the `Leap` and `Fuse` subgroups — see
[[#Attack timing is deliberately desynchronised]], [[#The leap]] and
[[#The fuse]], `projectile_scene` for ranged archetypes, `preferred_distance`),
**Support** (Healer's `heal_amount`/`heal_radius`, Summoner's `summon_data`/
`summon_count`/`summon_interval`), **Presentation** (`mesh`, `body_color`,
`has_halo`/`has_tether` — Healer-only, since Ranger and Healer share body
proportions and the halo is what separates their silhouettes at range),
**Audio**, **Economy** (`reward_currency`).

Data instances: `data/enemies/{rusher,ranger,elite,healer,summoner,bomber}.tres`.
Behavior trees: `scenes/enemies/ai/tree_{archetype}.tscn`.

`EnemyData.mesh` is the grey-box silhouette and is drawn centred on the body
capsule (`collision_height * 0.5`), the same place `_resize_capsule` puts the
shapes and the same pivot `tools/bake_enemy_meshes.gd` bakes into a real model.
It used to be pinned at `y = 0.9` by the scene — half of the 1.8m capsule the
scene was authored with, and therefore right for no archetype that actually
exists. The Ranger got away with it, the Elite and the Summoner sat low, and
anything shorter than 1.8m floated. Archetypes with a `model_scene` never
noticed either way, since the primitive is hidden under a model.

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

## Attack timing is deliberately desynchronised

Enemies of one archetype share a period, so a group that spawns together attacks
in lockstep. Three rangers firing on the same frame means the player eats three
projectiles or none — neither reads as combat, and neither can be played around.

Two things break the alignment:

- `EnemyData.attack_cooldown_jitter` (default `0.35`) — each cooldown lands
  somewhere in a band around the archetype's value, so phases drift apart and
  never re-converge.
- `Enemy.setup()` seeds `_attack_cooldown_left` with a random fraction of one
  cooldown, so even the **first** attack of a wave arrives staggered. Without it
  the jitter only separates enemies after their first attack, which still goes
  off in unison. (Same trick as the separation timer directly below it, and for
  the same reason.)

The jitter is **centred, not additive**. A `[1.0, 2.0]` band would separate the
phases just as well and halve every archetype's damage per second on the way —
desynchronising should not quietly cost difficulty.
`test_the_cooldown_jitter_does_not_change_how_often_the_archetype_attacks` pins
the average back to the archetype's `attack_cooldown`, which is the property that
makes this a timing change rather than a balance change.

## The leap

The Rusher throws itself at the player instead of punching from where it stands
(`Enemy.start_leap()`, `ActionLeapAttack`, `EnemyData.can_leap` and the `Leap`
subgroup). The arc is solved at take-off — same ballistic solve as
[[#Jump links]] — and **never corrected in flight**, which is the whole point:
moving during the flight is what makes it miss. The melee hit it replaces simply
appeared once the enemy had reached you, with nothing to do about it.

- Damage is **contact, not reach** (`_check_leap_contact()`), and lands once no
  matter how many frames the bodies overlap.
- A miss costs the enemy `leap_recovery` seconds standing still and vulnerable.
  That window is what pays the player for reading the wind-up; without it the
  leap is free and the telegraph means nothing.
- `start_leap()` refuses without floor under it, beyond `leap_range`, or without
  line of sight — otherwise it launches into the wall in between.

`ActionTelegraph` was already the wind-up and is unchanged; only the strike it
leads into is new. The **Elite keeps its slam** — the acid pool is what makes it
area denial rather than a large Rusher.

`ConditionPlayerInRange` gained `use_leap_range` so the tree opens the branch at
the archetype's leap range (7m) rather than its punch range (2.2m). Expressing
that as a hand-computed multiplier over `attack_range` would go silently wrong
the moment either number moved.

## The fuse

The Bomber (`EnemyData.has_fuse` and the `Fuse` subgroup, `Enemy.arm_fuse()` /
`_tick_fuse()` / `_detonate()`, `ActionArmFuse`) is a countdown with legs. It has
no attack: it walks at you, arms within `fuse_arm_range`, and `fuse_time` later
it goes off wherever it happens to be standing.

The design rests on one rule — **an armed fuse cannot be put out**:

- Running away does not disarm it. If it did, the answer to a Bomber would be
  "leave", and the archetype would have no question in it.
- Stagger and stun do not pause it. `_tick_fuse()` runs before the movement
  branches in `_physics_process` and outside all of them, so being knocked
  around, mid-air or frozen changes nothing.
- **Killing it detonates it early**, which is what turns the Bomber from a threat
  into a tool: shooting one while it stands in a crowd is a play. Killing one
  that never armed also detonates — a bomb that sometimes isn't reads far worse
  than one that always is, and always-explodes is what makes that play
  deliberate rather than accidental.

So the only question it asks is *where*, and the answer has to be reachable:
`test_the_fuse_outlasts_the_walk_from_where_it_arms` pins `fuse_time` above the
time it takes to cross `fuse_arm_range` at `move_speed`, because those are three
numbers tuned separately in a `.tres` and the relationship between them breaks
silently.

**One detonation, one site.** `_detonate()` does not spawn the blast; it kills
the Bomber, and `_on_died()` is the only place the blast comes from. That is what
makes the bomb that runs out and the bomb that eats a shotgun the exact same
death for the economy, the wave counter and the pool. `_has_detonated` is the
latch that stops the self-inflicted kill from re-entering and exploding twice.

`Explosion` (`scripts/actors/explosion.gd`) is deliberately **not** a
`HazardZone`. A hazard warns for 0.6s and then punishes standing still; an
explosion has already warned — the fuse was the warning, and far longer than
0.6s — and resolves in the instant it arrives. What it does inherit is the law:
the radius that hurts is the radius that was drawn. The `FuseRing` decal on the
enemy is authored from `explosion_radius` and dragged around by the walking bomb,
which is what lets the player pick the spot rather than only the moment. The
blink accelerates from `Tokens.TELL_BOMBER_FUSE_SLOW` to `_FAST`, the same
language the vanishing platform already taught.

The blast damages the player and the horde alike, and **that is the only friendly
fire inside the horde** — a Ranger cannot hit a team-mate with a stray shot. It
line-of-sight checks each victim for the same reason `deal_melee_damage()` does:
a blast that turns a corner is damage with nothing on screen to explain it.

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
  `action_leap_attack`, `action_ranged_attack`, `action_telegraph`,
  `action_heal_allies`, `action_summon_adds`, `action_elite_slam`,
  `action_arm_fuse`.
  `action_melee_attack` is still the standing hit, but no tree uses it since the
  Rusher moved to `action_leap_attack` — it stays as the plain melee an archetype
  without `can_leap` would use.
- **Conditions**: `condition_player_in_range` (`range_multiplier`,
  `absolute_range`, `use_leap_range`, `use_fuse_range`, `invert`),
  `condition_attack_ready`, `condition_not_staggered`.

`tree_bomber` is the smallest tree in the game and half the archetype's
personality: no attack branch, no attack telegraph, no cooldown. It closes, it
arms, and everything after that lives in `Enemy._tick_fuse()` — outside the tree,
because a tree can abandon a branch and a fuse cannot be abandoned.
`ActionArmFuse` returns SUCCESS only on the frame it arms and FAILURE forever
after, so the selector falls through to chasing: an armed bomb that stops walking
hands the player the one decision the archetype exists to ask for.

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
