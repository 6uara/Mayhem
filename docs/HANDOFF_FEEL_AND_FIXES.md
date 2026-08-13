---
tags: [mayhem, handoff, feel, bugs]
---

# Handoff — Feel pass and code findings

Written from a code review session with no Godot binary available, so **nothing
here was run**. Every claim is either measured from the source/data (marked
*medido*) or reasoned from it (marked *hipótesis*). Treat the *hipótesis* items
as leads to confirm in-game, not as facts.

Baseline: `develop` @ `d66c67a`. Findings re-verified against that commit.

---

## 0. Read this first

The reported symptom that started this: **"a veces las balas atraviesan al
enemigo"**. Four separate causes were found, and they compound. Fixing only one
will not make the symptom disappear.

Ruled out (do not re-investigate, all checked):

- Projectile tunnelling — `Projectile._physics_process()` raycasts the swept
  segment each frame (`_cast(from, to)`), so speed cannot skip a target.
- Enemy body blocking its own hitbox — body is layer `ENEMY` (4), the
  projectile masks `WORLD | HITBOX` (33). They do not interact.
- `ObjectPool` recycling an in-flight projectile — `acquire()` instantiates a
  new node when the free list is empty, never steals an active one.
- Missing hit feedback — hitmarker (`reticle.gd`), damage numbers
  (`damage_number_spawner.gd`) and hitstop are all wired to
  `EventBus.damage_dealt`. When a hit lands, the player is told.

So when it feels like a pass-through, the hit genuinely did not register.

---

## 1. Enemy hitboxes are narrower than their silhouettes — *medido*

**Priority: highest. This is the direct cause and the cheapest fix.**

`EnemyData.hitbox_radius` defaults to `0.0`, which means "fall back to
`collision_radius`" — the navmesh number. The field's own docstring warns
against exactly this:

> *"a model wider than its capsule is a model whose outer half is quietly
> bulletproof"*

That fix was applied to Rusher and Elite, but **never to Ranger, Healer or
Summoner**. Measured, per archetype (mesh vs. effective hitbox radius):

| Arquetipo | Mesh                                  | Radio efectivo | Veredicto |
|-----------|---------------------------------------|----------------|-----------|
| Summoner  | Cone, `bottom_radius = 0.9`           | **0.55**       | **35cm por lado a prueba de balas en la base** |
| Ranger    | Prism, `size.x = 0.75` (semi = 0.375) | **0.34**       | ~3.5cm por lado sin registro |
| Healer    | Capsule, `radius = 0.34`              | 0.36           | OK (hitbox ≥ mesh) |
| Elite     | Capsule, `radius = 0.75`              | 1.00           | OK, generoso |
| Rusher    | `spiderbot.res`                       | 0.60           | OK, generoso |

El Summoner es el caso grave: la parte más ancha y más fácil de acertar es
justamente la que no registra.

### Qué hacer

1. `data/enemies/summoner.tres` → añadir `hitbox_radius = 0.9`.
2. `data/enemies/ranger.tres` → añadir `hitbox_radius = 0.40`.
3. Healer/Elite/Rusher: dejar como están.

Sizing lives in `Enemy._apply_collision()` (`scripts/actors/enemy.gd:656`) and
reads through `get_hitbox_radius()` (`:241`) — no code change needed, only data.

### Y el test que falta

There is **no test asserting the hitbox covers the silhouette**. Add one to
`tests/integration/` that, for every `data/enemies/*.tres`, derives the mesh's
widest radius from its `AABB` and asserts `get_hitbox_radius() >= that`.

This matters beyond today: every mesh in `data/enemies/` is still a placeholder
primitive. When the real enemy models land (the XL modelling task), **all of
these numbers must be re-derived**, and without a test the same bug returns
silently. Wire this test before the models, not after.

---

## 2. Lead requirement makes fast enemies feel like pass-throughs — *medido*

Projectiles are 140–180 m/s (`data/weapons/*.tres`, `projectile_speed`). The
Rusher moves at 7.2 m/s.

At 25 m: flight time `25 / 170 = 0.147 s`, in which a strafing Rusher travels
**1.06 m**. Its hitbox diameter is 1.2 m — so the player must lead by almost a
full body width. That is physically consistent, but MAYHEM's stated gunplay
references (CoD / Battlefield / The Finals) are hitscan, so it reads as the
shot passing through.

**This is a design decision, not a bug — it needs a human call.** Raising
`projectile_speed` to ~300–400 m/s roughly halves the lead while keeping the
tracer visible. Do not change it silently; play it both ways first. If changed,
re-check `tests/integration/test_shooting_and_hitboxes.gd`.

---

## 3. Player weapon fire can be silently dropped under load — *medido*

`AudioPool._find_free_3d()` (`scripts/autoload/audio_pool.gd:113`) scans 48
players for a free one and, failing that, **drops the sound**. There is no
priority and no voice stealing: first come, first served.

During an elite wave (27 enemies) plus an SMG at 15 rounds/sec plus per-hit
impacts plus shell casings, the pool can exhaust — and the sound dropped may be
**the player's own gunshot**, which directly undermines pillar #1 ("if shooting
doesn't feel good, nothing else matters"). A shot with no sound *and* (per §1)
no hit registration is exactly the reported symptom.

Note `tools/configure_audio_mix.gd` set a bus *gain* hierarchy described as
"VO/Weapons highest priority down to UI" — but that is loudness, not voice
allocation. The intent exists; the pool does not implement it.

### Qué hacer

Give `play_3d`/`play_2d` a priority argument and let a high-priority sound
steal the oldest or most distant low-priority voice instead of being dropped.
Weapon fire and VO must never lose to an enemy footstep.

*Hipótesis*: confirm by watching for the existing
`push_warning("AudioPool: 3D pool exhausted…")` in the console during wave 10.
If it never fires in practice, deprioritise this.

---

## 4. The dash has no camera reaction at all — *medido*

`CameraFeelComponent` owns step bob, strafe lean and the landing punch. Nothing
in it — or anywhere else — reacts to a dash. Verified: no listener on
`EventBus.dash_used` in `camera_feel_component.gd`, `camera_recoil_component.gd`
or `player.gd`.

The only response is the speed-driven FOV in `Player._tick_speed_fov()`, which
lerps at `SPEED_FOV_BLEND = 5.0` — smooth by design, so it never reads as a
punch.

A dash is 0.16 s at 16 m/s: the most explosive move in the kit, and the camera
does not acknowledge it. **This is the biggest feel gap in the movement side and
the best effort-to-payoff item in this document.**

### Qué hacer

Add a dash reaction to `CameraFeelComponent` (it already owns `view_node` and
already has the damped-spring pattern from `_tick_landing()` to copy):

- A short FOV punch out and back, separate from the smooth speed FOV.
- Optionally a small positional kick opposite the dash direction.
- **Must respect `accessibility/screenshake_enabled`**, same as the landing
  punch does (`_on_landed()` checks it) — this is a hard rule in this codebase.

---

## 5. Robustness findings (not feel, but real) — *medido*

- **`SaveManager.load_leaderboard()`** (`scripts/autoload/save_manager.gd`)
  accepts any `Dictionary` from the JSON without validating its fields. A
  malformed or hand-edited `user://leaderboard.json` containing e.g. `[{}]`
  loads fine, then crashes later in `get_best_score()` / `submit_score()`'s sort
  on the missing `"score"` key. It is a user-writable file; validate the keys on
  load and skip bad entries.

- **`EconomyManager.award_wave_bonuses(wave, …)`** dereferences `wave.par_time`
  and `wave.completion_bonus` with no null guard.

- **Only enemies are prewarmed.** `ObjectPool.prewarm()` is called once, from
  `enemy_spawner.gd:24`. Projectiles, impact effects, damage numbers and shells
  are never prewarmed, so each type instantiates on its first use despite the
  pool's own docstring ("so the first shot never hitches"). One-time hitch per
  type; cheap to fix by prewarming them where the game scene loads.

---

## Suggested order

1. §1 hitbox data (XS) — direct cause, two numbers.
2. §1 silhouette test (S) — locks it in before the real models land.
3. §4 dash camera reaction (S) — biggest movement feel win.
4. §5 robustness (S) — small, unrelated to feel, easy to batch.
5. §3 audio priority (M) — confirm it actually happens first.
6. §2 projectile speed (S) — needs a human playing it both ways.

## Reminder

Run `gut` after each step. The two regression tests from the previous session
(`test_a_null_catalogue_entry_is_skipped_rather_than_crashing`,
`test_a_hint_dropped_by_a_full_queue_is_not_marked_seen`) got their first
green on 2026-08-13 (`Godot_v4.7.1-stable_win64_console.exe --headless`,
364/364 passing, 0 asserts failed) - both fixes are confirmed.
