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

**Headless a mano (lo mismo que corre CI):**

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gexit
```

En Windows usá el ejecutable `_console.exe`: el otro abre su propia ventana y la
terminal no ve la salida.

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

## Estado actual de la suite

Última corrida local con Godot 4.7 (`feat/coop-p2p`): **379 tests, 358 en verde**.
Los rojos que quedan no son del código de juego:

- `test_audio_pool` (6) y `test_host_voice` (1) — headless levanta un solo bus de
  audio, así que `default_bus_layout.tres` no está y los índices de bus dan -1.
- `test_wave_content` (9) — los `.tres` de oleadas resuelven sus `ext_resource` por
  ruta porque el UID no coincide con el importado. Se arregla reimportando el
  proyecto (`-Import`); si persiste, es que los `.uid` versionados no coinciden con
  los de esta máquina.

Antes de dar por buena una corrida, compará contra `develop`: `git worktree add` de
`develop` y la misma orden ahí separa lo tuyo de lo que ya venía en rojo.

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
