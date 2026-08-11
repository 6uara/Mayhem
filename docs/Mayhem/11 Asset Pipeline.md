---
tags: [mayhem, assets, tooling]
---

# Asset Pipeline

`tools/` — offline scripts, run by hand, output committed to the repo:

- `bake_navmesh.gd` — see [[05 Enemies and AI#Navmesh baking]].
- `bake_enemy_meshes.gd` — see below.
- `build_theme.gd` — generates `ui/mayhem_theme.tres` from the design tokens.
- `export_host_script.gd` — see [[07 UI and HUD]] / dumps `data/host/host_catalog.tres`
  to a checklist for external VO recording. See below.
- `generate_placeholder_sfx.py` — synthesizes every placeholder sound
  (stdlib-only Python, fixed RNG seed, deterministic re-runs). See below.
- `generate_placeholder_music.py` — same approach, three looping music beds
  (`assets/audio/music/menu.wav` / `combat.wav` / `shop.wav`) for
  `MusicManager` (see [[02 Autoloads#MusicManager]]).

## Weapon/enemy model import

Models live under `assets/models/`. Godot's `.fbx` importer produces a full node
hierarchy (a root transform carrying the Z-up→Y-up conversion and whatever
scale the source file's units imply) rather than a bare mesh resource — this
matters for two different fields that consume models differently:

- **`WeaponData.viewmodel: PackedScene`** — the imported `.fbx` is referenced
  *directly* as a `PackedScene` and instantiated as a child node. Since the full
  node hierarchy (and its transform) comes along, scale/rotation are correct
  automatically. Positioning is then just `viewmodel_offset` /
  `viewmodel_rotation_degrees` / `viewmodel_scale` on `WeaponData`.
- **`EnemyData.mesh: Mesh`** — typed as a bare `Mesh`, not a scene, so the
  `.fbx`'s root transform has to be baked in manually via `tools/bake_enemy_meshes.gd`:

  ```
  godot --headless --path . -s tools/bake_enemy_meshes.gd -- \
      res://assets/models/enemies/<Name>/<file>.fbx \
      res://assets/models/meshes/<name>.res \
      --height=1.8
  ```

  The tool instantiates the source scene, finds the `MeshInstance3D`, composes its
  local transform down from the scene root, then `SurfaceTool.append_from(mesh,
  surface, transform)` into a new `ArrayMesh` per surface (materials carried over).
  The result is recentred on its own AABB and rescaled so its tallest axis matches
  `--height` (typically the target archetype's `EnemyData.collision_height`),
  matching how the box/capsule placeholders were already authored (pivot at the
  shape's own center, not at the source rig's origin — which for at least one
  imported model was nowhere near the body). Save the output under
  `assets/models/meshes/` and point `data/enemies/*.tres`'s `mesh` field at it.

  Verified against the existing `spiderbot.res`: re-running the tool on
  `LowPoly_SpiderBot_Rzenn.fbx` with `--height=1.2` (the Rusher's
  `collision_height`) reproduces the same vertex/attribute data.

## Placeholder audio

`tools/generate_placeholder_sfx.py` — every sound in the game is a synthesized
stand-in, not a final sample, but every audio *hook* is wired, audible and
testable before real assets exist (the same role grey-box geometry plays for
level art). Layered construction per the handoff: transient + body + thump +
tail rather than one flat sample.

**Per-weapon voices** (`weapon_fire()` helper, parameterized per weapon):
pistol is short and bright (little body, almost no tail — "a crack, not a
boom"), shotgun is slow and enormous (all chest and room), SMG is short and
tinny (15 rounds/sec leaves no room for a tail — a long body would keep six
shots overlapping and turn the whole thing to mud), rifle is the baseline. Each
weapon's reload is three-to-four mechanical "clack" stages
(`_clack()` helper) sized to fit inside that weapon's own `reload_time` — the
shotgun's is deliberately the odd one out, loading shell-by-shell so a player
who learns the rhythm can count what's already chambered without looking at the
HUD.

**Footsteps**: four pitched variants (`footstep()`), because a walk cycle plays
this several times a second — a single sample repeating on a fixed interval is
the most audible "robotic" tell in the whole locomotion loop (see
[[03 Player and Movement#CameraFeelComponent]] for where these get triggered:
`stepped()` signal, distance-driven phase, never the same variant twice in a
row).

Output paths: `assets/audio/sfx/weapons/`, `assets/audio/sfx/world/`,
`assets/audio/sfx/enemies/` (per-archetype, pitched), `assets/audio/sfx/impacts/`,
`assets/audio/sfx/ui/`.

## Noise textures

`assets/textures/Noise128x128/` — eighteen categories (Cracks, Craters, Gabor,
Grainy, Manifold, Marble, Melt, Milky, Perlin, Spokes, Streak, Super Noise,
Super Perlin, Swirl, Techno, Turbulence, Vein, Voronoi), 14 variants each
(Perlin has 24). Currently consumed by the two custom world-material shaders —
`Cracks` for lava, `Swirl` for the spawn-door portal — see
[[08 VFX and Shaders]]. The rest are available and unused.

## Shader import notes

Two things that aren't obvious from the Godot docs and cost real debugging time
building these shaders:

- **`.gdshader` files use `//` comments only.** `##` (the GDScript doc-comment
  convention) is a tokenizer error in shader code — `Unknown character #35: '#'`.
- **Sampler wrapping needs an explicit hint.** A `sampler2D` uniform needs
  `repeat_enable` (plus `filter_linear_mipmap` for smooth scrolling) in its hint
  list for `TIME`-driven UV scrolling to tile correctly — texture import
  settings alone don't control this at the shader-sampler level.
