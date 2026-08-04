# Phase 4 - Economy, shop and content

**Exit criteria (from `CLAUDE.md` 7):** a full run has meaningful purchase decisions;
first balance pass done. The systems are complete and 130 tests pass; whether the decisions
*feel* meaningful is a playtest judgement.

## Done

- **All four weapons.** Rifle (Phase 1) joined by:
  - **Shotgun** - 9 pellets, heavy falloff (full damage to 8 m, 25% past 22 m), 6 rounds,
    slow reload. Rewards closing distance, which is what makes dash and grapple offensive
    tools rather than escape buttons.
  - **SMG** - 15 rounds/sec, 9 damage, the smallest moving/airborne spread penalties in the
    game (1.25x / 1.5x versus the rifle's 2.2x / 3.5x). The mobility weapon, by numbers.
  - **Pistol** - the starting weapon. Accurate, low DPS, 150 reserve.
  Each has its own authored recoil pattern; the shotgun's is a single hard kick that fully
  recovers (nothing to learn), the SMG's is a small forgiving drift, the pistol's is crisp
  and near-vertical.
- **WeaponHolder** - every weapon exists on the player from the start; owning one enables it.
  That makes per-weapon ammo persist across switches and shop visits with no save/restore
  logic. Swapping takes 0.35 s and drops the trigger, so a held fire input does not carry
  across the swap.
- **Three utilities**, all pooled and thrown on a stepped arc rather than simulated:
  - **Stun grenade** - 1.1 s fuse, stuns everything in 6 m. Reuses the stagger timer, so a
    stunned enemy also fails its behavior tree's attack branch rather than merely freezing.
  - **Barrier** - a solid wall for 7 s. Buys a reload, cuts a lane, blocks a ranger.
  - **Slow field** - 45% move speed inside 6.5 m for 6 s, applied and lifted as enemies
    enter and leave.
- **Ammo pickups** - six of them, on the exposed perches, the open centre and the far
  corners, never next to cover. This is Phase 1 debt paid: limited reserve only creates
  pressure if refills sit somewhere risky (CLAUDE.md 5.1). Each hums audibly from 26 m,
  glows, bobs and respawns after 20 s, and refuses to be collected when the player is full.
- **18 upgrades** across all three categories, every one expressed purely as `StatModifier`s.
  Includes one temporary upgrade (Adrenaline, 90 s) to exercise that path.
- **Shop** - `ShopCatalog` holds everything buyable and every price in one resource. Each
  visit rolls 6 offers with one guaranteed per upgrade category, so a run is never railroaded
  by bad luck. Sold-out entries (maxed upgrades, owned weapons, full utility slots) are
  filtered before the player sees them. Validation lives in `Shop` and `EconomyManager`, never
  in the UI, so a broken button cannot hand out free upgrades.
- **Wave-complete breakdown** - kills, completion, speed bonus and no-damage bonus shown as
  four separate lines, with the missed ones labelled *why* they were missed ("too slow",
  "took damage"). That legibility is the point (CLAUDE.md 5.5).
- **Shop phase** replaces the Phase 3 placeholder timer: 25 s, pauses the game, and is
  skippable with one button - banking the speed bonus early is a real decision.
- **Leaderboard** on the victory screen, top five with score, time and wave reached.

## Wiring that was missing and is now connected

Two upgrade categories were authored against stats nothing read:
- `air_control` was a plain exported constant in `MovementComponent`; it now goes through
  `StatsComponent`.
- `max_health` and `damage_taken_multiplier` live on `HealthComponent`, which knows nothing
  about `UpgradeManager`. `Player` now bridges them, and max health preserves the current
  health *fraction*, so buying Plating mid-run tops the player up proportionally rather than
  handing out a free full heal.

## Deviations, flagged

1. **Weapon viewmodels are all the same placeholder box.** Four weapons, one grey model.
   Distinct silhouettes are an art-pass job (Phase 5), but until then the viewmodel is not
   carrying any of the identity load the HUD label is.
2. **Weapon audio is shared.** All four use the rifle's fire, reload and empty samples.
   Section 6 wants each weapon distinct; that needs real samples, not more synthesis.
3. **Shop offers are random within the catalogue.** There is no rarity, no scaling by wave,
   no re-roll. Those are balance tools worth having, but they are guesses until the first
   playtest says what the economy actually feels like.
4. **Prices and payouts are first-pass.** The whole balance surface - kill rewards, bonus
   sizes, upgrade costs, weapon prices - is one `EconomyConfig` plus one `ShopCatalog`, so
   tuning is a data edit. Nothing has been tuned against real play yet.

## Testing

130 tests. New: purchase validation (insufficient funds, exact change, max stacks, negative
price, refused purchases charging nothing), wave payout itemisation, weapon ownership and
per-weapon ammo persistence across switches, utility charge limits and cooldowns, shop offer
filtering, and the between-wave loop (wave clear opens the shop with the breakdown, closing it
starts the next wave, the final wave resolves the match instead).

## Next

Phase 5 is art, VFX, audio and polish. Before that, the honest priority is a playtest: the
last three phases have all shipped systems whose exit criteria are judgements at the controls,
and the balance surface now exists to respond with.
