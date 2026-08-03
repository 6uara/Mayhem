# Addons

Vendored under `addons/` and committed to the repo, so a fresh clone runs without setup.

| Addon | Status | Purpose |
|---|---|---|
| **GUT** 9.7.1 | Installed (`addons/gut`) | Unit testing, see `docs/TESTING.md` |
| **Phantom Camera** | **Not installed** | Camera rig, shake, recoil kick, FOV transitions |
| **Beehave** | **Not installed** | Behavior trees for enemy AI |
| **Debug Draw 3D** | **Not installed** | Runtime hitbox / projectile / AI path visualization |

## Why the other three are not installed yet

Phantom Camera and Beehave are GDScript addons but pin to specific Godot minor versions;
Debug Draw 3D is a **GDExtension** and ships platform binaries that must match 4.7 exactly.
Installing the wrong build silently breaks the editor rather than failing loudly, so pick the
release tagged for Godot 4.7 from the asset library or the project's GitHub releases:

- Phantom Camera - https://github.com/ramokz/phantom-camera (needed for Phase 1: camera kick)
- Beehave - https://github.com/bitbrain/beehave (needed for Phase 3: enemy AI)
- Debug Draw 3D - https://github.com/DmitriySalnikov/godot_debug_draw_3d (dev-only)

Install order matters only in that **Phantom Camera is a Phase 1 blocker** - it owns camera
kick, which is part of the gunplay pillar. The other two can wait for their phase.

After installing each addon: enable it in Project > Project Settings > Plugins, commit
`addons/<name>/` and the updated `[editor_plugins]` block in `project.godot`.

## Debug Draw and release builds

Debug Draw calls must compile out of release builds. Use the `dev` feature tag (see
`docs/EXPORT.md`) and guard every call:

```gdscript
if OS.has_feature("dev"):
    DebugDraw3D.draw_sphere(position, radius, Color.RED)
```

## Adding a new addon

Do not. Section 11 of `CLAUDE.md`: propose it with a justification first.
