# Addons

Vendored under `addons/` and committed to the repo, so a fresh clone runs without setup.

| Addon | Status | Purpose |
|---|---|---|
| **GUT** 9.7.1 | Installed, enabled | Unit testing, see `docs/TESTING.md` |
| **Beehave** 2.9.2 | Installed, enabled | Behavior trees for enemy AI (Phase 3) |
| **DebugDraw3D** | Installed (no plugin to enable) | Runtime hitbox / projectile / AI path visualization |
| **Phantom Camera** | **Not installed** | Camera rig, shake, recoil kick, FOV transitions |

## Phantom Camera - still not installed

Camera kick shipped in Phase 1 without it: `CameraRecoilComponent` drives a `CameraRig` node
between the head pivot and the camera. Phantom Camera can take that node over whenever it is
installed - the aim-offset half of recoil is deliberately independent of it. Take the release
tagged for Godot 4.7: https://github.com/ramokz/phantom-camera

After installing: enable it in Project > Project Settings > Plugins, then commit
`addons/phantom_camera/` together with the updated `[editor_plugins]` line in `project.godot`.

## DebugDraw3D

This is the pure-GDScript in-scene node (`class_name DebugDraw3D`), not the GDExtension build -
no plugin to enable and no platform binaries to keep in sync with the engine version. Add a
`DebugDraw3D` node to a scene and call its draw methods.

Debug draw must not reach release builds. Use the `dev` feature tag (see `docs/EXPORT.md`) and
guard every call:

```gdscript
if OS.has_feature("dev"):
    _debug_draw.draw_sphere(position, radius, Color.RED)
```

## Beehave

Enabled but unused until Phase 3. Behavior trees are referenced from `EnemyData.behavior_tree` as
a `PackedScene`, so an archetype's AI is swappable from data. The project also carries a Beehave
script template at `script_templates/BeehaveNode/default.gd`.

## Adding a new addon

Do not. Section 11 of `CLAUDE.md`: propose it with a justification first.

## Local patch to Beehave

`addons/beehave/debug/debugger_messages.gd` carries a one-line local patch.

Upstream's `can_send_message()` gates debugger traffic on `OS.has_feature("editor")` alone,
which is true whenever the editor binary runs - including headless CI, GUT runs and
`--headless` playtests, where no debugger is attached. Every registered behavior tree then
pushed an `ERROR: Can't send message. No active debugger`, once per enemy spawned.

The patch adds `EngineDebugger.is_active()` to that check. **Re-apply it after any Beehave
update**; the file is marked with a `LOCAL PATCH` comment.
