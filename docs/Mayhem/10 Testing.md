---
tags: [mayhem, testing]
---

# Testing

GUT 9.7.1, vendored at `addons/gut/`. Tests live in `tests/`, mirroring
`scripts/`. See `docs/TESTING.md` in the repo root for the runner commands
(editor panel vs. headless CLI); this note is about coverage, not mechanics.

## Coverage map

**24 test files** as of this writing:

```
tests/unit/
  test_dash_charges.gd          test_economy_config.gd
  test_economy_manager.gd       test_enemy_data.gd
  test_recoil_pattern.gd        test_scene_wiring.gd
  test_spec_conformance.gd      test_stat_modifier.gd
  test_theme_tokens.gd          test_wave_content.gd
  test_wave_manager.gd          test_weapon_component.gd
  test_weapon_data.gd

tests/integration/
  test_arena_elements.gd        test_arena_navigation.gd
  test_enemy_behavior.gd        test_enemy_obstacles.gd
  test_hud.gd                   test_hud_layout.gd
  test_match_flow.gd            test_navigation_connectivity.gd
  test_pause_and_settings.gd    test_player_movement.gd
  test_shop_and_loadout.gd
```

## Notable individual tests (not obvious from the filename)

- `test_spec_conformance.gd` — cross-checks that code matches stated design
  intent rather than testing behavior in isolation: e.g.
  `test_the_elite_shares_the_hazard_accent` asserts `elite.body_color.g` tracks
  `Tokens.HAZARD.g`, and `test_shop_timer_matches_the_spec` asserts
  `ShopScreen.duration == Tokens.SHOP_TIMER`. This file is where "the docs and
  the code agree" gets enforced mechanically.
- `test_player_movement.gd` — added when the movement-feel pass landed (gravity
  asymmetry, jump cut, coyote time, buffer, `CameraFeelComponent`). Notably
  includes `test_view_bob_can_never_move_the_aim`, which drives the cosmetic
  `ViewBob` node to extreme transforms and asserts the aim transform is
  unaffected — this is the test that makes the aim-safety architectural claim
  in [[03 Player and Movement]] a checked fact, not just a comment.
- `test_hud_layout.gd` — measures actual rendered `Rect2`s of every HUD cluster
  against the *live* viewport (not an assumed 1920×1080) and asserts no two
  intersect. Caught a real overlap between the weapon cluster and the subtitle
  box during the visual-identity pass.
- `test_pause_and_settings.gd` — includes
  `test_every_schema_key_is_a_real_setting`, which walks `SettingsScreen.SCHEMA`
  and asserts every `key` exists in `SettingsManager.DEFAULTS`. This is the test
  that makes the options screen's schema-driven design (see
  [[07 UI and HUD#Options screen]]) actually safe to extend.
- `test_scene_wiring.gd::test_no_two_weapons_share_a_voice` — asserts no two
  weapons' `fire_sound`/`reload_sound`/`empty_sound` are the same `AudioStream`.
  Guards against exactly the regression that motivated per-weapon audio in the
  first place (all four weapons originally shared one rifle sample).
- `test_wave_content.gd` — validates every authored `.tres` in `data/waves/`:
  elite-wave cadence, non-decreasing difficulty, rising par times. Catches a
  broken wave file before a playtest does.

## Formerly-flaky test (root-caused, fixed)

`test_navigation_connectivity.gd::test_the_map_has_a_navmesh_at_all` used to
fail intermittently. Root cause: the arena was instantiated once in
`before_all()`, so `NavigationServer3D` only ever picked up the region
correctly when some *earlier* test in the run had already put an arena in the
tree first — passing by accident, not by correctness, and failing every time
this file ran in isolation. Fixed by building the arena fresh per test
(`before_each()`) and polling `NavigationServer3D.map_get_regions(_map)` /
`map_force_update()` for up to `MAX_SYNC_FRAMES` instead of waiting a fixed
frame count — see the docstring on `before_each()` in the test file itself.
Verified stable across multiple consecutive full-suite runs (backlog tanda
G6). If this ever flakes again it is a *new* bug, not a recurrence of this one
— don't reach for "known flaky, rerun it" as the reflex.

## What's explicitly *not* covered

`GrappleComponent` and `StatsComponent` have zero test files despite being real
gameplay surfaces (`StatsComponent` is the read path every purchased upgrade in
the game flows through). See [[12 Known Issues and Gaps]] for the current
priority list.
