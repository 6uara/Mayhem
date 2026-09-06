---
tags: [mayhem, index]
---

# MAYHEM — Technical Documentation

Single-player FPS arena shooter. Godot 4.7, GDScript, Jolt physics, Forward+.

This vault documents the **current state of the codebase**, not its history — for
the phase-by-phase build log see `docs/PHASE_0.md` through `docs/PHASE_5.md` in
the repo root's `docs/` folder, which this vault does not replace.

## Map

- [[01 Architecture]] — the shape of the codebase: layers, composition, data-driven design
- [[02 Autoloads]] — the global singletons and what each owns
- [[03 Player and Movement]] — first-person controller, movement feel, camera
- [[04 Weapons and Combat]] — WeaponData/WeaponComponent, projectiles, recoil, health
- [[05 Enemies and AI]] — archetypes, Beehave behavior trees, navigation
- [[06 Waves and Economy]] — spawning, the shop, upgrades, match flow
- [[07 UI and HUD]] — HUD, telegraphs, pause/options, theme system
- [[08 VFX and Shaders]] — the custom shaders and what drives them
- [[09 Design Tokens and Color Law]] — the single source of truth for color/timing/layout
- [[10 Testing]] — GUT setup, coverage map, known flake
- [[11 Asset Pipeline]] — model/audio import tooling
- [[12 Known Issues and Gaps]] — what's missing or fragile, as of this writing

## Orientation, fast

- **Where does gameplay logic live?** `scripts/components/` (composable pieces
  attached to actors) and `scripts/systems/` (standalone world objects). Actors
  (`scripts/actors/`) are thin: `Player` and `Enemy` mostly delegate to components.
- **Where do balance numbers live?** `data/` — every weapon, enemy archetype, wave,
  upgrade and utility is a `Resource` (`.tres`), not a hardcoded constant. Designers
  edit `.tres` files, not code.
- **How do systems talk to each other?** `EventBus` (autoload). No node holds a
  direct reference to another system's internals across a boundary — see
  [[01 Architecture#EventBus]].
- **Where is "the look" defined?** `Tokens` (autoload, `scripts/autoload/theme_tokens.gd`).
  Every color, timing and layout constant in the game traces back to it. See
  [[09 Design Tokens and Color Law]].
- **What actually enforces any of this?** Tests. `tests/unit/test_spec_conformance.gd`
  and `tests/unit/test_theme_tokens.gd` specifically exist to catch drift between
  code and the design intent described in this vault.
