---
tags: [mayhem, ui, hud]
---

# UI and HUD

## HUD

`scripts/ui/hud.gd` + `scenes/ui/hud.tscn`. Layout law: **the center 900×500 is a
no-UI zone** (`Tokens.NO_UI_ZONE`) — only the reticle, damage chevrons and
hitmarkers may enter it. Every other cluster anchors to its own screen corner, so
an ultrawide display pushes clusters apart rather than stretching them. Enforced
by `tests/integration/test_hud_layout.gd`, which measures actual rendered
`Rect2`s against the live viewport (not an assumed 1920×1080) and asserts no two
clusters intersect.

**The HUD never polls.** Every value on screen arrives via an `EventBus` signal
connection made in `_ready()` — there is no `_process()` reading gameplay state.
Clusters: Wave, Timer (par-time bar + no-damage indicator), Currency
(+ `PowerUpChip` list), Vitals (health segments, dash pips), Ability bar, Weapon
(ammo readout), plus the always-present `Reticle`, `BroadcastBug`, `AnnounceLayer`,
`SubtitleBox`.

### Reticle

`scripts/ui/reticle.gd` — **one system** for hipfire crosshair, grapple-anchor
confirmation, hitmarkers, kill confirmation, and all four ADS sight styles.
Consolidating these was deliberate: they share outline, color and hit-state
logic, and used to be separate widgets.

### TelegraphComponent

Covered in depth in [[01 Architecture#The telegraph contract]] and
[[09 Design Tokens and Color Law]] — the shared mesh/material/state system every
world affordance (not just HUD) runs on.

### Small single-purpose widgets

- `SegmentStrip` — health segments, dash pips, ammo pips: one widget, three
  configurations (count + size), not three separate scripts.
- `StripeBar` — the 45° hazard stripe, drawn procedurally rather than a tiled
  texture; reused for the elite-wave banner stripe and hazard floor cues.
- `MayhemIcon` — all 25 HUD icons drawn procedurally via `_draw()` (rectangles,
  circles, triangles, one diamond — matching the handoff's icon language) with a
  `texture` override field as an escape hatch for a future PNG pass.
- `PowerUpChip` — one active temporary upgrade + its countdown.
- `DamageIndicators` — directional chevrons at a fixed radius, rotated toward
  whatever hit the player.
- `BroadcastBug` / `HostMark` — the "Host" broadcast-layer presentation: amber
  top edge, LIVE tag, a crossed-ring mark reused across favicon/broadcast
  bug/floor decals/loading screens.

## Theme system

`ui/mayhem_theme.tres` — a Godot `Theme` resource with named type variations
(`HUDLabel`, `HUDPanel`, `NumCluster`, `NumPrimary`, `NumSecond`, `Subtitle`,
`SubtitlePanel`, `DisplaySmall`, `Keybind`, `Announce`, plus a themed default
`Button`/`Label`/`PanelContainer`). Any `Control` that sets `theme = ...` to this
resource picks these up automatically via `theme_type_variation`.

**`ChamferStyleBox`** (`scripts/ui/chamfer_style_box.gd`, `class_name ChamferStyleBox
extends StyleBox`) is the panel look: flat fill, thin border, one 45° cut on the
bottom-right corner (Godot's built-in `StyleBoxFlat` only does rounded corners,
and the style guide bans radius outright — "cut corners, never rounded" — so
this draws by hand via `_draw()` and `RenderingServer` calls). Also supports an
accent rail (one edge, configurable color/width/side — this is how "current" is
expressed everywhere: the equipped weapon, a selected row, an affordable shop
card) and corner tick marks (a frame is deliberately incomplete — brackets, not
a closed box).

## Pause menu

`scripts/ui/pause_menu.gd` + `scenes/ui/pause_menu.tscn`. Listens to
`EventBus.game_paused` (see [[02 Autoloads#EventBus]]) to show/hide. Buttons:
Resume (`GameManager.set_paused(false)`), Options (opens the child
`SettingsScreen`, hides itself), Quit to menu. `process_mode = PROCESS_MODE_ALWAYS`
— has to keep running while `get_tree().paused` is true, which is the entire
point of a pause menu.

This exists because pausing already worked (`GameManager` froze the tree and
released the cursor) but nothing was ever drawn over it — pressing pause mid-run
read as a hang, not a pause.

## Options screen

`scripts/ui/settings_screen.gd` + `scenes/ui/settings_screen.tscn`. **Rows are
generated from a schema (`SettingsScreen.SCHEMA`), not hand-authored per-control.**
Each entry is `{key, label, type, ...}` where `key` must exist in
`SettingsManager.DEFAULTS` — a hand-built panel of ~20 controls drifts from the
backend the instant a new setting is added (the value exists, nothing shows it,
nobody notices); a schema row pointing at a missing key fails a test instead
(`tests/integration/test_pause_and_settings.gd::test_every_schema_key_is_a_real_setting`).

Control types: `toggle` (`CheckButton`), `option` (`OptionButton`), `color`
(`ColorPickerButton`), `percent` / plain `slider` (`HSlider` + live readout
label). Changes apply immediately via `SettingsManager.set_value()` +
`apply_all()` — a sensitivity or volume can't be judged from its number, and the
tree is already paused, so re-applying on every edit costs nothing. Persisted
(`save_settings()`) only when the screen closes.

Listens on `_input()`, not `_unhandled_input()`, specifically so it beats
`GameManager`'s own pause-key handler — otherwise closing the options screen
with the pause key would also unpause the match underneath it.

The footer's "Reset tutorial hints" button (`_on_reset_hints_pressed()`) sits
outside the schema — it isn't a setting, it calls
`SaveManager.clear_tutorial_hints()` directly (see
[[02 Autoloads#TutorialHintManager]]). Exists for playtest sessions: reset the
build between testers so everyone sees the first-time hints fresh.

## Match overlay

`scripts/ui/match_overlay.gd` + `scenes/ui/match_overlay.tscn`. Wave banners,
victory/game-over screens. Restart reloads the scene outright rather than
unwinding state — the "under 2 seconds back to shooting" constraint is easier to
hit that way than by resetting every system by hand.

## Main menu

`scripts/ui/main_menu.gd` — **explicitly marked as a placeholder** in its own
top-of-file comment (`"Placeholder menu so GameManager's scene transitions have
somewhere to land."`). It has not been rebuilt to match the rest of the visual
identity pass. See [[12 Known Issues and Gaps]].

## Leaderboard

`SaveManager` (autoload) persists scores, but **no screen currently displays
them**. See [[12 Known Issues and Gaps]].

## Scene transitions

`SceneTransition` (`scripts/ui/scene_transition.gd` + `scenes/ui/scene_transition.tscn`)
— a `CanvasLayer` at `layer = 10` (above every other layer in the game; the
pause menu, the next highest, sits at 4) driving `assets/shaders/scene_change.gdshader`
(a Persona-5-style rotated square wipe, `canvas_item`, `t` uniform 0→1) over a
full-screen `ColorRect`, tinted `Tokens.VOID`. `GameManager` owns the only
instance as its own child (see [[02 Autoloads#GameManager]]) and is the only
thing that ever calls `fade_out()` / `fade_in()` — no other code should touch
this directly, or a scene change could start racing its own transition.

`_play()` polls `tween.is_running()` every frame instead of `await
tween.finished` directly, against a `safety_timeout` ceiling (`@export`, not a
const, so a test can shrink it) — if the tween is ever interrupted, the game
must force the target value and move on rather than hang on a black screen
waiting for a signal that will never come. `test_a_stalled_fade_is_forced_to_finish_rather_than_hanging_forever`
proves this without actually waiting out the real 3-second default.
