# Phase 3 - Enemies and waves

**Exit criteria (from `CLAUDE.md` 7):** 10 waves playable end to end, win and lose states
functional. The systems are in place and the loop runs unattended in a headless boot; the
"playable" half is a judgement made at the controls.

## Done

- **One enemy scene, five archetypes.** `scenes/enemies/enemy.tscn` is shared by every
  archetype; `EnemyData` supplies silhouette, stats, audio, rewards and behavior tree. That
  keeps composition data-driven and means one pool serves all enemies.
- **Enemy actor** (`scripts/actors/enemy.gd`) - navigation, hit reaction, stagger, death,
  pooling. Hit reaction is a gunplay-feel requirement, not an AI one: every hit flashes the
  emission, knocks back scaled by mass, and staggers for a window scaled by
  `stagger_resistance`. Being staggered fails the behavior tree's attack branch, so sustained
  fire interrupts wind-ups.
- **Beehave trees** for all five archetypes, built from a shared vocabulary of leaves in
  `scripts/ai/`:
  - **Rusher** - closes and hits. Fast, fragile, short tell. Forces movement.
  - **Ranger** - holds 14 m, fires a slow readable bolt. Punishes standing still in the open.
  - **Elite** - 420 HP, 0.85 stagger resistance, 1.65 s wind-up on a 34-damage slam. Wave
    punctuation.
  - **Healer** - never attacks, flees to 18 m, pulses healing to wounded allies in 9 m. Its
    action fails when nobody needs healing, so it repositions instead of idling.
  - **Summoner** - spawns rushers on a 7 s cycle from 16 m. Punishes slow clears.
- **Telegraphing is one reusable node.** `ActionTelegraph` owns the wind-up for every
  archetype - visual (emission ramp) and audio (per-archetype pitched tell), duration scaled
  from `attack_windup`. It is the single most important AI quality bar, so it is not
  reimplemented per tree. Melee damage re-checks range on landing: dodging a telegraphed
  attack actually works.
- **Spawn doors** (`scripts/systems/spawn_door.gd`) - seven placed around the arena perimeter
  and up on the mid platforms, so no single camping spot covers all of them. Each lights up
  and sounds off for 1.2 s **before** anything comes out; the wave manager awaits that tell
  once per spawn group.
- **Navigation** - `NavigationRegion3D` baked at runtime from the arena's static colliders,
  because the grey-box layout is still changing every playtest. Enemies fall back to
  straight-line steering when no nav map is available, which is also the path flying variants
  will use.
- **WaveManager** - real implementation. Wave clear requires alive == 0 **and** pending == 0,
  which covers the edge cases named in section 9: enemies killed by hazards, and summoned adds
  outliving their summoner. A generation counter kills in-flight spawn coroutines on reset, so
  a restart cannot leak the previous run's enemies into the new one.
- **10 waves** authored as `.tres` (`data/waves/`). Elite waves at 5 and 10. The curve
  introduces rushers, then rangers, then healers, then summoners, and rises from 4 to 18
  enemies.
- **Match flow** - `MatchDirector` runs the session and resolves it into victory (score
  submitted to the local leaderboard) or game over. `MatchOverlay` shows wave banners, a live
  remaining count, and the end screens. Restart reloads the scene rather than unwinding state,
  to hold the under-2-seconds-to-shooting bar.

## Deviations, flagged

1. **Enemy scenes are one scene, not five.** `CLAUDE.md` 4.1 implies a scene per enemy; a
   single data-driven scene keeps pooling simple and archetypes fully data-authored. Silhouette
   differences come from `EnemyData.mesh` (capsule / prism / box / sphere / cylinder).
2. **The healer's tether is not built.** The spec asks for a visible beam to whoever it is
   healing so it reads as a priority target. Right now it is identifiable by silhouette,
   colour and pulse audio only. This is a real gap and belongs in the Phase 5 VFX pass.
3. **The Elite has no area denial.** It is a high-health, high-damage, heavily telegraphed
   melee unit. Area denial needs a ground-hazard mechanic that does not exist yet.
4. **Between-wave gap is a plain 8 s timer.** Phase 4 replaces it with the shop phase.
5. **Local patch to Beehave** - `addons/beehave/debug/debugger_messages.gd`. Upstream gates
   debugger messages on "is an editor build" alone, so running the editor binary headlessly
   (CI, GUT, `--headless` playtests) pushed an error for every tree registered. The patch also
   requires `EngineDebugger.is_active()`. Re-apply after any Beehave update.

## Testing

89 tests. New coverage: wave clear detection with hazard kills and summoned adds, malformed
spawn groups completing rather than hanging, door telegraphing order, reset abandoning
in-flight spawns, and content guards over all five archetypes and all ten waves.

One test caught a wrong assumption of mine rather than a bug: par times do not increase
monotonically, because elite waves are deliberately slower than the normal wave that follows.
The test now checks the curve within normal waves and that elite waves get more time than the
wave before them.

## Next

1. Playtest the full 10-wave run. Balance is untuned: enemy counts, health and rewards are
   first-pass guesses.
2. Phase 4: economy, shop, remaining weapons and utilities.
