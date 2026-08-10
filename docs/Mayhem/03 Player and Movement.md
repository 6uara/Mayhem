---
tags: [mayhem, player, movement]
---

# Player and Movement

## Node chain (why it's shaped this way)

```
Player (CharacterBody3D)          — look input, weapon input, aim transform
└─ HeadPivot                       — pitch + where bullets originate (Player owns this)
   └─ ViewBob                      — step bob / strafe lean / landing punch (CameraFeelComponent)
      └─ CameraRig                 — weapon recoil visual kick (CameraRecoilComponent)
         └─ Camera3D                — FOV only
```

Each layer is owned by exactly one script, and each is **cosmetic-only** except
`HeadPivot` itself. `get_aim_transform()` on `Player` reads `head.global_transform`
— nothing below `HeadPivot` in the chain can affect where a shot goes, by
construction. `tests/integration/test_player_movement.gd::test_view_bob_can_never_move_the_aim`
enforces this directly: it drives `ViewBob`'s transform to extreme values and
asserts the aim transform doesn't move.

## MovementComponent

`scripts/components/movement_component.gd`. Owns **all** player physics. State
machine: `State` enum `GROUNDED / AIRBORNE / SLIDING / DASHING / GRAPPLING`.

Design law from the source's own comments: **momentum is a resource the player
builds and keeps** — nothing here caps speed "for fairness" (enemies are
aggro-locked, so player speed is safe), slide conserves and chains speed, bhop
chaining is intentional.

### Ground / Air

- `_tick_grounded()` — accelerate toward `wish_direction * get_move_speed()`
  (`acceleration`), or decelerate to zero (`friction`) with no input.
- `_tick_airborne()` — **steering only, no drag**. Air control (`air_control`)
  can redirect velocity but never accelerate past current speed. Mantling
  (`_try_mantle()`) triggers automatically while airborne, moving toward a wall,
  holding jump: a chest-height ray finds the wall, a head-height ray confirms
  clearance, and finding both boosts `velocity.y` — geometry snags that would
  otherwise kill momentum are a bug by design decree. Emits `mantled()` only on
  a successful boost, not on every probe.

`started_moving()` / `jumped()` / `mantled()` exist solely as
`TutorialHintManager`'s hook for each mechanic's first-time hint (see
[[02 Autoloads#TutorialHintManager]]) — `started_moving()` fires once ever, the
first frame `wish_direction` goes nonzero; `jumped()` fires from `_jump()`,
covering the ground/air/slide-jump paths alike since they all funnel through it.

### Gravity is asymmetric

```gdscript
func _apply_gravity(delta: float) -> void:
    if body.is_on_floor():
        return
    var scale: float = 1.0 if body.velocity.y > 0.0 else fall_gravity_scale
    body.velocity.y -= gravity * scale * delta
```

`fall_gravity_scale = 1.7` by default. The rise keeps its full hang time; only
the fall accelerates. This exists because a symmetric arc is the single loudest
source of a "floaty" feel — weight is sold on the way down, not the way up.

### Jump: three ways in, deliberately

`_consume_jump()` is the single gate all three paths call through:

1. **Held button** — auto-bhop, so slide-chaining never needs frame-perfect taps.
2. **Jump buffer** (`jump_buffer_time = 0.12s`) — a press just *before* landing
   still fires on touchdown.
3. **Coyote time** (`coyote_time = 0.10s`) — a press just *after* walking off a
   ledge still counts.

Coyote refreshes in `_post_move()`, gated on `body.velocity.y <= 0.0` — refreshing
unconditionally on `is_on_floor()` would hand out a second jump on the same frame
the first one fires, since the body is often still touching the floor that frame.

**Jump cut**: releasing the button mid-rise multiplies `velocity.y` by
`jump_cut_multiplier = 0.45`, so a tap and a hold produce different heights.

### Slide

`_tick_sliding()`: downhill acceleration is gravity projected onto the floor
plane (`slope_accel_scale`), gentle steering (weaker than running — a slide is a
commitment), friction decay. `slide_boost` applies once per slide entry from a
run (`_slide_boost_spent` guards re-triggering it via crouch-spam). Landing with
crouch held re-enters a slide at full speed with **no** boost — that's the chain
that makes downhill routes and pad-to-slide flow work.

### Dash

Flat, gravity-free burst (`dash_speed`, `dash_duration`) that goes wherever you
point, including mid-air. `dash_charges` (a `DashCharges` value object — see
`tests/unit/test_dash_charges.gd`) tracks up to `dash_charges_max = 3`
(`Tokens.DASH_CHARGES` — the HUD reserves exactly three pips for it) with
independent per-charge cooldowns. On dash end, `dash_exit_speed_fraction = 0.75`
of dash speed carries into the next state — the momentum handoff that makes
dash→slide chains worth learning.

### Grapple

`GrappleComponent` (separate component, `scripts/components/grapple_component.gd`)
— `try_fire()` / `release()` / `get_pull_velocity()`. `MovementComponent._tick_grappling()`
just calls into it and exits on release or on jump/re-fire. **No test coverage** —
see [[12 Known Issues and Gaps]].

## CameraFeelComponent

`scripts/components/camera_feel_component.gd`. Purely cosmetic — drives the
`ViewBob` node only. Added because the movement math was never what read as
"robotic" — a rigid camera on a moving body was.

- **Step bob**: phase advances by *distance travelled*, not time
  (`_bob_phase += TAU * (speed * delta) / stride_length`) — always in sync with
  ground actually covered, stops dead when the player stops. Emits `stepped()` on
  each half-cycle crossing (one per footfall), which drives footstep audio with
  variant/pitch selection that never repeats the same sample twice in a row.
- **Strafe lean**: small roll (`strafe_tilt_degrees = 1.8°`, more during slides).
  Roll around the view axis leaves the view axis itself unchanged, so this is
  provably aim-safe.
- **Landing punch**: a damped spring (`land_stiffness` / `land_damping`), not a
  linear return — the overshoot is what reads as the body absorbing an impact.
  Scales with fall speed, capped, and respects the screenshake accessibility
  toggle (it *is* a camera shake).
- Respects `accessibility/view_bob_enabled` for the bob itself specifically
  (motion sickness is the most common trigger in first-person, and it carries no
  gameplay information).

## CameraRecoilComponent

`scripts/components/camera_recoil_component.gd`. Splits recoil into two things
that are not the same thing:

- **`aim_offset`** — rotates where the player is actually looking. This changes
  where bullets go, and the player is meant to compensate for it with the mouse.
- **Visual kick** — cosmetic punch on `CameraRig` only, always fully recovers,
  disabled by the screenshake accessibility setting, never affects aim.

`apply_shot(pattern_offset, recovery_speed, visual_multiplier)` is called by
`WeaponComponent` per shot, sourcing the deterministic offset from that weapon's
`RecoilPattern` — recoil is a *pattern*, not randomness, so it's learnable. See
[[04 Weapons and Combat#Recoil]].

## Speed-scaled FOV

`Player._tick_speed_fov()` — widens FOV above `movement.base_move_speed`, capped
at `SPEED_FOV_MAX = 12.0`, suppressed while aiming (`* (1.0 - weapon.ads_progress)`).
Exists because the movement system hands out real momentum through slides, dashes
and pads, but without a visible consequence the screen looks identical at 7 m/s
and 14 — the reward for chaining well was otherwise invisible.

`SpeedLinesOverlay` (`scripts/ui/speed_lines_overlay.gd`, a `ColorRect` inside
`HUD/Root/StateOverlays`, `assets/shaders/speed_lines.gdshader`) is the screen
half of the same reward — see [[08 VFX and Shaders#Speed lines]]. `HUD._tick_movement()`
feeds it the player's actual horizontal speed (`Vector3(velocity.x, 0,
velocity.z).length()`, the same quantity `_tick_speed_fov()` reads), not
`MovementComponent.get_move_speed()`'s target.

## Weapon viewmodel kick

Lives on `WeaponComponent`, not `CameraFeelComponent` — see
[[04 Weapons and Combat#Viewmodel]].
