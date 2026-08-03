# Testing

GUT 9.7.1, vendored at `addons/gut/`. Tests live in `tests/` and mirror `scripts/`.

## Running

**In the editor:** the GUT panel at the bottom of the editor, once the plugin is enabled.

**Headless (what CI runs):**

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gexit
```

Configuration lives in `.gutconfig.json` (test dirs, `test_` prefix, exit code on failure).
CI runs the same command on every PR - see `.github/workflows/tests.yml`.

## What to test

Pure logic, not rendering. In priority order (section 9 of `CLAUDE.md`):

1. **`StatModifier` aggregation** - order, stacking limits. Highest priority: it breaks balance
   silently. Covered by `tests/unit/test_stat_modifier.gd`.
2. **Economy** - kill rewards, speed-bonus tiering, no-damage bonus, purchase validation.
   Partially covered by `tests/unit/test_economy_config.gd`; purchase validation lands with the
   shop in Phase 4.
3. **Damage** - falloff curve, headshot multiplier, damage reduction stacking.
   Covered by `tests/unit/test_weapon_data.gd`.
4. **Recoil** - pattern index advancement, reset timing, determinism.
   Offset/loop/determinism covered by `tests/unit/test_recoil_pattern.gd`; index advancement and
   `reset_time` land with `WeaponComponent` in Phase 1.
5. **Wave** - spawn group scheduling, clear detection edge cases (enemy dies to a hazard,
   summoned adds outliving their summoner). Phase 3.
6. **Ammo** - reserve clamping, reload with a partial magazine, pickup overflow. Phase 1.

## Conventions

- One test script per script under test, named `test_<script_name>.gd`.
- `extends GutTest`.
- Test names read as sentences: `test_add_applies_before_multiply_regardless_of_list_order`.
- Assert with a message whenever the failure would be ambiguous.
- Anything touching an autoload must reset it (`UpgradeManager.reset()`) so tests stay order
  independent.
