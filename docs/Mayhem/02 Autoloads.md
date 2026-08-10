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
| `SettingsManager` | `settings_manager.gd` | User settings: load/save/apply |
| `SaveManager` | `save_manager.gd` | Local leaderboard |
| `EconomyManager` | `economy_manager.gd` | Currency, purchases |
| `UpgradeManager` | `upgrade_manager.gd` | Owned upgrades, stat modifiers |
| `WaveManager` | `wave_manager.gd` | Wave sequencing, enemy spawn scheduling |
| `NarratorManager` | `narrator_manager.gd` | Host VO lines, subtitle queue |
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
`BUS_ENEMIES`, `BUS_WORLD`, `BUS_MUSIC`, `BUS_VO`, `BUS_UI`. Fixed-size voice
pools (`POOL_SIZE_3D = 48`, `POOL_SIZE_2D = 16`) rather than unbounded
`AudioStreamPlayer` instantiation. `play_3d()` / `play_2d()` are the entry
points; `push_duck()` / `pop_duck()` implement VO ducking
(`DUCK_AMOUNT_DB = -8.0`) as a stack, so overlapping duck requests resolve
correctly on release.

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

Local leaderboard only — `user://leaderboard.json`, top `MAX_ENTRIES = 10`.
`submit_score(score, total_time, waves_cleared)`. **No UI currently reads this**
— see [[12 Known Issues and Gaps]].

## EconomyManager

Wraps `EconomyConfig` (`data/economy/economy_config.tres`). `begin_wave()`,
`get_wave_kill_income()`, `award_wave_bonuses(wave, duration, took_damage)`
(returns a breakdown `Dictionary` — kills / completion / speed / no-damage — shown
verbatim by the shop screen), `try_purchase_upgrade(data)`, `try_spend(item_id, cost)`.

## UpgradeManager

Owns everything the player has bought this run. `get_stat(stat_key, base_value)`
is the read path every other component's `_stat()` helper calls through
(`StatsComponent`, `WeaponComponent`, `MovementComponent` all resolve their live
values this way rather than reading `data` directly, so an upgrade changes
behavior without any component needing upgrade-awareness). `add_upgrade(data)`,
`can_add(data)` (stack limits), `get_temporary_remaining(id)` for time-limited
effects.

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
