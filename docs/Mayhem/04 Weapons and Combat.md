---
tags: [mayhem, weapons, combat]
---

# Weapons and Combat

## WeaponData

`scripts/resources/weapon_data.gd`. Pure balance schema — no mesh field
originally (see [[#Viewmodel]] for why one exists now). Groups: Damage
(`damage`, `headshot_multiplier`, falloff start/end/min), Firing (`fire_rate`,
`projectiles_per_shot` — shotgun > 1, `projectile_speed`, plus `is_hitscan` and
`tracer_every_n_shots` — see [[#Hitscan and tracers]]), Ammo (`magazine_size`,
`reserve_ammo_max`, `reload_time`), Recoil and spread (`recoil_pattern`,
`spread_hipfire`/`spread_ads`, moving/airborne multipliers), ADS
(`ads_fov`, `ads_transition_time`, `ads_move_speed_multiplier`).

`get_damage(distance, is_headshot)` applies falloff then headshot multiplier —
the one place damage math actually happens; callers never compute it inline.

Instances: `data/weapons/pistol.tres`, `rifle_ak.tres`, `shotgun.tres`, `smg.tres`.
The player starts with the pistol equipped (`WeaponHolder._ready()` equips
`_weapons[0]`, first child by convention); buying another weapon from the shop
*replaces* it rather than adding a second slot — see [[#WeaponHolder]].

## WeaponComponent

`scripts/components/weapon_component.gd`. One equipped weapon: firing,
deterministic recoil, spread, ADS, reload, ammo. **Every weapon the player can
own exists as a child node from the start** — owning one just enables it
(`WeaponHolder` toggles `visible`/`set_process`). This is what keeps per-weapon
ammo persistent across switches and shop visits with zero save/restore logic.

- `set_trigger(held)`, `try_reload()`, `set_ads(value)` — the input surface.
- Firing computes spread from `get_current_spread()` (airborne/moving multipliers
  stack), applies it around the aim direction (`aim_node`, the head pivot — *not*
  the camera, so cosmetic kick never moves a shot), and spawns the projectile
  from `ObjectPool`.
- `_apply_recoil()` reads the weapon's `RecoilPattern` and calls into
  `CameraRecoilComponent.apply_shot()` — see [[03 Player and Movement#CameraRecoilComponent]].
- `_stat()` resolves every live number (fire rate, magazine size, spread, recoil
  magnitude, ADS transition time) through `StatsComponent.get_stat_from()`, which
  chains to `UpgradeManager` — a weapon never reads `data` fields raw once
  upgrades are in play.

### Recoil

`RecoilPattern` (`scripts/resources/recoil_pattern.gd`) — a fixed sequence of
per-shot offsets (`get_offset(shot_index, magnitude)`), not randomness. The
pattern resets after `reset_time` without firing, which is the mechanic that
makes a spray *learnable*: the same trigger discipline reproduces the same
pattern every time. See `tests/unit/test_recoil_pattern.gd`.

### Viewmodel

`WeaponData` gained `viewmodel: PackedScene`, `viewmodel_scale`,
`viewmodel_offset`, `viewmodel_rotation_degrees`. `WeaponComponent._spawn_viewmodel()`
instantiates it as a child on `_ready()`. All four weapons now have real
low-poly meshes (`assets/models/weapons/*.fbx`) — ak47 (Rifle), shotgun,
mac10 (SMG), pew (Pistol) — imported directly as `PackedScene`, no manual mesh
extraction needed since the scene's own node transforms carry the correct scale.

**Contrast with enemy meshes**, which *do* need extraction — `EnemyData.mesh` is
typed `Mesh`, not `PackedScene`, so an enemy's source `.fbx` gets its transform
hierarchy baked into a standalone `ArrayMesh` offline and saved under
`assets/models/meshes/*.res`. See [[05 Enemies and AI#Enemy meshes]].

Recoil *kick* on the viewmodel (cosmetic, `view_kick_back` / `view_kick_up_degrees`
/ `view_kick_recovery`) lives directly on `WeaponComponent`, applied in local
space to `_view.position`/`rotation_degrees` — **not** on `CameraFeelComponent`,
because it's specific to the currently-equipped weapon's own child node, not the
shared camera rig.

A separate HUD-layer `SubViewport` gun placeholder existed earlier in the
project's history and was removed — it duplicated this system with a generic
grey box, never fed the equipped weapon, and silently overlaid the real
viewmodel. If you find references to `scripts/ui/viewmodel.gd` anywhere, it's
stale; the file itself was deleted.

## WeaponHolder

`scripts/components/weapon_holder.gd`. One weapon carried at a time (loadout
design). Owns the swap (`start_swap` — firing is blocked for `swap_time` during
a swap), replacement (`acquire(weapon_id)` — equips `weapon_id`, replacing
whatever was current; returns `false` if it's already equipped), and top-up
(`add_reserve_ammo_fraction` — what an ammo pickup grants, applied to the
currently equipped weapon only).

`owns(weapon_id)` means "is this the weapon equipped right now", not "was this
ever bought" — a replaced weapon is not destroyed (it keeps its ammo and just
stops being `current`), and the shop offers it again like any other weapon not
currently equipped. Buying it back re-equips that same node.

Every WEAPON-category upgrade purchase is scoped by `weapon_id` in
`UpgradeManager` (see [[02 Autoloads#UpgradeManager]]) — a replaced
weapon's upgrades stay behind with it rather than following the player to the
new gun, and reappear if that weapon is bought back later. MOBILITY and
SURVIVABILITY upgrades are unaffected by any of this; they stay global.

No weapon-switch input remains — `handle_input()` is a no-op kept only because
`Player` still calls it every event. The `weapon_next`/`weapon_prev`/`weapon_1..4`
actions stay defined in the input map (remap screens list every action) but
nothing consumes them.

## Hitscan and tracers

The player's weapons resolve their shot **at the trigger**, not in flight. The
raycast that was already fired every shot to aim the muzzle (`_aim_hit()`, see
[[#WeaponComponent]]) now returns the whole hit, because that is precisely the
question the bullet used to fly off and repeat. What still flies is a *tracer*: the same pooled
`Projectile` node with `_is_tracer` set, which travels at `projectile_speed` to
the already-known impact point and never queries physics again.

Measured on the elite wave with sustained SMG fire: 2.89 → 2.48 ms/frame average
(−14%), worst frame 5.56 → 3.29 ms (−41%). The saving is in **drawing fewer
bullets, not computing less** — a tracer that never raycasts costs nearly what the
whole projectile cost, because the expense is the node (its `_physics_process`,
transform and pool traffic), not the arithmetic inside it. Converting to hitscan
while still drawing one bullet per shot measured slightly *worse* than the
original projectiles.

Two `WeaponData` fields drive it:

- `is_hitscan` (default `true`) — turn it off for a weapon whose flight time is
  part of the design. **Enemy projectiles never go through this path**: they use
  `EnemyProjectile`, where flying *is* the mechanic because it is what makes them
  dodgeable.
- `tracer_every_n_shots` — draw one bullet in N. This is a knob for **high rate of
  fire**, not for high `projectiles_per_shot`: it works because the eye fills the
  gap over time, so at 15 rounds/sec one in three still reads as a continuous line
  of fire. Rifle and SMG use 3. The shotgun deliberately uses 1 — its nine pellets
  leave at once, so the spread pattern is the entire visual with no following
  bullets to complete it, and at 1.4 shots/sec there was nothing to save.

A bullet that is not drawn also leaves no impact or decal, since the tracer is
what spawns them on arrival. Feedback for *hitting an enemy* does not depend on
this — hitmarker and damage numbers come from `take_hit` via
`EventBus.damage_dealt`, always.

Damage is read through `get_damage()`, not `data.damage`. This matters more than
it looks: the projectile path received the upgraded number via `damage_override`,
and reading the raw field when the shot moved to the trigger silently disabled
every purchased damage upgrade on all four player weapons. The whole suite passed
with that bug in place, because nothing crossed "bought an upgrade" with "fired a
shot" — `test_a_damage_upgrade_reaches_a_hitscan_shot` now does.

## Projectile / hitbox / health

- `scripts/systems/projectile.gd` — pooled, `launch(origin, direction, data, shooter, damage)`
  for a real projectile, `launch_tracer(from, to, speed, normal, surface, spawn_impact)`
  for the cosmetic half of an already-resolved hitscan shot.
- `HitboxComponent` (`scripts/components/hitbox_component.gd`) — per-zone
  (`is_headshot_zone`), applies `damage_multiplier`, forwards to a
  `HealthComponent`.
- `HealthComponent` (`scripts/components/health_component.gd`) — `apply_damage()`,
  `heal()`, `damaged`/`died` signals, `damage_taken_multiplier` (survivability
  upgrades apply here, bridged by `Player._apply_survivability_stats()`).

## StatsComponent

`scripts/components/stats_component.gd`. The single indirection every
upgrade-aware read goes through: `get_stat_from(stat_key, base_value)` asks
`UpgradeManager` for modifiers matching `stat_key` and folds them into the base
value. Covered by `tests/unit/test_stats_component.gd` (13 tests), and end to end
by `test_a_damage_upgrade_reaches_a_hitscan_shot`, which is the one that proves a
purchased upgrade survives all the way to a fired shot.
