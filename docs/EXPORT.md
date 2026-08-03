# Export settings

`export_presets.cfg` is gitignored (it can carry local paths and keystore info), so the export
configuration is documented here. Recreate it in Project > Export on a fresh clone.

## Presets

### 1. `Windows Dev`
- Platform: Windows Desktop, x86_64
- Export path: `builds/dev/mayhem.exe`
- **Custom feature tag: `dev`**
- Debug: enabled (export with debug)
- Binary format: embed PCK

### 2. `Windows Release`
- Platform: Windows Desktop, x86_64
- Export path: `builds/release/mayhem.exe`
- **Custom feature tag: `release`**
- Debug: disabled
- Binary format: embed PCK
- Resources: export all resources except `res://tests/*` (exclude filter: `tests/*`)

### 3. `Linux Release` (nice-to-have)
- Platform: Linux, x86_64
- Export path: `builds/release/mayhem.x86_64`
- Custom feature tag: `release`
- Same exclude filters as the Windows release preset.

## Feature tags

`dev` and `release` are set per preset under *Feature Tags* in the export dialog. Guard all
development-only code with them so it is stripped from shipping builds:

```gdscript
if OS.has_feature("dev"):
    ...  # Debug Draw calls, cheat keys, the recoil pattern visualizer
```

The editor itself always reports `editor` and `debug`, so `dev` behavior works while testing
in-editor if you check `OS.has_feature("dev") or OS.has_feature("editor")`.

## Checklist before tagging a build

1. `godot --headless -s addons/gut/gut_cmdln.gd -gexit` passes.
2. Export templates match the editor version exactly (4.7-stable).
3. Launch the release build and confirm no Debug Draw geometry is visible.
4. Confirm 60 FPS with a full elite wave on screen (section 10 of `CLAUDE.md`).
