---
tags: [mayhem]
estado: guia
actualizado: 2026-10-09
---

# Addons

Vendored under `addons/` and committed to the repo, so a fresh clone runs without setup.

| Addon | Status | Purpose |
|---|---|---|
| **GUT** 9.7.1 | Installed, enabled | Unit testing, see [TESTING.md](TESTING.md). Carries a local patch |
| **Beehave** 2.9.2 | Installed, enabled | Behavior trees for every enemy archetype. Carries a local patch |
| **MAYHEM Tools** | Ours, enabled | Arena editor + balance editor dock, see [`addons/mayhem_tools/README.md`](../addons/mayhem_tools/README.md) |
| **DebugDraw3D** | Installed (no plugin to enable) | Runtime hitbox / projectile / AI path visualization |
| **Phantom Camera** 0.11.0.3 | **Vendored, not enabled, not used** | — |

## Phantom Camera - on disk, unused

It was vendored (`79a2b4e`) for camera kick, but kick shipped without it:
`CameraRecoilComponent` drives a `CameraRig` node between the head pivot and the camera, and the
dash punch and landing spring were built the same way. Nothing in `scripts/` or `scenes/`
references it, the plugin is not in `[editor_plugins]`, and the export filter already keeps it
out of builds (see [EXPORT.md](EXPORT.md)).

Either enable it for a concrete need or delete `addons/phantom_camera/` (~1.9 MB). Leaving it
vendored and unused only means one more addon to keep in step with the engine version.

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

Behavior trees are referenced from `EnemyData.behavior_tree` as
a `PackedScene`, so an archetype's AI is swappable from data. The project also carries a Beehave
script template at `script_templates/BeehaveNode/default.gd`.

## Adding a new addon

Do not. Section 11 of the design brief ([DISENO.md](DISENO.md#11-addons)): propose it with a
justification first.

## Local patch to Beehave

`addons/beehave/debug/debugger_messages.gd` carries a one-line local patch.

Upstream's `can_send_message()` gates debugger traffic on `OS.has_feature("editor")` alone,
which is true whenever the editor binary runs - including headless CI, GUT runs and
`--headless` playtests, where no debugger is attached. Every registered behavior tree then
pushed an `ERROR: Can't send message. No active debugger`, once per enemy spawned.

The patch adds `EngineDebugger.is_active()` to that check. **Re-apply it after any Beehave
update**; the file is marked with a `LOCAL PATCH` comment.
