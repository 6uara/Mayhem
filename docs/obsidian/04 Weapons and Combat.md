---
tags: [mayhem, weapons, combat]
---

# Weapons and Combat

## WeaponData

`scripts/resources/weapon_data.gd`. Pure balance schema — no mesh field
originally (see [[#Viewmodel]] for why one exists now). Groups: Damage
(`damage`, `headshot_multiplier`, falloff start/end/min), Firing (`fire_rate`,
`projectiles_per_shot` — shotgun > 1, `projectile_speed`), Ammo (`magazine_size`,
`reserve_ammo_max`, `reload_time`), Recoil and spread (`recoil_pattern`,
`spread_hipfire`/`spread_ads`, moving/airborne multipliers), ADS
(`ads_fov`, `ads_transition_time`, `ads_move_speed_multiplier`).

`get_damage(distance, is_headshot)` applies falloff then headshot multiplier —
the one place damage math actually happens; callers never compute it inline.

Instances: `data/weapons/pistol.tres`, `rifle_ak.tres`, `shotgun.tres`, `smg.tres`.
The player starts with only the pistol (`WeaponHolder._ready()` — `_owned.push_back(_weapons[0])`,
first child by convention); the other three are shop purchases.

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

`scripts/components/weapon_holder.gd`. Owns switching (`select_slot`, `cycle`,
`start_swap` — firing is blocked for `swap_time` during a swap), ownership
(`acquire(weapon_id)`, `owns(weapon_id)`), and fan-out (`add_reserve_ammo_fraction`
— what an ammo pickup grants, applied to every *owned* weapon at once).

## Projectile / hitbox / health

- `scripts/systems/projectile.gd` — pooled, `launch(origin, direction, data, shooter, damage)`.
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
value. **Zero test coverage** despite being the path every purchased upgrade in
the game flows through — see [[12 Known Issues and Gaps]].
