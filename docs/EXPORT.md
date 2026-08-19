# Export settings

`export_presets.cfg` is gitignored (it can carry local paths and keystore info), so the export
configuration is documented here — copy the blocks below into a fresh `export_presets.cfg` at
the repo root on a new clone (or recreate them by hand in Project > Export; the values below are
what the editor would write).

**Verified real** (backlog tanda G1): both Windows presets actually export and the resulting
`.exe` boots, via
`godot --headless --export-debug "Windows Dev" builds/dev/mayhem.exe` /
`--export-release "Windows Release" builds/release/mayhem.exe`. The exclude filter was checked
against the real export log (`grep -c "Storing File: res://tests/"` on stdout — 74 hits for
Windows Dev, 0 for Windows Release), not assumed. Linux Release is configured identically but
**unverified** — no Linux export templates are installed in this environment; verify it once
they are.

**The widened exclude filter is verified too.** `Windows Release` was re-exported with it
(`--export-release`, Godot 4.7-stable, exit 0) and the export log checked per excluded tree:
`tests/`, `docs/`, `tools/`, `script_templates/`, `addons/gut/`, `addons/phantom_camera/`,
`addons/debug_draw/`, `builds/` and `LatestBuild/` each stored **0** files, while
`addons/beehave/` stored 119 — the AI trees still ship. Build size went 214 MB to 210 MB.

"Debug" vs "Release" is not a field stored on the preset itself — it's which export command you
run against it (`--export-debug` vs `--export-release`, or the corresponding buttons in the
Export dialog). Windows Dev is meant to always be exported with `--export-debug`; Windows
Release and Linux Release with `--export-release`.

## Presets

### 1. `Windows Dev`
- Platform: Windows Desktop, x86_64
- Export path: `builds/dev/mayhem.exe`
- **Custom feature tag: `dev`**
- Export with: `--export-debug`
- Binary format: embed PCK
- Resources: all (`export_filter="all_resources"`, no exclude filter) — the whole point of this
  preset is a build you can still debug and test against.

### 2. `Windows Release`
- Platform: Windows Desktop, x86_64
- Export path: `builds/release/mayhem.exe`
- **Custom feature tag: `release`**
- Export with: `--export-release`
- Binary format: embed PCK
- Resources: export all resources except the dev-only trees — see *Exclude filter* below.

### 3. `Linux Release` (nice-to-have, unverified — see above)
- Platform: Linux, x86_64
- Export path: `builds/release/mayhem.x86_64`
- Custom feature tag: `release`
- Export with: `--export-release`
- Same exclude filter as the Windows release preset.

## Exclude filter

Both release presets share one exclude filter. Every entry is a tree that exists only to
develop the game — none of it is reachable from a scene, an autoload, or a script at runtime,
which was checked by grepping `scripts/`, `scenes/`, `ui/`, `assets/` and `data/` for each path
before it was added here. Shipping it would hand a player the test suite, the design docs and
~5 MB of unused editor addons for nothing.

| Entry | Why it is not in a shipping build |
| --- | --- |
| `tests/*` | GUT test suite. |
| `docs/*` | Design docs, phase plans, the Obsidian vault. |
| `tools/*` | The Python asset generators (placeholder SFX and music). |
| `script_templates/*` | Editor-only new-script templates. |
| `addons/gut/*` | Test framework, editor-only (~2.9 MB). |
| `addons/phantom_camera/*` | Installed but unused — the only mention is a comment in `camera_recoil_component.gd` (~1.9 MB). |
| `addons/debug_draw/*` | Installed but unused; no call site anywhere (~235 KB). |
| `builds/*`, `LatestBuild/*` | Previous exports living inside the project directory. Belt and braces — `all_resources` should not pick up a `.exe` — but a build that packs an older build of itself is not a failure worth risking. |

`addons/beehave/*` is **not** excluded: five enemy AI trees under `scenes/enemies/ai/` depend on
it, and two of its scripts are autoloads (`BeehaveGlobalMetrics`, `BeehaveGlobalDebugger`).

If you install a new addon, decide which side of this list it lands on at install time and add a
row here — an addon nobody classified defaults to shipping.

## `export_presets.cfg`

Minimal reference — the fields above (`name`, `platform`, `custom_features`, `export_path`,
`exclude_filter`) are what actually matter; the rest is boilerplate the editor fills in the same
way for any Windows Desktop / Linux preset. Full file (including the boilerplate
`[preset.N.options]` blocks) lives in git history on the commit that landed this section if you
need to diff against it — this doc is the source of truth for the fields that are decisions,
not a byte-for-byte dump of a file that's gitignored specifically because most of it isn't one.

```ini
[preset.0]
name="Windows Dev"
platform="Windows Desktop"
custom_features="dev"
export_filter="all_resources"
exclude_filter=""
export_path="builds/dev/mayhem.exe"

[preset.1]
name="Windows Release"
platform="Windows Desktop"
custom_features="release"
export_filter="all_resources"
exclude_filter="tests/*,docs/*,tools/*,script_templates/*,addons/gut/*,addons/phantom_camera/*,addons/debug_draw/*,builds/*,LatestBuild/*"
export_path="builds/release/mayhem.exe"

[preset.2]
name="Linux Release"
platform="Linux"
custom_features="release"
export_filter="all_resources"
exclude_filter="tests/*,docs/*,tools/*,script_templates/*,addons/gut/*,addons/phantom_camera/*,addons/debug_draw/*,builds/*,LatestBuild/*"
export_path="builds/release/mayhem.x86_64"
```

## `layout_mode` en escenas de UI con raiz Control

**Toda escena cuya raiz sea un `Control` y que se instancie como hija de otra escena necesita
`layout_mode = 3` en esa raiz.** Sin eso anda en el editor y se rompe solo en el build
exportado: el panel entero aparece pegado a la esquina superior izquierda, cortado.

Por que. Los `.tscn` de este proyecto estan escritos a mano, y el editor de Godot siempre
escribe `layout_mode` en un Control - nosotros nunca lo pusimos. Al empaquetar la escena que
instancia, Godot calcula los overrides de la instancia comparandola con la escena base, y sin
`layout_mode` sintetiza `anchors_preset = 0`, que es `PRESET_TOP_LEFT`. Ese override pisa los
anchors de la base, la raiz instanciada queda en size `(0, 0)`, y un hijo anclado al 50% con
offsets `-260/-250` cae fuera de la esquina. Con `layout_mode = 3` el override sintetizado pasa
a ser `layout_mode = 1` (anchors) y los anchors sobreviven.

Afecta solo a raices `Control`. `hud.tscn`, `pause_menu.tscn`, `shop_screen.tscn`,
`match_overlay.tscn`, `loading_screen.tscn` y `scene_transition.tscn` tienen raiz `CanvasLayer`,
y `spectator_view.tscn` `Node3D`: sus hijos Control cuelgan del viewport y nunca dependieron de
esto. Las tres que si tenian raiz `Control` -`coop_panel`, `settings_screen`,
`leaderboard_panel`- son exactamente las tres que se rompian.

Medido en un build exportado real, fullscreen a 2560x1440: antes las tres raices reportaban
`size=(0,0)` con anchors `0.0/0.0`; despues, `size=(1920,1080)` con anchors `1.0/1.0` y los
paneles centrados.

> **`.godot/exported/` cachea las escenas ya convertidas a binario, y el cache se queda viejo.**
> Dos exports seguidos devolvieron el `.tscn` anterior aunque el archivo en disco ya estaba
> cambiado, lo que hace parecer que un arreglo no funciona. Al diagnosticar cualquier cosa que
> se vea distinta entre el editor y el build, borrar `.godot/exported/` antes de exportar y no
> sacar conclusiones de un export que no arranco de un cache limpio.

## Feature tags

`dev` and `release` are set per preset under *Feature Tags* in the export dialog. Guard all
development-only code with them so it is stripped from shipping builds:

```gdscript
if OS.has_feature("dev"):
    ...  # Debug Draw calls, cheat keys, the recoil pattern visualizer
```

The editor itself always reports `editor` and `debug`, so `dev` behavior works while testing
in-editor if you check `OS.has_feature("dev") or OS.has_feature("editor")` — see
`scripts/systems/recoil_visualizer.gd` for the one place in the codebase that does this today.

## Checklist before tagging a build

1. `godot --headless -s addons/gut/gut_cmdln.gd -gexit` passes.
2. Export templates match the editor version exactly (4.7-stable).
3. Export both Windows presets and confirm the log actually honours the exclude filter for
   Release. Capture the export stdout and check every excluded tree, not just `tests/`:
   `grep -cE "Storing File: res://(tests|docs|tools|script_templates|addons/(gut|phantom_camera|debug_draw))/"`
   — must be 0 for Release and nonzero for Dev. Do not trust a visual skim of the preset config
   alone.
4. Launch the release build and confirm no Debug Draw geometry is visible.
5. Confirm 60 FPS with a full elite wave on screen (section 10 of `CLAUDE.md`).
6. **En el build, no en el editor**: abrir Options, Best runs y Coop desde el menu, y Options
   desde la pausa. Los cuatro paneles tienen que quedar centrados. Es el unico sintoma de la
   trampa de `layout_mode` de mas arriba, y no se ve corriendo desde el editor.
