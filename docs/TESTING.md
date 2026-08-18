# Testing

GUT 9.7.1, vendored at `addons/gut/`. Tests live in `tests/` and mirror `scripts/`.

## Running

**Windows, todo de una:**

```powershell
pwsh tools/run_tests.ps1
```

El script busca el Godot instalado (`$env:GODOT` lo pisa), corre la suite headless y
devuelve el código de salida de GUT. Un script suelto o un test suelto:

```powershell
pwsh tools/run_tests.ps1 -Script res://tests/unit/test_economy_manager.gd
pwsh tools/run_tests.ps1 -Test test_kills_pay_into_the_wave_total
pwsh tools/run_tests.ps1 -Import   # después de traer assets nuevos
```

El runner deja el árbol como lo encontró. Correr Godot sobre el proyecto puede
re-serializar `.tscn` y `.tres` por su cuenta —agrega `uid=` y borra toda
propiedad igual a su default—, y así `game.tscn` perdió dos veces el
`prewarm_count` del `EnemySpawner`. Lo que estaba limpio antes de la corrida y
quedó sucio después se revierte y se avisa; lo que ya estaba modificado es tuyo
y no se toca; los archivos nuevos se reportan pero nunca se borran. Con
`-KeepIncidentalChanges` se desactiva, que es lo que querés si justamente estás
tratando de ver qué reescribió.

Medido: hoy la corrida headless no cambia **ninguno** de los 1950 archivos
versionados. El guard está para que siga siendo cierto sin depender de que
alguien lo mire.

**Headless a mano (lo mismo que corre CI):**

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gexit
```

En Windows usá el ejecutable `_console.exe`: el otro abre su propia ventana y la
terminal no ve la salida.

El que sí reescribe es el preview de modelos, porque necesita ventana para
renderizar y en esa pasada Godot reescanea el proyecto. Va envuelto en el mismo
guard:

```powershell
pwsh tools/run_preview.ps1 rusher walk
```

**En el editor:** el panel GUT abajo, con el plugin habilitado. El botón **Run All**
recorre los directorios configurados **en el panel**, no los de `.gutconfig.json`.

Esa distinción es la que suele dejar el Run All vacío. GUT guarda la config del panel
en `user://gut_temp_directory/gut_editor_config.json` — en Windows,
`%APPDATA%\Godot\app_userdata\Mayhem\gut_temp_directory\` — que es por usuario y por
eso no está versionada. Si el panel arranca sin nada:

1. Abrilo, tocá el engranaje (*Settings*).
2. En **Directories** agregá `res://tests/unit` y `res://tests/integration`.
3. Marcá **Include Subdirs**, dejá el prefijo `test_` y el sufijo `.gd`.

El panel guarda solo al cerrar Godot, así que si querés escribir el archivo a mano,
hacelo con el editor cerrado.

`.gutconfig.json` es la config de la línea de comandos (directorios, prefijo `test_`,
código de salida). CI corre el comando headless en cada PR — ver
`.github/workflows/tests.yml`.

## Cuando la suite se pone roja sola

Síntoma: quince o veinte tests en rojo de golpe, todos de `test_audio_pool` y
`test_wave_content`, con el log lleno de `invalid UID: uid://...` y de índices de bus
de audio en `-1`. El código no tiene nada que ver: es la caché de import de **tu**
copia, `.godot/`, que quedó viciada (típicamente después de un merge que trae
`.uid`/`.import` nuevos).

Borrar `.godot/imported` y `.godot/uid_cache.bin` **no alcanza** — hay estado viejo
en `.godot/editor` también. Hay que borrar la carpeta entera:

```powershell
# Godot cerrado. Guardá esto si exportás firmado: .godot/export_credentials.cfg
Remove-Item .godot -Recurse -Force
pwsh tools/run_tests.ps1 -Import
```

Se regenera sola (está gitignoreada). Cuesta un reimport completo, unos minutos.

Para separar "roto por mi rama" de "roto en mi máquina", corré la misma orden sobre
un worktree limpio:

```powershell
git worktree add ..\baseline develop   # o la rama base que corresponda
pwsh tools/run_tests.ps1   # con $env:GODOT apuntando al mismo binario
```

Un worktree nunca trae `.godot`, así que arranca con caché fresca por definición.

## Estado actual de la suite

Godot 4.7, corrida local del 14/08/2026 sobre `develop` @ `c76d772`:
**364 tests, 364 en verde**.

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
