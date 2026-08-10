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

`glow_color` on the lava shader and `tint` on the portal shader are set to match
`Tokens.HAZARD` and `Tokens.SPAWN` respectively at the `.tscn` authoring level
(not derived live from the token at runtime — a known minor gap, see
[[12 Known Issues and Gaps]]). See [[09 Design Tokens and Color Law]] for what
those tokens mean and why they can't be reused for anything else.
