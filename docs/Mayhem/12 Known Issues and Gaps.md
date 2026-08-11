---
tags: [mayhem, todo, gaps]
---

# Known Issues and Gaps

State as of this writing. Update this note as items get resolved — it's meant
to stay current, not be a historical log (that's what `docs/PHASE_*.md` and git
history are for).

## Needs a human at the editor, not more unattended passes

- **Arena dressing/geometry pass** (backlog tanda D1) — un-started on purpose.
  Turning greybox into a dressed level is a visual-judgment task (does this
  read as a space, does the new geometry kill sightlines/flow) that has no
  meaningful unattended version; the safe thing to automate would just be
  guessing. See [[08 VFX and Shaders#Arena glow]] for what *did* ship
  unattended this pass (glow) and why that one was safe to guess at (it
  completes an already-decided, documented convention rather than choosing
  new geometry or color).
- **Lighting pass beyond glow** (tanda D2) — same reasoning. Glow shipped
  because it's mechanical completion of shader uniforms that already existed
  for this purpose; key/fill lighting, shadow baking decisions, and a
  per-zone "can I actually see the enemy here" check all need a person
  looking at the rendered arena.
## No test coverage

- **`StatsComponent`** — zero test files, despite being the read path *every*
  purchased upgrade in the game flows through (`get_stat_from()`, chained into
  from `WeaponComponent`, `MovementComponent`, `Player`). If this breaks, the
  shop silently stops mattering — no test would catch it.
- **`GameManager`**, **`AudioPool`** — also uncovered, lower risk (simpler,
  less state).
- ~~`GrappleComponent`, `BouncePad`~~ — this note was stale; both have covered
  (`tests/unit/test_grapple_component.gd`, `test_bounce_pad.gd`).

## Missing UI

- **No leaderboard screen.** `SaveManager` persists scores to
  `user://leaderboard.json` and `MatchDirector` writes to it, but nothing reads
  it back for display. The "run for time" loop the economy/scoring is built
  around has no visible payoff screen.
- **Main menu is an explicit placeholder.** `scripts/ui/main_menu.gd`'s own
  top-of-file comment: *"Placeholder menu so GameManager's scene transitions
  have somewhere to land. The real menu is built in Phase 5."* It was not
  rebuilt during the visual-identity pass — still plain `Control`/`Button`
  nodes, no theme, no `ChamferStyleBox`. Everything else in [[07 UI and HUD]]
  uses the shared theme system; this doesn't yet.

## Known flaky test

`test_navigation_connectivity.gd::test_the_map_has_a_navmesh_at_all` — see
[[10 Testing#Known flaky test]]. Present on unmodified `develop`, not caused by
any specific recent change, not yet root-caused.

## Minor drift

- **`Tokens.CROSSHAIR_COLORS`** still contains the *old* hazard green
  (`#C6FF3D`) as a preset option, unchanged when `Tokens.HAZARD` moved to lava
  orange (`#FC3A00`). Currently harmless — nothing consumes this constant yet,
  the settings screen's crosshair color control is a free `ColorPickerButton`,
  not limited to this preset list — but it should move if that preset picker
  ever gets built.
- **Shader `tint`/`glow_color` uniforms are set once, at `.tscn` authoring
  time**, matching `Tokens.HAZARD` / `Tokens.SPAWN` by hand rather than being
  derived from the token live at runtime (see
  [[08 VFX and Shaders#Color law tie-in]]). If either token changes again, the
  lava and portal shaders need a manual update to follow — there's no test
  currently catching that specific drift, unlike the Elite/hazard coupling
  which *is* tested.
- **`data/surfaces/metal.tres` reuses `impact_world.wav`** — no metal-specific
  impact sample has been recorded yet, so metal currently sounds identical to
  concrete despite looking different (see
  [[08 VFX and Shaders#Impact VFX keyed to surface material]]). The variation
  system is real; only that one sample is a placeholder. Same story for every
  `SurfaceMaterialData.decal_texture` — all null, grey-box tint only, until
  real decal art exists. Only two world `StaticBody3D`s (the scifi containers
  in `greybox_arena.tscn`) are tagged `&"metal"` so far; the rest of the arena
  resolves to the `concrete` default until more geometry gets tagged.

## Housekeeping

- `assets/materials/Lava.tres` — an earlier, superseded lava material attempt
  (flat `StandardMaterial3D` + normal map). No longer referenced anywhere
  (`hazard_zone.tscn` now uses the `lava_pool.gdshader` `ShaderMaterial`
  directly). Left in place rather than deleted since it wasn't clearly
  abandoned vs. kept for reference — safe to remove if confirmed unwanted.
- Stray `assets/shaders/vhs.gdshader` / `vhs.gdshader.uid` / `vhs.tres` appeared
  in the working tree during a documentation-writing session, containing only
  an empty shader stub (`shader_type spatial;`, nothing else). Timing strongly
  suggests they're debris from a concurrently-running local editor session
  rather than intentional content — never committed, flagged rather than
  deleted.
- Godot's editor performs **auto-resaves of open scenes** when the project is
  loaded (e.g. via `--import`), which can silently revert recent hand-edits to
  a `.tscn` if that scene is open in a stale editor window — this has
  destroyed real content once (a floor-material fix and four `TargetDummy`
  nodes disappeared from `greybox_arena.tscn` in one such resave). Always
  `git diff` a scene file before committing if any Godot editor process ran
  during the session, even one only invoked headlessly for `--import` or
  `--quit-after`.
