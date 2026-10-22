---
tags: [mayhem, vfx, shaders]
estado: referencia
actualizado: 2026-10-20
---

# VFX and Shaders

Custom `.gdshader` files, all in `assets/shaders/`.

## `arena_glitch_panel.gdshader`

Applied to the arena's walls, mid platforms and high platforms (**not the
floor** — reverted to a flat `StandardMaterial3D`, since the floor is what the
player looks at for an entire arena-clear, and a moving grid directly underfoot
reads as noise where the same pattern on a wall reads as texture).

Triplanar (blends by world-normal, so one shader tiles across floor-orientation
and wall-orientation CSG geometry without stretching at seams): a circuit-grid
line pattern, a per-cell "glitch pulse" (each grid cell picks a random
brightness per tick — animation is currently frozen, `glitch_speed = 0`,
`scanline_speed = 0`, ready to re-enable), and a fresnel rim term scaled per-cell
so panels catch light with individually fixed brightness rather than one
uniform sheen.

## `lava_pool.gdshader`

Drives the snare pool (`scenes/arena/snare_zone.tscn`). Two copies of a
crack-noise texture (`assets/textures/Noise128x128/Cracks/`) scroll at different
speeds and multiply together — one texture alone loops obviously; two drifting
against each other almost never realign, which is what reads as something
flowing rather than a sliding image. Crust color (dark) mixes toward glow color
(bright) based on where the multiplied noise crosses `crack_threshold`.

Uniforms: `noise_texture`, `crust_color`, `glow_color`, `glow_energy`,
`crack_threshold`, `flow_speed`, `roughness_value`.

The hazard pool used to wear this shader too, retinted to acid; it now has its
own (below) and this one keeps only the dark-red molten skin.

## `acid_pool.gdshader`

The hazard pool (`scenes/arena/hazard_zone.tscn`): arena traps, the Elite's slam
and the flasks. A flat 2.3×2.3 quad (radius 1 = damage radius, the margin is for the stain) that `HazardZone`
scales to the damage radius — it replaced a 0.08 m `CylinderMesh` that read as a
coin lying on the floor.

- **A puddle outline, and damage follows it.** The edge is three angular
  harmonics (2, 3, 5) with random phases per spawn, normalised so the longest
  lobe touches `radius` and the shortest sits at `1 - shape_irregularity`
  (0.3 on the acid pool). `HazardZone.reach_at()` evaluates the same formula,
  and `_is_standing_in_it()` uses it: the dry floor between a lobe and the
  trigger cylinder does not burn. `radius` is the furthest reach, so the
  burning area is roughly 70% of the old disc at the same radius. A fine
  world-anchored wobble on top only ever moves the edge inward (3%).
  The corroded stain around the liquid is dark and unlit — it is floor, not
  warning; the glow ends where the damage ends. The snare pool keeps
  `shape_irregularity = 0`, a circle, because its drawing is still a disc.
- **Reads as liquid:** low roughness, rippling normal, a glowing meniscus along
  the edge, thin veins (the same two-layer crack-noise trick as `lava_pool`)
  and bubbles that grow and pop with an emissive ring.
- **`spread` / `evaporate`**, driven by `HazardZone`: the pool spreads from the
  centre during the 0.6 s warning (`Tokens.HAZARD_WARNING`), and a temporary
  pool dries up over `Tokens.HAZARD_EVAPORATE` before going back to the pool.
  It stops damaging the moment it expires, not when it finishes drying
  (`is_evaporating`).
- **The material is `resource_local_to_scene`.** Shared, every pooled pool
  would spread, blink and dry in step with the last one spawned.

Uniforms: `noise_texture`, `liquid_color`, `glow_color`, `stain_color`, `shape_*` (written by `HazardZone`),
`glow_energy`, `spread`, `evaporate`, `edge_wobble`, `edge_scale`, `stain_width`,
`stain_opacity`, `flow_speed`, `vein_threshold`, `ripple_strength`,
`bubble_cell`, `bubble_density`, `bubble_speed`.

## `fire_pool.gdshader`

The burning floor Scorched Earth leaves on every kill
(`scenes/arena/fire_pool.tscn`, script `FireZone extends HazardZone`). It used
to spawn the acid pool, which lied about where it came from: green acid means
"a Flask is alive nearby", this is ownerless broadcast fire that burns everyone.

- **Same contract as the acid.** Same quad, same `shape_*` contour, same
  `spread` / `evaporate`, same 0.6 s warning — only the look changes. Glowing
  embers in the cracks, a brighter fire front along the edge, a flicker
  anchored to world space, charred floor inside and unlit soot outside.
  When it expires the fire retreats toward the centre and the char fades last.
- **Vertical read from `FireZone`, not the shader:** `Flames` and `Embers`
  (`GPUParticles3D`, additive, `flame_03_a` / `spark_01_a`) and a flickering
  `OmniLight3D` without shadows. Their `amount_ratio` and the light energy
  follow `spread * (1 - evaporate)`, so they grow and die with the decal.
- **Flames never rise from floor that does not burn:** they emit from a disc of
  `radius * (1 - shape_irregularity)`, the smallest the contour can be.
- `BroadcastRule.kill_hazard_scene` lets another rule bring its own look;
  empty falls back to this one.
- Side-by-side capture: `tools/capture_hazards.tscn`.

## `arena_surface.gdshader`

Every greybox arena piece (`PieceMeshBuilder`): bolted metal plates with
bevelled seams, per-plate brightness variation and grime, procedural in world
space so seams run continuously across adjacent pieces and land on cell edges.
Elevated pieces add a diamond tread plate (`tread_strength`) as a second cue,
next to the edge trim, that they are walkways. Colour still comes from each
piece's `greybox_color`. Fine detail fades with screen-space footprint so it
does not shimmer at distance.

## `portal_spawn.gdshader`

Fills the "Opening" quad of every `SpawnDoor` (`scenes/arena/spawn_door.tscn`).
Additive, unshaded, `cull_disabled` — reads as a hole into somewhere else, not a
lit surface. Samples noise through **polar coordinates** instead of UV: angle +
`TIME * spin_speed` for rotation, radius offset by `TIME * pull_strength` for an
inward drain — the same swirl noise, sampled this way, reads as a vortex rather
than a spinning texture. A radial `ring` mask keeps the effect inside the
doorway.

Uniforms: `noise_texture`, `tint`, `spin_speed`, `pull_strength`, `glow_energy`.

## How TelegraphComponent drives a custom shader

`TelegraphComponent` (see [[01 Architecture#The telegraph contract]]) normally
builds a flat, unlit `StandardMaterial3D` per driven mesh and animates its
`emission_energy_multiplier` for the `WARNING` blink / `ACTIVE` pulse states.
That would **overwrite** a hand-authored lava/portal `ShaderMaterial` the
instant the scene entered the tree — which is exactly what happened to an
earlier lava material attempt (it only ever rendered in the editor viewport).

The fix, in `telegraph_component.gd`: `_build_materials()` checks whether a
driven mesh's `material_override` is already a `ShaderMaterial`. If so, it's
left alone and pushed into a separate `_shader_materials` list; `_set_energy()`
then calls `material.set_shader_parameter(&"glow_energy", energy)` on those
instead of touching `emission_energy_multiplier`. Both custom shaders above
expose a `glow_energy` float uniform by convention specifically so this works —
**any** telegraphed mesh can now own a custom shader and still receive the
standard warning-blink/active-pulse cues without `TelegraphComponent` knowing
anything about what the surface looks like.

## Per-instance material duplication

Godot shares local `sub_resource`s across every instantiation of the same
`PackedScene` by default. Both `SpawnDoor` (one per spawn point in the arena file) and pooled
`Enemy` instances therefore explicitly `.duplicate()` their material on `_ready()`
before mutating it — without this, telegraphing one spawn door would visually
light up all of them, since they'd all be pointing at the same `ShaderMaterial`
instance. See `spawn_door.gd::_ready()` for the pattern.

## Impact VFX keyed to surface material

`ImpactEffect` (`scripts/systems/impact_effect.gd` + `scenes/vfx/impact_effect.tscn`,
pooled) no longer hardcodes a world/flesh split. `play_at(hit_position, normal,
material: SurfaceMaterialData)` takes a `SurfaceMaterialData`
(`scripts/resources/surface_material_data.gd`) resolved by
`SurfaceMaterials.resolve(collider)` (`scripts/util/surface_materials.gd`) —
a static utility, same shape as `PhysicsLayers`. Every material lives as data
under `data/surfaces/` (`concrete.tres`, `metal.tres`, `flesh.tres`): `id`,
`impact_sound`, `decal_texture` (nullable — grey-box materials have none yet,
same phase the rest of this pass is in), `accent_color` (tints both the decal
and the spark particles), `spawns_decal` (always `false` for flesh, data-driven
rather than an `is_flesh` branch in the code).

**Tagging a collider**: `set_meta(SurfaceMaterials.META_KEY, &"metal")` — a
meta value, not a group (a group would collide with gameplay groups like
`&"player"`, and doesn't show in the inspector the way meta does).
`HitboxComponent._ready()` tags itself `&"flesh"` unconditionally, and `Player`
does the same for its own body (enemy projectiles raycast directly onto it,
with no `HitboxComponent` in between) — so `projectile.gd` and
`enemy_projectile.gd` both just call `SurfaceMaterials.resolve(collider)`
uniformly, with **no** `is_flesh` special-case left anywhere in either. An
untagged collider (most world geometry, until more of it is tagged) resolves
to `SurfaceMaterials.DEFAULT_ID` (`&"concrete"`) rather than erroring — the two
`StaticBody3D` scifi containers in `greybox_arena.tscn` are tagged `&"metal"`
via `metadata/surface = &"metal"` as the first real example.

**Per-instance retinting, not per-scene**: same pitfall as the section above —
`ImpactEffect._ready()` duplicates its spark `QuadMesh` and `StandardMaterial3D`
once per pooled instance (`_spark_material`), so setting `albedo_color` to one
hit's `accent_color` can never bleed into a different pooled instance mid-flight.

**Content debt, not a code gap**: `metal.tres` currently reuses
`impact_world.wav` — no metal-specific sample has been recorded. The system
already varies sound per material; only the audio content lags. See
[[12 Known Issues and Gaps]].

## Floating damage numbers

`DamageNumberSpawner` (`scripts/systems/damage_number_spawner.gd`, a node in
`game.tscn` beside `HitstopController`) listens to the same
`EventBus.damage_dealt` signal `HitstopController` already does, and shows a
`DamageNumber` (`scripts/ui/damage_number.gd` + `scenes/vfx/damage_number.tscn`
— a billboarded `Label3D`) over whatever got hit.

The pool is the spawner's own, not `ObjectPool`: a fixed ring of
`max_live_numbers` numbers instantiated once as its children, never leaving the
tree (a free one is just hidden), all advanced by the spawner's single
`_process` through `DamageNumber.tick()`. Hits on the same target inside
`merge_window` add into one number; an open number is tracked with its
`play_id` so a recycled one never takes another target's hits. Kill payouts
evict the oldest number when the ring is full.

That signal carries the target `Node`, not the exact hit position, so numbers
spawn at `target.global_position + height_offset` (enemy origins sit at the
feet) rather than the precise impact point — close enough to read as attached
to what got hit, without adding a new EventBus parameter just for this.
A small random per-number jitter keeps simultaneous hits (a shotgun blast, a
handful of enemies dying the same frame) from stacking into one unreadable
column. Rises and fades out over `DamageNumber.LIFETIME`, computed in `tick()`
rather than a `Tween`.

Headshots read differently by design, same as the hitmarker treatment in
`Reticle` — bigger (node scale `HEADSHOT_SCALE`, never a different font size), tinted `Tokens.REWARD` instead of
`Tokens.TEXT`. Gated by `hud/damage_numbers` in `SettingsManager` (off is a
legitimate preference — floating numbers are divisive — same accessibility
section as the screenshake toggle).

## Speed lines

`SpeedLinesOverlay` (`scripts/ui/speed_lines_overlay.gd`, a `ColorRect` inside
`HUD/Root/StateOverlays`) drives `assets/shaders/speed_lines.gdshader` — a
procedural radial streak vignette, `canvas_item`, no texture assets needed
(same grey-box-first approach as the rest of this VFX pass). Each of
`line_count` angular slices gets its own randomized width (`hash()` seeded by
the slice index) so the streaks read as uneven, organic lines rather than a
perfectly even fan; `inner_radius` keeps the centre (the HUD's own no-UI zone)
clear, and a second fade kills it again before the very edge.

`set_speed(horizontal_speed)` (called every physics frame from
`HUD._tick_movement()`, see [[03 Player and Movement#Speed-scaled FOV]]) maps
`[min_speed, max_speed]` to `[0, 1]` intensity — both `@export`ed tuning knobs,
not hardcoded, since "fast" depends on the mobility upgrade catalogue's own
numbers. The shown intensity chases that target via `move_toward()` on
`_physics_process` (not idle `_process` - doesn't reliably tick under the
headless test runner, same reason `HitstopController` ticks on physics too)
rather than snapping, so a strafe correction or a half-second of ground
friction reads as a smooth ramp rather than a flicker. Gated by its own
`accessibility/speed_lines_enabled` setting — a distinct discomfort trigger
from screenshake, so it doesn't ride along with that toggle.

## Color law tie-in

`tint` on the portal shader is set to match `Tokens.SPAWN` at the `.tscn`
authoring level (not derived live from the token at runtime — a known minor
gap, see [[12 Known Issues and Gaps]]). See [[09 Design Tokens and Color Law]]
for what those tokens mean and why they can't be reused for anything else.

The hazard pool's `glow_color` used to be the same arrangement against
`Tokens.HAZARD`, and **deliberately is not any more**: the pool is acid green
while the token stays lava orange. That is a decision, not drift — the token
drives the whole hazard *language* (telegraph WARNING/ACTIVE, the elite-wave
stripe, hazard chevrons, power-ups), and the pool is one surface inside it.

## Arena glow

`greybox_arena.tscn`'s `WorldEnvironment` (`Env_arena`) turns on `glow_enabled`
(`glow_intensity = 0.9`, `glow_hdr_threshold = 1.05`, `glow_bloom = 0.0`). The
wall/mid/high panel shaders and the lava/portal shaders already write real
`EMISSION` scaled by their own `emission_energy` / `glow_energy` uniforms — that
convention exists specifically so glow has something to catch — but nothing
ever turned glow on, so the Art Bible's "dark base, high-saturation emissive
accents" language wasn't actually landing on screen. The threshold sits just
above 1.0 so only genuinely emissive (HDR) surfaces bloom; flat albedo
materials (the floor, unlit props) never do.

**Not yet done** (needs a human at the editor to judge, not something to guess
blind — see [[12 Known Issues and Gaps]]): the rest of a real lighting pass
(key/fill beyond the single `DirectionalLight3D`, baked vs. dynamic shadow
decisions, per-zone legibility check against the enemy silhouettes) and the
arena dressing/geometry pass that's supposed to precede it. Both are visual
judgment calls this repo's tooling can't make unattended.

**A `.tscn`/`.tres` resource body does not support `#` comments** — unlike
`.gdshader` (which rejects `##` specifically but allows `//`), a text resource
file silently mis-parses anything after a `#` inside a `[sub_resource]` block,
which broke `glow_enabled`'s assignment the first time this was authored
(it parsed as unset). Keep rationale in docs or the consuming script, not
inline in `.tscn`/`.tres`.
