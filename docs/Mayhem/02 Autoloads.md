---
tags: [mayhem, architecture, autoloads]
estado: referencia
actualizado: 2026-10-21
---

# Autoloads

Registered in `project.godot` under `[autoload]`, in this exact order (load order
matters — `Tokens` loads before `EventBus`, everything loads before Beehave's
globals):

| Name | File | Owns |
|---|---|---|
| `Tokens` | `theme_tokens.gd` | Design constants — see [[09 Design Tokens and Color Law]] |
| `EventBus` | `event_bus.gd` | Cross-system signals |
| `GameManager` | `game_manager.gd` | Match state machine, pause, run mode and fixed seed |
| `RunSeed` | `run_seed.gd` | The run's seed and one RNG stream per system; share codes — see [[#RunSeed]] |
| `ObjectPool` | `object_pool.gd` | Pooled instantiation |
| `AudioPool` | `audio_pool.gd` | 3D/2D voice pool, buses, ducking |
| `MusicManager` | `music_manager.gd` | Crossfaded music bed, follows match state |
| `SettingsManager` | `settings_manager.gd` | User settings: load/save/apply |
| `SaveManager` | `save_manager.gd` | Local leaderboard |
| `EconomyManager` | `economy_manager.gd` | Currency, purchases |
| `UpgradeManager` | `upgrade_manager.gd` | Owned upgrades, stat modifiers |
| `KillBonusTracker` | `kill_bonus_tracker.gd` | Judges each player kill for style bonuses |
| `RunRecord` | `run_record.gd` | What happened this run, the trophies it earned, damage by cause |
| `Armory` | `armory.gd` | Weapon mastery and attachments: the one thing that carries between runs — see [[04 Weapons and Combat#Armory]] |
| `WaveManager` | `wave_manager.gd` | Wave sequencing, enemy spawn scheduling |
| `CombatDirector` | `combat_director.gd` | Coordinates the horde: roles, attack tokens, per-frame budget |
| `BroadcastRating` | `broadcast_rating.gd` | The broadcast rating: style multiplier — see [[06 Waves and Economy#Rating]] |
| `BroadcastRules` | `broadcast_rules.gd` | The per-wave broadcast rule, the shop offer and the contract — see [[06 Waves and Economy#Broadcast rules]] |
| `CrowdRequests` | `crowd_requests.gd` | Crowd requests ("we want a 360") — see [[06 Waves and Economy#Crowd requests]] |
| `NarratorManager` | `narrator_manager.gd` | Host VO lines, subtitle queue |
| `TutorialHintManager` | `tutorial_hint_manager.gd` | First-time-mechanic HUD hints |
| `BalanceHub` | `balance_hub.gd` | Editor-only live reload of balance `.tres` files |
| `ArenaSession` | `arena_session.gd` | The arena being built/played and its `user://` round trip |
| `DevConsole` | `dev_console.gd` | Debug-build in-game console |
| `FeedbackManager` | `feedback_manager.gd` | Player feedback reports: save / copy / open form |
| `BeehaveGlobalMetrics` / `BeehaveGlobalDebugger` | addon | Beehave's own (not ours) |

## EventBus

`scripts/autoload/event_bus.gd`. Signals only, grouped by domain:

```gdscript
# Combat
signal damage_dealt(target: Node, amount: float, is_headshot: bool)
signal enemy_killed(enemy_type: StringName, position: Vector3, reward: int)
signal kill_credited(reward: int)   # ...y es tuya: sólo si diste el golpe final
signal player_damaged(amount: float, remaining: float)
signal player_hit(amount: float, cause: StringName)   # same hit, with DamageCause; right before player_damaged
signal player_died()

# Weapons
signal weapon_fired(weapon_id: StringName)
signal weapon_reloaded(weapon_id: StringName)
signal ammo_changed(current: int, reserve: int)
signal weapon_switched(weapon_id: StringName)
signal weapon_ads_changed(is_ads: bool)   # whichever weapon is equipped

# Movement
signal fast_fall_landed()                  # replaced dash_used (2026-10-21)
signal grapple_started(anchor: Vector3)
signal grapple_ended()

# Waves
signal wave_started(wave_index: int, config: WaveData)
signal wave_completed(wave_index: int, duration: float, damage_taken: float)
signal match_completed(score: int, total_time: float)

# Economy
signal currency_changed(new_total: int)
signal purchase_made(item_id: StringName, cost: int)
signal shop_opened()
signal shop_closed()
signal shop_offers_rolled(offers: Array)   # [{id, rare}] per visit/reroll, for the run log

# Crowd (excerpt: the broadcast show)
signal broadcast_rules_offered(rule_ids: Array, contract_id: StringName)
signal broadcast_contract_started(contract_id, title, description, payout: int)
signal broadcast_contract_settled(contract_id: StringName, paid: int)
signal rating_peak(bonus: int)                 # top tier, once per wave
signal rating_sponsor_walkout(active: bool)    # too long off air: no gifts
signal crowd_request_started(request_id, title, goal: int, time_limit: float)
signal crowd_request_progress(request_id, progress: int, goal: int)
signal crowd_request_ended(request_id: StringName, success: bool)

# Match state
signal game_state_changed(new_state: int)
signal game_paused(is_paused: bool)   # rides its own signal, not part of State

# Settings
signal settings_applied()
```

`enemy_killed` y `kill_credited` no son redundantes: la primera anuncia una
muerte y la escucha todo lo que reacciona a eso (el contador de la oleada, el
anunciador, el feel), y sale siempre. La segunda dice "y esta plata es tuya", y
desde la atribución de muertes sale sólo cuando el golpe final fue del jugador —
ver [[05 Enemies and AI#Whose kill it was]]. `EconomyManager` cuelga de la
segunda, nunca de la primera.

`game_paused` is deliberately not folded into `game_state_changed`: pause can
interrupt any state and leaves the run intact underneath, so widening the state
enum to include it would be wrong. Added when the pause menu was built — see
[[07 UI and HUD#Pause menu]].

## RunSeed

`scripts/autoload/run_seed.gd`. One seed per run (`begin(fixed_seed)` from
`MatchDirector.start_match()`, with `GameManager.run_fixed_seed` — 0 rolls a new
one), and **one stream per system**: `RunSeed.rng(&"shop")`,
`&"broadcast_rules"`, `&"crowd_drops"`, `&"crowd_requests"`, `&"spread"`. Separate
streams so that buying one more upgrade doesn't move where the next medkit lands.
The systems keep a `_rng` property whose getter returns their stream, so the old
call sites (and the tests that seed `_shop._rng`) didn't change.

What the seed does **not** pin: physics, enemy AI jitter, the Host's line choice
and the music. Same seed = same offers, rules, contracts, requests, drops and
spread; not the same fight.

Share codes: `MAYHEM-<ARSENAL|weapon id>-XXXX-XXXX`, 40 bits in Crockford base 32
(`make_code()` / `parse_code()` / `encode_seed()` / `decode_seed()`). The mode
screen takes a pasted code; the end screen copies a line with the score and the
code. The run log stores the seed in the same format.

## GameManager

`State` enum: `MENU`, `PLAYING`, `SHOPPING`, `GAME_OVER`.

Key methods: `start_run()`, `restart_run()` (must land the player back in a
shooting state in under 2 seconds — a design constraint, not a suggestion),
`return_to_menu()`, `toggle_pause()` / `set_paused(bool)`. Listens for the
`pause` input action itself and for `EventBus.player_died`.

`restart_run()` / `return_to_menu()` are both `await _transition.fade_out()` →
`change_scene_to_file()` → `await _transition.fade_in()` — every scene change
in the game goes through this one path, so nothing can skip the fade and cut
straight to a new scene. `_transition` (`SceneTransition`,
`scripts/ui/scene_transition.gd` + `scenes/ui/scene_transition.tscn`) is
instantiated as `GameManager`'s own child in `_ready()` — since it is not part
of whatever scene `change_scene_to_file()` is about to replace, it survives
every change untouched, the same reason `GameManager` itself does. See
[[07 UI and HUD#Scene transitions]].

## ObjectPool

`acquire(scene: PackedScene) -> Node` / `release(instance: Node) -> void`.
Pre-warmable via `prewarm(scene, count)`. Pooled objects go into
`RELEASED_GROUP` group when freed, not `queue_free()`'d, and get
`_on_acquired()` / `_on_released()` lifecycle hooks (see `Enemy`,
`HazardZone`, `Projectile` for consumers).

## AudioPool

Bus constants: `BUS_MASTER`, `BUS_SFX`, `BUS_WEAPONS`, `BUS_IMPACTS`,
`BUS_ENEMIES`, `BUS_WORLD`, `BUS_MUSIC`, `BUS_VO`, `BUS_UI`. Per-bus default
gain and a Master `AudioEffectLimiter` (ceiling -1 dB, threshold -6 dB, so a
worst-case elite wave can't clip) live in `default_bus_layout.tres`, generated
by `tools/configure_audio_mix.gd` — see [[12 Known Issues and Gaps]] for what
that pass is and is not (a gain-staging default, not a real mix). Fixed-size voice
pools (`POOL_SIZE_3D = 48`, `POOL_SIZE_2D = 16`) rather than unbounded
`AudioStreamPlayer` instantiation. `play_3d()` / `play_2d()` are the entry
points; `push_duck()` / `pop_duck()` implement VO ducking
(`DUCK_AMOUNT_DB = -8.0`) as a stack, so overlapping duck requests resolve
correctly on release. `_apply_duck()` moves both `BUS_SFX` and `BUS_MUSIC`
together — one ref-counted mechanism, not two, so `MusicManager` gets VO
ducking for free the moment `NarratorManager` calls `push_duck()`/`pop_duck()`
around a line; it never needed its own.

### Voice priority

Una voz que no está libre ya no significa "este sonido no suena". `play_3d()` /
`play_2d()` toman una prioridad y, con el pool lleno, se la roban a una voz que
valga **estrictamente** menos. La escala (`AudioPool.Priority`) no mide
importancia en abstracto, mide qué se rompe si el sonido falta:

| Nivel | Qué es | Qué pasa si no suena |
|---|---|---|
| `CRITICAL` | El arma del jugador, la voz del Host | Se cae el pilar 1 |
| `TELEGRAPH` | Wind-ups, la espoleta del Bomber, el aviso del charco y el de la plataforma | Daño sin aviso — la regla de CLAUDE.md 5.3 |
| `NORMAL` | Todo lo demás: enemigos, mundo, UI | Se nota poco |
| `AMBIENT` | Impactos | No se nota: es un sonido por bala |

La prioridad **sale del bus** (`BUS_PRIORITY`), así que las cuarenta llamadas que
ya existían quedaron bien clasificadas sin tocar ninguna — el bus ya decía de qué
era cada sonido. La excepción son los avisos, que están repartidos entre `Enemies`
y `World` y por eso piden su nivel a mano; son cuatro llamadas.

Dos reglas que no son obvias:

- **Igual prioridad no roba.** Con "menor o igual", una ráfaga de SMG se cortaría
  a sí misma en el segundo tiro.
- **Se roba la voz más lejana del oyente**, a igual prioridad (la más vieja en el
  pool 2D, que no tiene posición). Un impacto a treinta metros ya casi no se oye.

Esto cierra el hallazgo §3 de [HANDOFF_FEEL_AND_FIXES.md](../historial/HANDOFF_FEEL_AND_FIXES.md):
`tools/configure_audio_mix.gd` describía la jerarquía "VO y Weapons arriba, UI
abajo", pero eso era ganancia. Esta es la mitad que faltaba, que es asignación de
voces. Era además precondición de los Gladiadores: tres bandos peleando llenan el
mix mucho más rápido que uno.

## MusicManager

`scripts/autoload/music_manager.gd`. Crossfades a looping music bed to match
`GameManager.state` (`EventBus.game_state_changed`) — `TRACK_PATHS` maps each
`GameManager.State` to a track under `assets/audio/music/`. Two
`AudioStreamPlayer`s on `AudioPool.BUS_MUSIC`, held directly rather than pulled
from `AudioPool`'s one-shot pool — a loop needs one stable, addressable player
to fade in/out over `CROSSFADE_TIME = 1.5s`, which "whichever pooled player
happens to be free" can't promise. `stream.loop_mode` is set to
`LOOP_FORWARD` in code on load rather than trusted to the asset's own import
settings, since the placeholder tracks are raw synthesized `.wav` output with
no guaranteed loop config baked in yet.

Tracks are placeholders (`tools/generate_placeholder_music.py`, same
synthesized-stand-in approach as `generate_placeholder_sfx.py`), not composed
music.

## SettingsManager

`DEFAULTS: Dictionary` is the single source of truth for every setting key
(`"input/mouse_sensitivity"`, `"video/fov"`, `"accessibility/view_bob_enabled"`,
etc.) — see [[07 UI and HUD#Options screen]] for how the options UI is generated
directly from this dictionary's keys via a schema, so a setting cannot exist in
one place without the other. `get_value(key, fallback)` / `set_value(key, value)`,
persisted via `ConfigFile` at `user://settings.cfg`. `apply_all()` re-applies
audio/video settings; `get_mouse_sensitivity(is_ads)` derives actual look-degrees-
per-pixel from the slider position and `Tokens.SENS_DEFAULT` — see the
`SENS_DEGREES_AT_DEFAULT` comment in the source for why the derivation exists at
all (pinning feel independent of the slider's default UI position).

## SaveManager

Local leaderboard — `user://leaderboard.json`, top `MAX_ENTRIES = 10`.
`submit_score(score, total_time, waves_cleared)`. **No UI currently reads this**
— see [[12 Known Issues and Gaps]].

Also owns which first-time tutorial hints have already been shown, in a
**separate** file (`user://tutorial.json`) with its own lifetime — clearing the
leaderboard must never also reset hints, or vice versa. `has_seen_hint(id)` /
`mark_hint_seen(id)` / `clear_tutorial_hints()` (wired to the options screen's
"Reset tutorial hints" button — see [[07 UI and HUD#Options screen]]). Neither
of these is meta-progression; nothing here affects a run's balance.

## EconomyManager

Wraps `EconomyConfig` (`data/economy/economy_config.tres`). `begin_wave()`,
`get_wave_kill_income()`, `award_wave_bonuses(wave, duration, took_damage)`
(returns a breakdown `Dictionary` — kills / completion / speed / no-damage — shown
verbatim by the shop screen), `try_purchase_upgrade(data, weapon_id)`,
`try_spend(item_id, cost)`.

## UpgradeManager

Owns everything the player has bought this run. `get_stat(stat_key, base_value,
weapon_id)` is the read path every other component's `_stat()` helper calls
through (`StatsComponent`, `WeaponComponent`, `MovementComponent` all resolve
their live values this way rather than reading `data` directly, so an upgrade
changes behavior without any component needing upgrade-awareness).
`add_upgrade(data, weapon_id)`, `can_add(data, weapon_id)` (stack limits),
`get_temporary_remaining(id, weapon_id)` for time-limited effects.

`weapon_id` scopes `Category.WEAPON` upgrades to the weapon they were bought
for (loadout design: one weapon at a time, buying a new one replaces the
current one — see [[04 Weapons and Combat#WeaponHolder]] — and its upgrades
stay behind rather than following the player to the new gun). Every dictionary
inside `UpgradeManager` is keyed by a *scope key* (`_key()`): `"<id>::<weapon_id>"`
when a weapon_id is given, or the bare id otherwise. `Category.MOBILITY` and
`Category.SURVIVABILITY` upgrades never pass a weapon_id and stay global, same
as before this scoping existed. Omitting `weapon_id` for a `Category.WEAPON`
purchase is a programming error — `add_upgrade` rejects it with `push_error`
rather than silently going global.

## WaveManager

`WAVE_COUNT = 10`. `setup(wave_list)`, `start_next_wave() -> bool`,
`spawn_summoned(enemy_data, position)` (used by the Summoner archetype — see
[[05 Enemies and AI]]), `get_last_breakdown()` (feeds `EconomyManager`'s bonus
calculation). Tracks `get_damage_taken_this_wave()` for the no-damage bonus and
resolves wave-clear via `_check_wave_cleared()` on every `enemy_killed` event
rather than a countdown timer.

## NarratorManager

Host VO line queue. `Tier` enum: `STANDARD` / `WARNING` / `PUNCHLINE`. Pacing
constants: `LINE_COOLDOWN = 20.0`, `DEFAULT_CATEGORY_COOLDOWN = 8.0`,
`PLACEHOLDER_DURATION = 2.5`. `request_line(line_id, category, text, ...)` — the
category cooldown prevents the same *kind* of line spamming even if the specific
line differs; the line cooldown prevents the exact line repeating too soon.
Emits `subtitle_shown` / `subtitle_hidden`, consumed by the HUD's subtitle box.

**Voice packs**: `say(occasion, format_args)` builds `line_id` as
`"<occasion>_<01-based index, zero-padded>"` — the same convention
`tools/export_host_script.gd` uses for recording filenames, so the id a line
gets tested under is the id it ships under — then resolves it against the
current presenter via `resolve_stream(line_id)`. `HostPresenter`
(`scripts/resources/host_presenter.gd`, catalogued by `HostPresenterCatalog`
at `data/host/presenters.tres`) is just `id` / `display_name` / `icon` /
`preview_line_id` — adding a presenter is authoring one of these and dropping
recordings under `res://assets/audio/voice/<id>/<line_id>.ogg`
(`VOICE_PATH_FORMAT`), no code change. A missing recording resolves to `null`
silently — `_play()` already falls back to `PLACEHOLDER_DURATION` and a
subtitle-only line when `stream` is null, so "nobody has recorded this yet" is
the expected steady state during production, not an error path.
`set_presenter(id)` clears `_voice_cache` (keyed by `line_id`, so repeated
lines don't hit `ResourceLoader.exists()` every time) — a no-op if the id is
already current. Selected in Settings (see
[[07 UI and HUD#Options screen]]), persisted as
`SettingsManager`'s `"audio/host_presenter"`. Ships with exactly one
presenter, `&"subtitles_only"` — no recordings exist yet.

## TutorialHintManager

`scripts/autoload/tutorial_hint_manager.gd`. Shows a one-line HUD overlay the
first time the player does each core mechanic — move, jump, mantle, slide,
fast fall, grapple, ADS, reload, first shop visit. Content is data
(`TutorialHint` / `TutorialHintCatalog`, `data/tutorial/tutorial_hints.tres`),
never string literals in the manager.

**Deliberately not `NarratorManager`**: the Host talks to the crowd, not the
player (Game Treatment) — a tutorial prompt is a neutral overlay, never a Host
line. "Seen" is permanent (`SaveManager.has_seen_hint`/`mark_hint_seen`), so a
hint never repeats once learned, across runs, until the player explicitly
resets it in Settings.

A small queue (`_queue`, `MAX_QUEUED = 4`) guarantees hints never overlap on
screen: `_try_show_next()` refuses to show a second hint while `_current` is
still set, even if called directly rather than from `_process()` — the
non-overlap guarantee lives on the method itself, not on caller discipline.

Hooks into gameplay two ways: global `EventBus` signals for anything that
already has one (`fast_fall_landed`, `grapple_started`, `weapon_reloaded`,
`shop_opened`, and the ADS-only `weapon_ads_changed` added for this), and a
direct binding to the current player's `MovementComponent` for the rest
(`started_moving`, `jumped`, `mantled`, and `state_changed` for `SLIDING`).
The `MovementComponent` binding rebinds on `EventBus.game_state_changed ==
GameManager.State.PLAYING` rather than once at startup, because the player
scene (and its `MovementComponent`) is recreated every run.

`{action}` in a hint's text substitutes the actually-bound key for
`TutorialHint.action`, read live from `InputMap` — a remapped key is never
wrong. Hints with no single key to name (movement, the shop) leave `action`
empty and skip substitution.

## KillBonusTracker

`scripts/autoload/kill_bonus_tracker.gd`. Decides **whether** a kill earned a
style bonus (headshot, airborne, spin, grapple, slide, long shot, point blank,
last round, double/triple/mayhem multi-kills, priority target); `EconomyConfig`
decides **how much** it pays. Player state (air, grapple, slide, magazine, camera
spin) is tracked frame by frame, because by the instant of the kill it is too
late to reconstruct. Bonus ids are stable `StringName`s, emitted on
`EventBus.kill_payout`.

## RunRecord

`scripts/autoload/run_record.gd`. Accumulates what happened in the run from
`EventBus` alone and awards trophies, which are saved **with the leaderboard
row**, not in a profile — trophies stay per run on purpose (the one exception to
"nothing carries over" is weapon mastery, see [[04 Weapons and Combat#Armory]]).
Trophy ids are stable so an old saved run keeps rendering. It also adds up damage
taken **by cause** (`player_hit`, ids from `DamageCause`: the archetype, `arena`
or `self`) and the cause of the killing hit; `get_death_recap()` feeds the end
screen ("Killed by Bomber - 62% of your damage came from Ranger").

`RunLogger` (`scripts/systems/run_logger.gd`) is its playtest sibling: one JSON
per run in `user://runs/`, format 2. Per run: seed (share-code format), mode,
weapon, worn attachments, shop offers per visit (with `rare`), damage by cause,
`killed_by`, death position. Per wave: damage by cause, rules offered / picked,
contract and what it paid, rating peak and average (sampled each second of
fight), crowd requests and whether they were met.

## CombatDirector

`scripts/autoload/combat_director.gd`. Decides what can only be decided looking
at the whole horde: (1) **each enemy's post** — bearings around the target are
handed out by role (`ROLE_BANDS`), never duplicated; (2) **who commits** —
blocking telegraphed attacks (the leap) need a token, so a 30-enemy wave stays
readable; (3) **the per-frame budget** — neighbours and repaths are served from
a grid and a quota instead of a full scan per enemy. Autoload because pooled
enemies outlive arenas. Why and the numbers:
[PLAN_COMBAT_DIRECTOR](../historial/PLAN_COMBAT_DIRECTOR.md).

### Respuesta a la retirada (2026-10-23)

Retroceder disparando contra una horda que viene de frente era gratis: el
jugador caminaba hacia atrás a 7.5 m/s, el Rusher corre a 7.2 y los tiradores
apuntaban a donde estaba. No se prohíbe; se vuelve caro y poco eficiente.

- **Medición** — `RetreatPressure` (`scripts/systems/retreat_pressure.gd`),
  0–1: sube sólo con la parte de la velocidad que va hacia atrás de la mirada
  (de costado no cuenta), por encima de `min_retreat_speed`, en `rise_time`;
  baja en `fall_time`, más corto. Por debajo de `onset` la horda no contesta;
  la respuesta (`CombatDirector.retreat_effect()`) es una curva suave y escala
  de `first_wave_strength` en la ola 1 a completa en `full_strength_wave`.
- **Respuestas**, todas proporcionales a ese efecto:
  - *Corte de camino*: hasta `max_interceptors` cuerpo a cuerpo/bombas que ya
    están del lado hacia donde retrocede caminan a `interception_point()` (la
    retirada adelantada `interception_lead_time`) en vez de perseguir.
  - *Tiros y saltos que adelantan*: `fire_projectile()` y `start_leap()` suman
    `retreat_lead()` — sólo la componente hacia atrás, así que moverse de
    costado se sigue esquivando igual.
  - *Frascos*: el Environmental suma `flask_lead_bonus` de la retirada a su
    predicción.
  - *Persecución*: los BRAWLER corren hasta `pursuit_speed_bonus` más rápido;
    se lee en el paso del modelo, que sale de la velocidad.
  - *Puertas*: entre las que nombra el grupo, `EnemySpawner` pesa más las que
    quedan hacia donde va el jugador (`door_weight()`, nunca menos de 1).
- **Números**: `data/combat/retreat_pressure.tres` (`RetreatPressureConfig`).
  **Telemetría**: `RunLogger` formato 3 guarda `retreat_avg`/`retreat_peak` por
  ola.
- Complemento del lado del jugador: `MovementComponent.backpedal_speed_multiplier`
  (ver [[03 Player and Movement#Ground / Air]]).

## BalanceHub

`scripts/autoload/balance_hub.gd`. Editor-only: watches `res://data/economy`
and `res://data/enemies` every `POLL_INTERVAL = 0.5s` and reloads any changed
`.tres` with `CACHE_MODE_REPLACE`, so a value tweaked in the Balance Editor
lands in the running match without a restart — every system already holding
that resource keeps its reference and just sees new numbers. An exported
build has no writable resource files to watch, so this does nothing there.

## ArenaSession

`scripts/autoload/arena_session.gd`. Owns the arena currently being built or
played and where it lives: `res://data/arena_pieces/default_catalog.tres` for
the piece catalog, `user://arenas` for player-made arenas, `res://data/arenas`
for shipped ones (`default_arena.tres`, authored at the single fixed size —
see [[06 Waves and Economy#Arena]]). It is the one object that knows both the
arena-editor addon and the game scene, since neither of those knows the other
exists: `new_arena()`, `save()`/`load()`, and the round trip out to a
playtest via `GAME_SCENE` and back to `EDITOR_SCENE`.

## DevConsole

`scripts/autoload/dev_console.gd`. Debug builds only, a `CanvasLayer` toggled
open at `OPEN_HEIGHT = 0.45` of the viewport. Commands are data
(`_commands: Dictionary`, name → `{args, help, handler}`) that call straight
into systems that already exist — the console owns no gameplay rules of its
own, so it can't drift from what it's testing. Freezes the tree under its own
`FREEZE_REASON` so it doesn't fight the pause menu's own freeze.

## FeedbackManager

`scripts/autoload/feedback_manager.gd`. Writes one JSON file per report to
`user://feedback/feedback_<timestamp>.json`: the player's text, a category,
and automatic context (version, arena, wave, score, session time, OS,
resolution, GPU, average FPS) — the context is what makes a report useful,
since nobody writes that by hand. Reads `FeedbackConfig`
(`data/feedback/feedback_config.tres`) for the external form URL, which ships
empty until there's a form to point at (see [[07 UI and HUD#Feedback panel]]).
Nothing leaves the machine on its own: save writes the file, copy puts the
report on the clipboard, and opening the form is a separate, explicit button.
