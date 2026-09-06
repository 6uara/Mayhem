---
tags: [mayhem, waves, economy, shop]
---

# Waves and Economy

## Match flow

`MatchDirector` (`scripts/systems/match_director.gd`) is the top-level
conductor: `start_match()` → schedule first wave after `first_wave_delay` →
on `EventBus.wave_completed`, run the shop phase
(`shop_open_delay` pause, then open `shop_screen` and await its close) →
schedule the next wave after `between_wave_delay` → repeat until
`WaveManager.is_last_wave()`, then `_finish_match()` (submits score via
`SaveManager`, emits `EventBus.match_completed`). `_on_player_died()` cuts the
sequence short. Every scheduled step carries a `generation` counter so a stale
timer from a previous match/restart can't fire into the new one.

## WaveData / SpawnGroup

`WaveData` (`scripts/resources/wave_data.gd`): `wave_index`, `spawn_groups: Array[SpawnGroup]`,
`par_time` (speed-bonus target), `completion_bonus`, `is_elite_wave`.

`SpawnGroup` (`scripts/resources/spawn_group.gd`): one batch — `enemy_data`,
`count`, `spawn_door_ids`, `delay` (seconds after wave start), `interval`
(seconds between individual spawns in the group). `get_total_duration()` =
`delay + (count - 1) * interval`.

10 waves authored in `data/waves/wave_01.tres` … `wave_10.tres`. Content rules
enforced by `tests/unit/test_wave_content.gd`:

- Elite wave every 5th (`wave_index % 5 == 4` — waves 5 and 10).
- Enemy count never decreases wave-over-wave (waves 5/10 excluded from the direct
  comparison, since an elite wave deliberately trades bodies for an elite).
- `par_time` rises across normal waves; an elite wave's `par_time` must exceed
  the wave immediately before it (elites are damage sponges — they need more time,
  not less, than the wave that precedes them).

## WaveManager → EnemySpawner → SpawnDoor

`WaveManager` (autoload) schedules each `SpawnGroup` via `_schedule_wave()` /
`_spawn_group()` / `_spawn_one()`, calling into `EnemySpawner`
(`scripts/systems/enemy_spawner.gd`, a scene node under `MatchDirector`) which:

1. `telegraph(door_ids)` — tells each matching `SpawnDoor` to light up and sound
   off (`SpawnDoor.telegraph()`, see [[08 VFX and Shaders#`portal_spawn.gdshader`]]) and **awaits**
   it, so the first enemy of a group never appears before its tell.
2. `spawn(enemy_data, door_ids)` — picks a door (`_pick_door`, weighted toward
   least-recently-used) and acquires a pooled `Enemy` via `ObjectPool`, calling
   `Enemy.setup(enemy_data, door.get_spawn_position())`.
3. `close_doors(door_ids)` once a group finishes.

`spawn_at(enemy_data, position)` bypasses the door system entirely — used by
`WaveManager.spawn_summoned()` for the Summoner archetype's mid-fight spawns,
which have no door to telegraph from.

## Shop

`Shop` (`scripts/systems/shop.gd`), child of `ShopScreen`
(`scripts/ui/shop_screen.gd` + `scenes/ui/shop_screen.tscn`).

`Kind` enum: `UPGRADE`, `WEAPON`, `UTILITY`. `roll_offers()` builds a randomized
set from `ShopCatalog` (`_build_pool()` — excludes the weapon currently
equipped and upgrades maxed out for their scope, see
[[02 Autoloads#UpgradeManager]]), resets the reroll price, emits
`offers_changed`. `can_afford(offer)` / `buy(offer)` → `_execute()` dispatches
to `_buy_weapon()` / `_buy_utility()` / `_buy_upgrade()` (threads the currently
equipped `weapon_id` into `EconomyManager.try_purchase_upgrade()` for
`Category.WEAPON` offers, empty otherwise).

`offers_per_visit = 4` (down from the catalogue's full size) plus
`reroll()`: spends currency (`ShopCatalog.reroll_base_cost`, rising by
`reroll_cost_increment` per use within the same visit, reset by the next
`roll_offers()`) to rebuild the offer list without leaving the shop.
`get_reroll_cost()` / `can_reroll()` for the UI to show/gate the button.
Still respects `guarantee_one_per_category` — the whole point of that
guarantee is that bad luck can't lock a run out of a track, and a reroll that
bypassed it would just reintroduce the same problem at a price.

`ShopScreen` itself: `open(breakdown, wave_index, duration_seconds)` formats the
wave-clear breakdown (kills / completion / speed bonus / no-damage bonus —
shown explicitly, because that legibility is what makes the economy teachable),
pauses the tree, shows the cursor. Cards are built procedurally
(`_make_card()`) from a `ChamferStyleBox` panel per offer — see
[[07 UI and HUD#Theme system]]. A `Category.WEAPON` upgrade card is labelled
with the weapon it applies to (`_category_label()` → `_weapon_name()`), and a
weapon offer's description warns it replaces the current weapon before the
player spends money on a surprise. `duration` (default from `Tokens.SHOP_TIMER`)
is a self-closing timer; the shop is skippable, but banking the speed bonus by
leaving quickly is a real decision the player can make.

## EconomyManager / UpgradeManager

See [[02 Autoloads#EconomyManager]] and [[02 Autoloads#UpgradeManager]] for the
autoload API. `EconomyConfig` (`data/economy/economy_config.tres`) holds the
actual numbers: per-archetype kill rewards, `no_damage_bonus`, tiered
`speed_bonus_tiers` / `speed_bonus_payouts` (par-time fraction → payout, first
tier crossed wins), `currency_multiplier`, `starting_currency`.

## Arena

Fixed size: `ArenaData.SIZE_PRESETS` has a single entry, `32×8×32`
(`grid_size` defaults to `Vector3i(32, 8, 32)`), and the size selector is gone
from both the in-editor dock and `arena_editor_hud.gd` — see
[[02 Autoloads#ArenaSession]] for who owns loading/saving an arena.
`ArenaData.from_dict()` forces `grid_size` to 32 for anything saved under the
old variable-size format, so a player's existing arenas still load.
`data/arenas/default_arena.tres` is re-authored to fill the grid rather than
sit in an 8-cell margin — generated by
[tools/make_default_arena.gd](../tools/make_default_arena.gd), a headless
script (`godot --headless --path . -s tools/make_default_arena.gd`) rather
than hand-edited, so the shipped arena stays reproducible. The floor is built
from `floor_3x3` blocks with `floor_2x2` trim strips, not 1024 individual
`floor_1x1` pieces.

## Spawn doors

`scripts/systems/spawn_door.gd` + `scenes/arena/spawn_door.tscn` — seven placed
by hand around the arena (`data/waves/*.tres` reference them by
`spawn_door_ids: Array[StringName]`, e.g. `&"door_01"`). Distribution across the
arena is a level-design job: no single camping spot should cover all seven. See
[[08 VFX and Shaders#`portal_spawn.gdshader`]] for the door's visual telegraph.
