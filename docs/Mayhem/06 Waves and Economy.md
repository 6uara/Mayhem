---
tags: [mayhem, waves, economy, shop]
estado: referencia
actualizado: 2026-10-21
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

Weapons are not in the common draw. After the one-per-category guarantee,
`_roll()` reserves a slot for one weapon with `ShopCatalog.weapon_offer_chance`
(0.6), only in modes where `GameManager.shop_sells_weapons()`; that slot counts
as guaranteed, so a rare never replaces it. A visit can then show five cards
(three categories, a weapon, a rare). Before 2026-10-21 weapons competed with
every upgrade for the single free slot and showed up in under one visit in ten.

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
wave and bonus numbers: `no_damage_bonus`, the kill-bonus payouts
(`bonus_headshot`, `bonus_spin`, `bonus_mayhem`…, judged by `KillBonusTracker`),
the currency lost per point of damage taken, tiered
`speed_bonus_tiers` / `speed_bonus_payouts` (par-time fraction → payout, first
tier crossed wins), `currency_multiplier`, `starting_currency`.

**Kill rewards are not here.** What a kill pays is `EnemyData.reward_currency`,
per archetype `.tres`. `EconomyConfig` still carries `kill_reward_*` fields that
only the balance editor's curve reads — see
[[12 Known Issues and Gaps#Minor drift]].

## Arena

Fixed size: `ArenaData.SIZE_PRESETS` has a single entry, `32×8×32`
(`grid_size` defaults to `Vector3i(32, 8, 32)`), and the size selector is gone
from both the in-editor dock and `arena_editor_hud.gd` — see
[[02 Autoloads#ArenaSession]] for who owns loading/saving an arena.
`ArenaData.from_dict()` forces `grid_size` to 32 for anything saved under the
old variable-size format, so a player's existing arenas still load.
`data/arenas/default_arena.tres` is re-authored to fill the grid rather than
sit in an 8-cell margin — generated by
[tools/make_default_arena.gd](../../tools/make_default_arena.gd), a headless
script (`godot --headless --path . -s tools/make_default_arena.gd`) rather
than hand-edited, so the shipped arena stays reproducible. The floor is built
from `floor_3x3` blocks with `floor_2x2` trim strips, not 1024 individual
`floor_1x1` pieces.

## Spawn doors

`scripts/systems/spawn_door.gd` + `scenes/arena/spawn_door.tscn`. The doors are
part of the arena file: `ArenaLoader._build_spawn_doors()` instances one per
spawn point saved in the `ArenaData` and names them `door_01`, `door_02`… in
order (`data/waves/*.tres` reference them by `spawn_door_ids:
Array[StringName]`). Distribution across the arena is a level-design job: no
single camping spot should cover all of them. See
[[08 VFX and Shaders#`portal_spawn.gdshader`]] for the door's visual telegraph.

## Score

`RunRecord.get_score(victory)`: **kills + style + waves**, plus
`score_victory_bonus` for winning. Kill points are the base reward ×
`score_per_kill_reward`; style points are each kill's bonus total ×
`score_per_style` × `EconomyManager.get_style_multiplier()` (rating and
Showman); a cleared wave N adds `score_per_wave` × N. Numbers in
`EconomyConfig`, group Score. Neither total time nor banked currency count: the
old formula gave an early death almost the whole time bonus and made shopping
lower the score. The end screen shows the three parts.

## Game modes

`GameManager.Mode` — `ARSENAL` (start with the pistol, the shop sells every
other weapon, every weapon has a price) and `SINGLE_WEAPON` ("ONE GUN": the
weapon picked in `ModeSelect` is the run's weapon, `Shop._build_pool()` offers
no weapons). Chosen from the main menu's Play button before the arena;
`WeaponHolder._starting_weapon()` reads `GameManager.get_starting_weapon_id()`.

## Rare upgrades

`UpgradeData.is_rare` + `ShopCatalog.rare_upgrades`: kept out of the regular
pool and the one-per-category guarantee. `Shop._roll_rare()` adds at most one per
visit, from wave `rare_from_wave` (2), with `rare_offer_chance` (0.45), taking
the slot of a random (never a guaranteed) offer. Each one is StatModifiers on a
stat whose base is neutral (`StatsComponent.SLIDE_RELOAD_RATE` and siblings), so
the rule is off until bought; the rules live in `PlayerPerks`, `WeaponComponent`
(Air Ace), `BouncePad` (Pad Charger) and `EconomyManager` (Showman). Healing is
the common upgrade *Nanoweave* (`HEALTH_REGEN`, after `PlayerPerks.REGEN_DELAY`
without damage) and the crowd's medkit (see [[13 Arena, Venue and Crowd]]).

## Rating

`BroadcastRating` (autoload, `data/economy/rating_config.tres`). 0-100. A kill
with style adds `gain_per_bonus` × bonuses × speed factor (player speed over
`bhop_max_speed`) × pace factor (kills in the last `pace_window`); a plain kill
subtracts `plain_kill_drop`; it decays `decay_per_second` while a wave is live and
freezes in the shop. Multiplies style money and score (up to `max_multiplier`)
and shortens the crowd's drop interval. Only measures while a match runs
(`tracking`, set by `MatchDirector`). Tier crossings go out on
`EventBus.rating_tier_changed` for the Host. HUD: `RatingMeter`, under the money.

## Broadcast rules

`BroadcastRules` (autoload) + `BroadcastRule` resources in
`data/broadcast_rules/`, pooled by `rule_pool.tres`. From wave `from_wave` (3),
never on elite waves, no repeats until the pool runs out. Only active when
`MatchDirector.broadcast_rules_enabled` (true in `game.tscn`).

**Offer and pick.** When the break opens, `MatchDirector._open_break()` calls
`BroadcastRules.prepare_offer(next_wave)`: `offer_size` (2) distinct rules and,
with `contract_chance`, one contract. The shop screen shows them
(`ShopScreen._refresh_broadcast_box()`); the player picks a rule
(`choose_rule()`, default the first) and may sign the contract
(`set_contract_signed()`). `wave_started` starts what was picked. With no offer
(wave 1, tests that emit `wave_started` by hand) it falls back to a random
`pick_for()`.

**What a rule can touch** (all data):

| Group | Fields | Used by |
|---|---|---|
| Economy | `bonus_multipliers`, `kill_reward_multiplier`, `rating_gain_multiplier` | `KillBonusTracker`, `EconomyManager`, `BroadcastRating` |
| Arena | `drop_interval_multiplier`; `kill_hazard_*` (every kill leaves a pooled `HazardZone`, ownerless) | `CrowdDropDirector`; `BroadcastRules._on_enemy_killed()` |
| Enemies | `enemy_modifiers: Array[EnemyRuleModifier]` (health/speed/damage per archetype or all); `mark_every` / `mark_limit` (Manhunt) | `Enemy.setup()` → `BroadcastRules.enemy_multipliers()` / `should_mark_spawn()` |
| Player | `stat_modifiers`, applied as a temporary global upgrade (`rule_<id>` / `contract_<id>`) | `UpgradeManager` |
| Contract | `contract_payout` + `contract_payout_per_wave` (> 0 makes it a contract) | `EconomyManager.award_wave_bonuses()` (`contract_bonus` row) |

Rule and contract stack: every accessor multiplies the active rule by the
contract. A contract settles on `wave_completed` (paid) or `player_died` (0) with
`broadcast_contract_settled`.

**Manhunt.** A marked enemy wears an amber ring (`Enemy._set_marked()`, REWARD
colour + circle, the "this pays" law). On death by the player, the enemy calls
`BroadcastRules.note_marked_kill()` right before `kill_scored`, and
`KillBonusTracker` consumes it as the `marked` bonus
(`EconomyConfig.bonus_marked`). The kill signal carries no body, so the flag is
synchronous within the frame.

Rules today: Headshot Night, Air Show, Moon Boots, Sponsored Reloads, Crowd
Frenzy, Glass Cannon, Combo Hour, Scorched Earth, Manhunt, Heavyweights, Fast
Forward. Contracts (`data/broadcast_rules/contracts/`): Grounded, No Hook, Short
Mags, Paper Armor, Lead Boots.

HUD: one chip under the wave number with the rule and the contract.

## Rating consequences

On top of the multiplier (see [[#Rating]]), two events in `BroadcastRating`,
numbers in `rating_config.tres` group *Consecuencias*:

- **Peak** — the first time per wave the rating reaches the top tier:
  `EconomyManager.award_show_bonus(peak_bonus)` (the `show_bonus` row of the
  breakdown) and `rating_peak`, on which `CrowdDropDirector` throws a gift at once.
- **Sponsor walkout** — `walkout_after` seconds of fight in the bottom tier, from
  wave `walkout_from_wave` (3): `rating_sponsor_walkout(true)` and the crowd stops
  throwing until the rating leaves the floor; then the first gift comes right away.

## Crowd requests

`CrowdRequests` (autoload) + `CrowdRequest` resources in `data/crowd_requests/`,
pooled by `request_pool.tres`. From wave `from_wave` (2), one request at a time:
`goal` kills carrying `bonus_id` (any `KillBonusTracker` id) within `time_limit`.
Counted from `kill_payout`. Met → `BroadcastRating.boost(reward_rating)`,
`award_show_bonus(reward_currency)` and, if `throws_gift`, a gift from
`CrowdDropDirector`. Failing or the wave ending just closes it. Turned on with the
broadcast rules by `MatchDirector`. HUD: a chip under the rule chip with progress
and seconds left; the Host announces and celebrates.
