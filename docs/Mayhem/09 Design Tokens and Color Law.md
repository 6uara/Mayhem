---
tags: [mayhem, design-tokens, color]
---

# Design Tokens and Color Law

`scripts/autoload/theme_tokens.gd`, autoloaded as `Tokens`. **Every color,
timing, size and threshold in the game is meant to trace back to a constant in
this file** — nothing should be hardcoded elsewhere. `tests/unit/test_theme_tokens.gd`
and `tests/unit/test_spec_conformance.gd` pin specific values and cross-checks
(e.g. the Elite archetype's body color must track `Tokens.HAZARD`) so drift
between code and design intent fails a test instead of shipping silently.

## The one law (interactive/world color)

```gdscript
const WORLD_TRAVERSAL := PLAYER   # "you can use this"      — square/bracket
const WORLD_HAZARD    := HAZARD   # "this will hurt you"     — 45° stripes
const WORLD_PICKUP    := REWARD   # "take this"              — circle
const SPAWN := Color("#FF3BC1")   # "enemies come from here" — doors, summon plates
```

**No other color may appear on an interactive surface, and none of these four is
ever reused for a second meaning.** Every telegraphed object in the arena — grapple
anchors, zip lines, moving/disappearing platforms, hazard pools, spawn doors — is
one of exactly these four meanings, enforced structurally by `TelegraphComponent.Meaning`
(see [[01 Architecture#The telegraph contract]]) and checked directly by
`tests/integration/test_arena_elements.gd::test_the_four_meanings_never_share_a_colour`.

## Accent colors and their shapes

Color is never the only signal — each accent has a companion shape
(`Tokens.SHAPE_FOR`), so the game reads correctly for colorblind players:

| Token | Hex | Meaning | Shape |
|---|---|---|---|
| `PLAYER` | `#35E0D4` | yours: health, ammo, dash, grapple | square |
| `ENEMY` | `#FF3B54` | threat, damage in, hitmarkers | diamond/chevron |
| `REWARD` | `#FFB020` | currency, pickups, Host voice | circle |
| `HAZARD` | `#FC3A00` | traps, elite waves, power-ups | triangle |
| `HEAL` | `#8AF0C4` | healing VFX only — **never UI** | — |

`HAZARD` was **acid green (`#C6FF3D`) until this session** — changed to lava
orange when the hazard pool got a real molten-rock shader material (see
[[08 VFX and Shaders#lava_pool.gdshader]]) and it made more sense for the token
to match what the material actually renders than to fight it. This was a
deliberate, discussed change (not a silent recolor): the Elite enemy archetype's
`body_color`, `ENEMY_ELITE`, and `GLOW_HAZARD` all moved with it, because they
were already deliberately coupled to `HAZARD` for the elite-wave HUD stripe.
`ENEMY` (`#FF3B54`, crimson-pink) stays visually distinct from the new
`HAZARD` orange on purpose — "this attacks you" and "this burns you" need to
read as different threats.

**Known drift**: `CROSSHAIR_COLORS` (a preset list for a settings-screen
crosshair color picker) still contains the literal `Color("#C6FF3D")` — the
*old* hazard green — and is not wired to any UI yet, so it's inert rather than
actively wrong. Worth fixing if that picker ever gets built. See
[[12 Known Issues and Gaps]].

## Neutral ramp

`VOID` `#07080B` (deepest shadow, letterbox) → `BASE` `#14161C` (panel fill,
used with `PANEL_ALPHA = 0.82`) → `RAISED` `#1E212B` → `LINE` `#2C3140`
(dividers) → `DIM` `#454C60` (disabled) → `MUTED` `#8A90A3` (secondary text) →
`TEXT` `#E6E8EF` (primary text).

## Layout

8px grid (`GRID = 8`). `SCREEN_MARGIN = 48`, `NO_UI_ZONE = Vector2(900, 500)`
(center reserved for reticle/chevrons/hitmarkers only — see
[[07 UI and HUD#HUD]]), `CHAMFER = 12` (the corner-cut radius every panel uses).

## Type

Four fonts: `Archivo-Variable.woff2` (display), `IBMPlexSans-Regular/SemiBold`
(UI), `IBMPlexMono-SemiBold` (numerals — every stat readout is monospace so
digits don't jitter the layout as they change). Sizes are named by role
(`SIZE_NUM_PRIMARY = 56` for health/ammo magazine, `SIZE_NUM_CLUSTER = 40` for
wave number/currency, `SIZE_NUM_SECOND = 28` for reserve/timer/enemies-left),
not by pixel value at the call site.

## Motion

Every animated duration in the HUD is named here — `HITMARKER_LIFE = 0.12`,
`DAMAGE_CHEVRON_LIFE = 1.20`, `HAZARD_WARNING = 0.60` (the telegraph window
before `HazardZone`, `scripts/systems/hazard_zone.gd`, can actually deal
damage — the decal is drawn at the exact damage radius, and damage additionally
requires standing height-checked against the pool's own floor, so acid on the
ground never reaches a player on a platform above it), `STATE_SETTLE_MAX = 0.40`
(a hard ceiling: nothing may animate longer than this, so no UI feedback ever
feels laggy).

## Enemy identity

`ENEMY_RUSHER` / `_RANGER` / `_ELITE` / `_HEALER` / `_SUMMONER` — dominant color
per archetype (silhouette is the primary read, color confirms). `ENEMY_HEIGHT`
dictionary doubles as the canonical list of archetype names used elsewhere in
tests (`for archetype in Tokens.ENEMY_HEIGHT.keys(): ...`). `EMISSIVE_MAX_AREA = 0.08`
— a cap on how much of an enemy's surface may glow, so emissive doesn't wash out
silhouette readability. `TELL_*` constants are per-archetype telegraph
durations — see [[05 Enemies and AI]].

## Economy / shop

`SHOP_TIMER = 30.0`, `SHOP_TIMER_URGENT = 5.0` (below this the countdown turns
`ENEMY` red). `CATEGORY_COLOR` maps upgrade category → accent (`mobility` →
`PLAYER`, `weapon` → `ENEMY`, `survivability` → `REWARD`) and `INCOME_COLOR`
maps a wave-breakdown row's source to the same accent — this is explicitly
**how the economy is taught**: color-coding income sources by the pillar they
reward.

## Menus / Host / settings ranges

`FOV_RANGE = Vector2(80, 120)`, `SENS_RANGE = Vector2(0.1, 10.0)`,
`SENS_DEFAULT = 2.40` with `SettingsManager.SENS_DEGREES_AT_DEFAULT = 0.25` —
two numbers that must stay in sync (the slider shows 2.40 as its default
*position*, but the game must actually feel like 0.25°/pixel out of the box;
deriving the scale from the ratio of these two, rather than hardcoding degrees
directly, is what keeps them from silently diverging if the slider's default
position ever changes). `HOST_LINE_COOLDOWN = 20.0` / `HOST_PUNCHLINE_PER_WAVE = 1`
gate the Host narrator's pacing — see [[02 Autoloads#NarratorManager]].
`LEADERBOARD_ENTRIES = 20` / `LEADERBOARD_PATH` back `SaveManager`. Eran diez
hasta que las filas pasaron a llevar nombre: con varias personas turnandose en
la misma maquina, diez lugares los llena el mejor de todos.
