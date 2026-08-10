---
tags: [mayhem, vfx, shaders]
---

# VFX and Shaders

Three custom `.gdshader` files, all in `assets/shaders/`.

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

Drives the hazard pool decal (`scenes/arena/hazard_zone.tscn`). Two copies of a
crack-noise texture (`assets/textures/Noise128x128/Cracks/`) scroll at different
speeds and multiply together — one texture alone loops obviously; two drifting
against each other almost never realign, which is what reads as flowing molten
rock rather than a sliding image. Crust color (dark) mixes toward glow color
(bright) based on where the multiplied noise crosses `crack_threshold`.

Uniforms: `noise_texture`, `crust_color`, `glow_color`, `glow_energy`,
`crack_threshold`, `flow_speed`, `roughness_value`.

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
`PackedScene` by default. Both `SpawnDoor` (seven placed in the arena) and pooled
`Enemy` instances therefore explicitly `.duplicate()` their material on `_ready()`
before mutating it — without this, telegraphing one spawn door would visually
light up all seven, since they'd all be pointing at the same `ShaderMaterial`
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
`EventBus.damage_dealt` signal `HitstopController` already does, and pools a
`DamageNumber` (`scripts/ui/damage_number.gd` + `scenes/vfx/damage_number.tscn`
— a billboarded `Label3D`) over whatever got hit.

That signal carries the target `Node`, not the exact hit position, so numbers
spawn at `target.global_position + height_offset` (enemy origins sit at the
feet) rather than the precise impact point — close enough to read as attached
to what got hit, without adding a new EventBus parameter just for this.
A small random per-number jitter keeps simultaneous hits (a shotgun blast, a
handful of enemies dying the same frame) from stacking into one unreadable
column. Rises and fades out over `DamageNumber.LIFETIME` via a `Tween`.

Headshots read differently by design, same as the hitmarker treatment in
`Reticle` — bigger (`HEADSHOT_FONT_SIZE`), tinted `Tokens.REWARD` instead of
`Tokens.TEXT`. Gated by `hud/damage_numbers` in `SettingsManager` (off is a
legitimate preference — floating numbers are divisive — same accessibility
section as the screenshake toggle).

## Color law tie-in

`glow_color` on the lava shader and `tint` on the portal shader are set to match
`Tokens.HAZARD` and `Tokens.SPAWN` respectively at the `.tscn` authoring level
(not derived live from the token at runtime — a known minor gap, see
[[12 Known Issues and Gaps]]). See [[09 Design Tokens and Color Law]] for what
those tokens mean and why they can't be reused for anything else.
