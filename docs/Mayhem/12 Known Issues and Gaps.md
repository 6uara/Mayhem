---
tags: [mayhem, todo, gaps]
---

# Known Issues and Gaps

State as of this writing. Update this note as items get resolved — it's meant
to stay current, not be a historical log (that's what `docs/PHASE_*.md` and git
history are for).

## Performance

Backlog tanda G2: does the game "hold 60 FPS on a full elite wave"?
`tools/profile_elite_wave.gd` forces wave 10 (27 enemies — the largest
authored wave), makes the player invincible (so it can't die and reset the
wave mid-measurement — a real risk, since nothing in the scenario fights
back), removes the video/fps_cap and vsync default (both would otherwise
silently ceiling the reading at 60), and samples `Engine.get_frames_per_second()`
for 20 real seconds once all 27 are alive.

```
godot --path . -s tools/profile_elite_wave.gd -- 20
```

**Must run with real rendering, not `--headless`** — headless skips the
renderer, so it would only ever measure script/physics cost and miss glow,
particles, decals and the panel shaders entirely.

**Last verified result** (2026-08-10, AMD Radeon RX 7700 XT, Windows, D3D12
Forward+, this repo's own dev machine): two runs, `min 519–547 / avg 590–599 /
max 619–636 FPS`, **0.0% of frames under 60** both times. Comfortably clears
the target on this hardware — by roughly 9-10x at the floor, not a marginal
pass.

**What this does NOT tell you**, and needs a person to actually check:
- **Lower-end / integrated GPUs.** One machine, one (strong, discrete) GPU.
  A number this far above target is a good sign, not a guarantee for a
  laptop iGPU.
- **Full combat load.** The player stands still — no player weapon fire, no
  muzzle flash/projectile/impact VFX from the player's side, no camera
  movement. It measures the enemy-density floor, not "worst frame during a
  real firefight."
- Rerun this after tanda D1 (arena dressing) and F1 (real enemy models) land
  — both add real cost this number doesn't include yet.

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
- **Real audio mix** (tanda E3) — `tools/configure_audio_mix.gd` set a
  first-pass gain hierarchy (VO/Weapons highest priority down to UI lowest,
  see the tool's own docstring for the exact table) plus a Master limiter so
  a worst-case elite wave can't clip. That's mechanical - applying an
  already-decided priority order as relative dB offsets, and a safety net.
  What it explicitly is NOT: a real mix. Perceptual loudness balance, EQ,
  reverb sends, and the "does this actually sound right, on headphones AND
  speakers" listening pass all need a person with ears at a review, same
  reasoning as the arena/lighting items above.

## No test coverage

- ~~**`StatsComponent`**, **`GameManager`**, **`AudioPool`**~~ — all three are
  covered now (`tests/unit/test_stats_component.gd` 13 tests,
  `test_game_manager.gd` 12, `test_audio_pool.gd` 14).

  Worth keeping the original warning on record, because it came true almost
  word for word: *"if this breaks, the shop silently stops mattering — no test
  would catch it."* When hitscan moved damage resolution to the trigger, the new
  path read `data.damage` instead of `get_damage()`, and every purchased damage
  upgrade stopped applying to all four player weapons. The full suite passed.
  Unit-testing `StatsComponent` was not enough on its own — what was missing was
  a test crossing *"bought an upgrade"* with *"fired a shot"*, which is now
  `test_a_damage_upgrade_reaches_a_hitscan_shot`. Coverage of a component does
  not cover the seam between components.
- ~~`GrappleComponent`, `BouncePad`~~ — this note was stale; both have covered
  (`tests/unit/test_grapple_component.gd`, `test_bounce_pad.gd`).

## Missing UI

~~No leaderboard screen; main menu an unstyled placeholder.~~ Both stale —
this note wasn't updated when they were built. `LeaderboardPanel`
(`scripts/ui/leaderboard_panel.gd` + `scenes/ui/leaderboard_panel.tscn`) is
themed, reads `SaveManager.get_entries()`, opens from the main menu's
`LeaderboardButton`, and shows the player's best score on the front page
(`BestRow/Value`) — all covered by
`tests/integration/test_main_menu_and_leaderboard.gd`, which was already
passing before this doc got corrected (backlog tanda G6).

## Minor drift

- ~~`Tokens.CROSSHAIR_COLORS`~~ — fixed (backlog tanda G6): the stale preset
  swapped for `HAZARD` itself, so it can't drift again the same way.
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

- ~~`assets/materials/Lava.tres`~~ — removed (backlog tanda G6). Confirmed
  unreferenced anywhere (`hazard_zone.tscn` uses the `lava_pool.gdshader`
  `ShaderMaterial` directly) before deleting.
- `assets/shaders/vhs.gdshader` — this note used to describe it as a stray,
  empty stub (`shader_type spatial;`, nothing else), presumed editor debris.
  That's stale: as of this writing it's a real, substantial `canvas_item`
  VHS post-processing shader (signal distortion, glass-crack, tape-artifact
  uniform groups) — active work in progress on another branch, not debris.
  Left untouched; re-check before assuming either description next time.
- Godot's editor performs **auto-resaves of open scenes** when the project is
  loaded (e.g. via `--import`), which can silently revert recent hand-edits to
  a `.tscn` if that scene is open in a stale editor window — this has
  destroyed real content once (a floor-material fix and four `TargetDummy`
  nodes disappeared from `greybox_arena.tscn` in one such resave). Always
  `git diff` a scene file before committing if any Godot editor process ran
  during the session, even one only invoked headlessly for `--import` or
  `--quit-after`.

## Planeado, sin empezar (ramas nice-to-have)

Trabajo deliberadamente fuera del alcance de la entrega, con rama y plan ya
armados para que arrancar no cueste una sesión de arqueología:

- **`feat/coop-p2p`** — cooperativo P2P.
- **`feat/new-enemy-types`** — Bomber, Ranged Flyer, Environmental y
  Gladiadores (una tercera facción que pelea contra el jugador *y* contra la
  horda). El plan está en
  [PLAN_NEW_ENEMY_TYPES.md](../PLAN_NEW_ENEMY_TYPES.md).

  De ese plan vale la pena traer acá los cuatro bloqueos que encontró, porque son
  limitaciones del código actual y no del trabajo futuro:

  1. **El objetivo está cableado al jugador.** `Enemy` no tiene noción de "mi
     objetivo", tiene `get_player()` (grupo `&"player"`), y de ahí cuelgan el
     melee, el salto, el disparo y todos los leaves de Beehave. Cualquier
     enemigo que pelee contra otro enemigo necesita esa abstracción primero.
  2. **Un proyectil enemigo no puede tocar a un enemigo.** `EnemyProjectile`
     enmascara `WORLD | PLAYER` *y además* verifica `is_in_group(&"player")`
     antes de aplicar daño — son dos filtros, no uno. No existe daño entre NPCs.
  3. **No hay vuelo.** `Enemy._steer()` hace `direction.y = 0.0`; la altura sale
     sólo de la gravedad y de saltos balísticos que siempre aterrizan. Un
     enemigo volador necesita un modo de movimiento nuevo, no un número distinto.
  4. **No existe atribución de muertes.** `Enemy` emite
     `EventBus.enemy_killed(id, position, reward)` al morir (`enemy.gd:1138`) y
     `EconomyManager._on_enemy_killed()` suma la moneda sin preguntar quién
     mató (`economy_manager.gd:97`). No hay concepto de "asesino" en ningún
     lado. Cualquier regla del tipo "sólo cobrás lo que rematás vos" es un
     sistema nuevo, no un ajuste de balance — y es útil por sí sola, aunque los
     Gladiadores nunca se construyan.
