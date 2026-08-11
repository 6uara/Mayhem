---
tags: [mayhem, architecture, autoloads]
---

# Autoloads

Registered in `project.godot` under `[autoload]`, in this exact order (load order
matters — `Tokens` loads before `EventBus`, everything loads before Beehave's
globals):

| Name | File | Owns |
|---|---|---|
| `Tokens` | `theme_tokens.gd` | Design constants — see [[09 Design Tokens and Color Law]] |
| `EventBus` | `event_bus.gd` | Cross-system signals |
| `GameManager` | `game_manager.gd` | Match state machine, pause |
| `ObjectPool` | `object_pool.gd` | Pooled instantiation |
| `AudioPool` | `audio_pool.gd` | 3D/2D voice pool, buses, ducking |
| `MusicManager` | `music_manager.gd` | Crossfaded music bed, follows match state |
| `SettingsManager` | `settings_manager.gd` | User settings: load/save/apply |
| `SaveManager` | `save_manager.gd` | Local leaderboard |
| `EconomyManager` | `economy_manager.gd` | Currency, purchases |
| `UpgradeManager` | `upgrade_manager.gd` | Owned upgrades, stat modifiers |
| `WaveManager` | `wave_manager.gd` | Wave sequencing, enemy spawn scheduling |
| `NarratorManager` | `narrator_manager.gd` | Host VO lines, subtitle queue |
| `TutorialHintManager` | `tutorial_hint_manager.gd` | First-time-mechanic HUD hints |
| `BeehaveGlobalMetrics` / `BeehaveGlobalDebugger` | addon | Beehave's own (not ours) |

## EventBus

`scripts/autoload/event_bus.gd`. Signals only, grouped by domain:

```gdscript
# Combat
signal damage_dealt(target: Node, amount: float, is_headshot: bool)
signal enemy_killed(enemy_type: StringName, position: Vector3, reward: int)
signal player_damaged(amount: float, remaining: float)
signal player_died()

# Weapons
signal weapon_fired(weapon_id: StringName)
signal weapon_reloaded(weapon_id: StringName)
signal ammo_changed(current: int, reserve: int)
signal weapon_switched(weapon_id: StringName)
signal weapon_ads_changed(is_ads: bool)   # whichever weapon is equipped

# Movement
signal dash_used(charges_remaining: int)
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

# Match state
signal game_state_changed(new_state: int)
signal game_paused(is_paused: bool)   # rides its own signal, not part of State

# Settings
signal settings_applied()
```

`game_paused` is deliberately not folded into `game_state_changed`: pause can
interrupt any state and leaves the run intact underneath, so widening the state
enum to include it would be wrong. Added when the pause menu was built — see
[[07 UI and HUD#Pause menu]].

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
synthesized-stand-in approach as `generate_placeholder_sfx.py` — see
`assets/audio/music/CREDITS.md`), not licensed/composed music.

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
dash, grapple, ADS, reload, first shop visit. Content is data
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
already has one (`dash_used`, `grapple_started`, `weapon_reloaded`,
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
