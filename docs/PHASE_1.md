# Phase 1 - Gunplay core

**Exit criteria (from `CLAUDE.md` 7):** shooting a wall and a dummy feels good with zero enemies
in the game. That is a judgement call made at the controls, not something a test can assert -
what follows is the systems work that makes the judgement possible.

## Done

- **FPS controller** (`scripts/actors/player.gd`) - move and look only. Yaw on the body, pitch on
  the head pivot, mouse sensitivity and FOV read from `SettingsManager`, ADS sensitivity
  multiplier applied while aimed. Slide/dash/grapple are Phase 2.
- **Projectile system** (`scripts/systems/projectile.gd`) - pooled, stepped, never a
  `RigidBody3D`. Each frame it raycasts the segment it actually travelled, so a 180 m/s round
  cannot tunnel through a wall or a hitbox.
- **Damage** - `HealthComponent`, `HitboxComponent` (head vs body, no limb zones),
  `StatsComponent` (upgrade-aware live values with a cache invalidated on upgrade change).
- **WeaponComponent** - firing, fire-rate cooldown, deterministic recoil, spread, ADS, reload,
  ammo and reserve, auto-reload on empty, low-ammo HUD cue.
- **Deterministic recoil** - `CameraRecoilComponent` splits recoil into the two things it
  actually is: an **aim offset** that moves where bullets go and can be learned and compensated,
  and a **cosmetic kick** on the camera rig that always returns in full and never touches aim.
  The cosmetic half honours the screenshake accessibility toggle; the aim half does not, because
  it is gameplay.
- **Recoil pattern visualizer** (`scripts/systems/recoil_visualizer.gd`) - the Phase 1
  deliverable. `F1` projects the authored pattern onto the range's pattern wall; `F2` fires a
  full magazine and plots the real impacts next to it, so intent and result are comparable.
  Dev builds only - it frees itself in release.
- **Viewmodel** - rendered by its own camera inside a `SubViewport` with its own world, so it can
  never clip into geometry. Kick, sway and ADS position are cosmetic only.
- **HUD** - crosshair whose gap tracks the real spread cone (converted through the camera FOV, so
  it is honest rather than decorative), three distinct hitmarkers (body / headshot / kill), ammo
  with a low-ammo colour cue, and narrator subtitles.
- **Grey-box range** - 50x50 room, pattern wall at 15 m, crates, four target dummies at 6-22 m
  that flash on hit and respawn two seconds after dying.
- **Rifle** - `data/weapons/rifle_ak.tres` with a 30-point pattern: vertical climb, then a right
  hook, then a left sweep, looping from index 20. Horizontal randomness is absent by
  construction, not by tuning.

## Deviations, flagged

1. **Phantom Camera is still not installed** - fetching it was blocked in this environment.
   Camera kick is implemented natively in `CameraRecoilComponent`, which drives a dedicated
   `CameraRig` node between the head pivot and the camera. Phantom Camera can take that node over
   later without touching the aim-offset half, which is the part that matters for gunplay.
2. **Two new script folders**: `scripts/actors/` (player, target dummy) and `scripts/ui/`.
   `CLAUDE.md` 4.1 lists neither, and actor root scripts are not components, systems or AI.
3. **Audio is wired but silent** - every hook is in place (`fire_sound`, `reload_sound`,
   `empty_sound`, impact and hitmarker streams, all routed to the right bus through `AudioPool`),
   but no samples exist yet. Section 6 says not to defer audio: this is the next thing to do, and
   it is half of what makes the exit criteria achievable.

## Gotcha worth knowing

Hand-authored `.tscn` files must declare node exports in the node header:

```
[node name="Player" type="CharacterBody3D" node_paths=PackedStringArray("head", "weapon")]
head = NodePath("HeadPivot")
```

Without `node_paths`, the `NodePath` is stored but never resolved and the export is silently
null at runtime. Paths are relative to the node that declares them.
`tests/unit/test_scene_wiring.gd` guards every such reference.

## Next

1. First-pass weapon audio - layered fire (transient + body + tail), staged reload, empty click.
2. Tune the rifle against the visualizer and the dummies until the exit criteria are met.
3. Only then, Phase 2.
