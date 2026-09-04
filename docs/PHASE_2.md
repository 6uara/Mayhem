# Phase 2 - Mobility

**Exit criteria (from `CLAUDE.md` 7):** a movement "playground" run through the arena is fun
with no combat at all. Like Phase 1, that judgement is made at the controls; this documents the
systems that make it judgeable.

## Done

- **MovementComponent** (`scripts/components/movement_component.gd`) - the state machine:
  GROUNDED, AIRBORNE, SLIDING, DASHING, GRAPPLING. It owns all player physics including jump;
  `player.gd` is reduced to look and weapon input, per the parent-child split in section 4.4.
- **Slide** - momentum-preserving and exploitable, as specced:
  - One-time boost entering a slide from a run. **Not** paid again on bhop re-entry, so
	crouch-spam is not a free accelerator - only real momentum sources are.
  - Downhill: gravity projected on the floor plane feeds the slide (`slope_accel_scale`).
  - Slide-jump carries full horizontal speed into the air, and **air applies no drag, only
	steering** - that pair is what makes bhop chaining work and is intended behavior.
  - Landing with crouch held re-enters the slide at speed. Steering mid-slide is deliberately
	weak: a slide is a commitment.
- **Dash** - Deadlock model, 2 charges, each regenerating independently on its own cooldown
  (`scripts/util/dash_charges.gd`, pure logic, unit tested). Burst follows input direction,
  works in air, and hands off `dash_exit_speed_fraction` of its speed on exit so dash -> slide
  chains compound. Charge count and cooldown read through `StatsComponent` - they are the
  upgrade targets named in 5.5.
- **Grapple** (`scripts/components/grapple_component.gd`) - raycast against the
  `grapple_anchor` layer with world geometry blocking (no grappling through walls), hard max
  range, cooldown, pull along a controlled arc via `move_toward` on velocity, exit keeps
  whatever momentum the arc built. Releases on arrival, on re-press, on jump, or when the
  anchor falls behind. **Reticle telegraph**: the crosshair turns cyan and grows brackets when
  a usable anchor is in range (`Crosshair.set_anchor_available`).
- **Mantle** - while airborne holding jump toward a ledge: a chest-height ray that hits with a
  clear head-height ray means a mantleable ledge, and the player gets an upward boost instead
  of a geometry snag.
- **Bounce pads** (`scripts/systems/bounce_pad.gd`) - set vertical velocity, never touch
  horizontal, never reduce an incoming upward velocity. That is what makes them combo with
  dash and slide.
- **HUD** - dash pips (filled / regen arc / hollow) and the grapple reticle state.
- **Arena v1** (`scenes/arena/greybox_arena.tscn`) - 70x70, three height levels (ground, 3 m
  platforms, 6 m walkway and perch), two ramps, a slide hill, two mantle boxes, three bounce
  pads (one tuned to reach the high level), four emissive grapple anchors, four dummies placed
  across levels for firing-while-moving, and the pattern wall kept for the recoil visualizer.
  The Phase 1 range (`greybox_range.tscn`) still exists for isolated gunplay tuning.
- **Audio** - placeholder jump/land/dash/slide/grapple/bounce one-shots from the same
  generator, routed through `AudioPool` to the World bus.

## Firing while moving

Already correct from Phase 1 with zero new code: `WeaponComponent.get_current_spread()` reads
`body.is_on_floor()` and velocity, so slide/dash/air states inherit the moving and airborne
spread penalties, and nothing anywhere blocks firing during any movement state.

## Deviations, flagged

1. **Movement VFX are minimal** - the phase list names dash trails and slide sparks; what
   exists is the bounce pad pulse and audio. Trails are cosmetic polish that lands naturally
   with the Phase 5 VFX pass; flagging rather than half-building them now.
2. **Slide does not shrink the collision capsule** - only the head drops. Sliding under
   obstacles is not yet a mechanic; if playtesting wants it, it needs capsule swapping plus
   un-crouch clearance checks.
3. **Player scene root no longer holds movement tunables** - they moved to
   `MovementComponent`, where the state machine that uses them lives.

## Next

1. Playtest the playground run: pad -> dash -> slide hill -> bhop -> grapple chains.
2. Tune `slide_boost`, `dash_exit_speed_fraction`, `air_control` and pad heights from feel.
3. Then Phase 3: enemies and waves.
