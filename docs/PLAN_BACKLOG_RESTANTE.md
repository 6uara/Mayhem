---
tags: [mayhem, plan, backlog]
---

# MAYHEM — Plan de trabajo del backlog restante

Plan derivado del backlog de Notion (base de datos *MAYHEM Tasks*), cruzado
contra el estado real del repo al 2026-08-10. Está escrito para ser ejecutado
tarea por tarea por un agente (Claude Code / Sonnet): cada entrada dice qué
archivos tocar, qué construir, qué testear y cuándo se considera cerrada.

**Leé esta sección de reglas antes de la primera tarea. Aplica a todas.**

---

## 0. Reglas de trabajo (válidas para todo el plan)

### Convenciones del proyecto

- **GDScript estrictamente tipado.** El proyecto tiene
  `untyped_declaration` como warning activo. Toda variable, parámetro y
  retorno lleva tipo, incluidos los tipos de elemento en arrays
  (`Array[StatModifier]`, no `Array`).
- **Separación datos/código.** `scripts/resources/` = definiciones de clase
  (`class_name X extends Resource`). `data/` = instancias `.tres`. Nunca
  mezclar: si una tarea necesita un número de balance nuevo, va en un `.tres`,
  no hardcodeado en el script.
- **`EventBus` es sólo señales**, cero lógica y cero estado. Si una tarea
  necesita una señal nueva, se declara en [event_bus.gd](scripts/autoload/event_bus.gd)
  agrupada con las de su dominio y con comentario de una línea.
- **Audio siempre por `AudioPool`**, nunca instanciando `AudioStreamPlayer`
  por evento. Buses: `Master > SFX > {Weapons, Impacts, Enemies, World}`,
  `Music`, `VO`, `UI`.
- **Objetos de alta rotación por `ObjectPool`** (proyectiles, impactos,
  casquillos, números de daño).
- **Colores y medidas desde `Tokens`** ([theme_tokens.gd](scripts/autoload/theme_tokens.gd)).
  Nada de literales de color en escenas nuevas de UI: hay un test
  (`tests/unit/test_theme_tokens.gd`) que vigila la ley de color.

### Tests

- Framework: **GUT**. `tests/unit/` refleja `scripts/`, `tests/integration/`
  cubre escenas completas.
- **Ninguna tarea de este plan se cierra sin correr la suite entera** y
  dejarla en verde. Correr headless:
  ```
  godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
  ```
- Hay un test flaky conocido:
  `test_navigation_connectivity.gd::test_the_map_has_a_navmesh_at_all`.
  Si falla sólo ese y sólo a veces, no es tu cambio — anotalo y seguí.
  Si empieza a fallar **siempre**, sí es tu cambio.
- Los tests de este proyecto tienen nombres en prosa
  (`test_dashing_bursts_the_dash_trail`). Seguí ese estilo.

### Git

- Ramas: `feature/*`, `fix/*`, `chore/*` desde `develop`. Conventional
  Commits con scope (`feat(shop):`, `fix(vfx):`, `chore(tools):`).
- **Una rama por tarea de este plan.** No mezcles dos tareas numeradas en un
  mismo PR salvo que el plan las agrupe explícitamente.
- GitHub Actions corre GUT headless en cada PR: si CI está rojo, no se
  mergea.

### Riesgo específico de Godot — leelo

Godot **auto-resguarda las escenas abiertas** cuando se carga el proyecto
(por ejemplo con `--import`). Esto ya destruyó contenido real una vez en
`greybox_arena.tscn`. Por lo tanto:

- **Siempre `git diff` sobre los `.tscn` antes de commitear**, si corrió
  algún proceso del editor.
- Si vas a editar `.tscn` a mano, asegurate de que el editor no tenga esa
  escena abierta.

### Fuera de alcance de este plan

- **Viewmodel de primera persona (brazos + manos).** La tarea de Notion
  *"Define viewmodel visual style (arms + 4 weapons)"* se está trabajando en
  la rama `feature/held-weapon-visual`. **No la toques desde este plan.**
  Consecuencia práctica: no modifiques
  [viewmodel_rig.tscn](scenes/player/viewmodel_rig.tscn),
  [player.tscn](scenes/player/player.tscn),
  [first_person_head_hider.gd](scripts/components/first_person_head_hider.gd),
  [torso_aim_follower.gd](scripts/components/torso_aim_follower.gd),
  [head_bone_follower.gd](scripts/components/head_bone_follower.gd) ni
  [player_body_animator.gd](scripts/components/player_body_animator.gd).
  Varias tareas de acá abajo rozan `player.tscn` (speed lines, hints); en esos
  casos el plan indica cómo minimizar el conflicto — leé la nota de cada una.

---

## 1. Mapa del backlog restante

24 tareas no cerradas. Agrupadas en 7 tandas por dependencia, no por prioridad
de Notion: las tandas están ordenadas de modo que ninguna tarea se haga dos
veces.

| Tanda | Contenido | Por qué va en ese orden |
|---|---|---|
| **A** | Tooling (2 tareas, XS/S) | Barato, y las tandas E y D lo usan. Hacerlo después es rehacer trabajo a mano. |
| **B** | Cambios de diseño de gameplay (3) | Cambian el balance. Todo lo que sea balance o playtest tiene que ir después. |
| **C** | VFX y game feel restantes (4 items → cierran 4 tareas de Notion) | Independientes entre sí, bajo riesgo, alto retorno visual. |
| **D** | Arena: rediseño + iluminación (2, XL+L) | El lighting pass va sobre la arena rediseñada, nunca antes. |
| **E** | Audio: música, voice packs, mix (3) | El mix va al final, cuando ya existe todo el material a mezclar. |
| **F** | Arte de enemigos (1, XL) | Depende de la tanda A (bake tool). |
| **G** | Ship: export, perf, playtests, balance, bugs, trailer, build (8) | Todo lo demás tiene que estar cerrado. |

Además, dos P3 explícitamente opcionales (gamepad, crowd) que sólo se hacen si
sobra tiempo — están al final, sección 9.

---

## 2. TANDA A — Tooling

### A1. Promover el bakeo de mallas de enemigos a `tools/`

- **Notion:** *"Promover el bakeo de mallas de enemigos (fbx→.res) a tools/"* —
  P2, XS, epic AI.
- **Por qué ahora:** hoy es un script `SceneTree` de scratch, no commiteado
  (ver [12 Known Issues and Gaps.md](docs/Mayhem/12%20Known%20Issues%20and%20Gaps.md)).
  La tanda F lo va a correr 4+ veces más.

**Qué hacer**

1. Crear `tools/bake_enemy_meshes.gd`, siguiendo el patrón de los tools que ya
   existen — mirá [bake_navmesh.gd](tools/bake_navmesh.gd) y
   [build_theme.gd](tools/build_theme.gd) para la forma exacta (`extends
   SceneTree`, `func _init()`, invocación con `godot --headless -s`).
2. El tool tiene que:
   - Recibir por argumento (o iterar un directorio convenido) los `.fbx`/`.glb`
     de `assets/models/enemies/`.
   - Instanciar la escena importada, extraer las `Mesh` y guardarlas como
     `.res` en la ruta destino.
   - Loguear una línea por asset procesado y salir con código != 0 si algún
     asset falla, para que sea usable desde CI.
3. Documentar la invocación exacta en
   [11 Asset Pipeline.md](docs/Mayhem/11%20Asset%20Pipeline.md), sección
   *Weapon/enemy model import*, reemplazando la descripción del proceso
   manual.
4. Sacar el bullet correspondiente de
   [12 Known Issues and Gaps.md](docs/Mayhem/12%20Known%20Issues%20and%20Gaps.md).

**Aceptación:** correr el tool sobre el spiderbot actual reproduce el `.res`
existente sin diferencias funcionales. Suite verde.

**Commit:** `chore(tools): bake enemy meshes with a repeatable tool`

---

### A2. Exportar el guion de voicelines del Host

- **Notion:** *"Exportar guion de voicelines del Host para grabación externa"* —
  P1, S, epic AUDIO.
- **Por qué ahora:** el lead time no es programar, es coordinar personas. Cuanto
  antes salga el checklist, antes empiezan a grabar los amigos.

**Contexto de código**

- [host_catalog.gd](scripts/resources/host_catalog.gd) tiene
  `sets: Array[HostLineSet]`.
- [host_line_set.gd](scripts/resources/host_line_set.gd) tiene `id: StringName`,
  `lines: Array[String]`, `tier`, `priority`, `category_cooldown`.
- La instancia vive en `data/host/host_catalog.tres` (11 ocasiones, 37 líneas).
- La convención de archivo de audio que va a usar A2 y la tarea E2 es
  `res://assets/audio/voice/<presenter_id>/<line_id>.ogg`. **Definila acá y
  respetala en E2.**

**Qué hacer**

1. Crear `tools/export_host_script.gd` (`extends SceneTree`).
2. Carga `res://data/host/host_catalog.tres`, itera los sets y por cada línea
   emite una fila con:
   - `line_id` — convención: `<set_id>_<índice base 1>`, p. ej.
     `first_blood_01`. **Este id es el nombre de archivo esperado**, así que
     tiene que ser estable: si se reordenan las líneas de un set, los archivos
     ya grabados se desalinean. Anotá esa advertencia en el propio export.
   - `set_id` (la ocasión), `tier`, `priority`.
   - El texto de la línea.
   - El nombre de archivo esperado: `<line_id>.ogg`.
3. Salida en dos formatos, ambos a `docs/host_script/`:
   - `host_script.csv` — para pegar en una planilla y repartir.
   - `host_script.md` — checklist legible, agrupado por ocasión, con una
     cabecera que explique al que graba: formato (`.ogg`), naming, y que el
     tier `PUNCHLINE` se entrega con más énfasis que el `STANDARD`.
4. Commitear la salida generada además del tool (el guion es un entregable que
   se manda por fuera del repo).

**Aceptación:** el `.md` lista las 37 líneas con id único y no colisionante.
Correr el tool dos veces produce archivos idénticos (determinístico).

**Commit:** `chore(tools): export the host script for external recording`

---

## 3. TANDA B — Cambios de diseño de gameplay

> Estas tres cambian cómo se juega. Todo balance y todo playtest va **después**.

### B1. Loadout de un arma a la vez (reemplazo, no acumulación)

- **Notion:** P1, L, epic ECONOMY. **Es la tarea más riesgosa del plan.**
- **Diseño pedido:** el jugador arranca con la pistola. Comprar otra arma la
  **reemplaza**. Las mejoras de arma compradas hasta ese momento **quedan con
  el arma reemplazada** y no pasan a la nueva.

**Por qué es cara (leer antes de escribir código)**

Dos supuestos del código actual se rompen:

1. [weapon_holder.gd](scripts/components/weapon_holder.gd) mantiene
   `_owned: Array[WeaponComponent]` de hasta 4 armas simultáneas, con
   `cycle()`, `select_slot()`, `handle_input()` mapeando `weapon_1..4`, y
   `add_reserve_ammo_fraction()` que reparte munición entre **todas** las
   armas poseídas.
2. [upgrade_manager.gd](scripts/autoload/upgrade_manager.gd) agrega los
   modificadores **globalmente por `stat_key`**: `get_modifiers_for(stat_key)`
   recorre todos los upgrades owned sin saber a qué arma pertenecen. Hoy
   "extended mag" sube el cargador de lo que tengas equipado, siempre. Para
   que "las mejoras quedan con la pistola" sea verdad, los modificadores de
   categoría `WEAPON` tienen que trackearse **por `weapon_id`**.

**Plan de implementación, en este orden**

**Paso 1 — `UpgradeManager` con scope por arma.**

- Extender el estado interno: además de `_stacks` / `_owned` por `id`, guardar
  el `weapon_id` al que se ató cada compra de categoría `WEAPON`. Sugerencia
  de forma, respetando el estilo existente:
  ```gdscript
  ## upgrade id -> weapon_id al que quedó atado (sólo Category.WEAPON)
  var _weapon_scope: Dictionary = {}
  ```
- `add_upgrade(data: UpgradeData)` gana una sobrecarga o un parámetro opcional
  `weapon_id: StringName = &""`. Si `data.category == UpgradeData.Category.WEAPON`
  y `weapon_id` viene vacío, es un error de programación: `push_error` y
  devolver `false`. Un upgrade de arma sin arma no debe existir.
- `get_modifiers_for(stat_key)` gana un parámetro opcional
  `weapon_id: StringName = &""`. Cuando el upgrade es de categoría `WEAPON`,
  sólo aporta si su `_weapon_scope` coincide. Los upgrades `MOBILITY` y
  `SURVIVABILITY` siguen siendo globales — **no los toques**.
- **Ojo con el stacking:** hoy `can_add()` compara contra `max_stacks` por
  `id`. Con scope por arma, la pregunta correcta es *"¿cuántos stacks de este
  upgrade tiene ESTA arma?"*. Decidí y **documentá en el docstring** que
  `max_stacks` para categoría `WEAPON` es por arma, y hacé que `get_stacks()`
  acepte el `weapon_id` opcional.

**Paso 2 — `StatsComponent` / `WeaponComponent` propagando el arma.**

- [stats_component.gd](scripts/components/stats_component.gd) cachea por
  `stat_key` en `_cache`. Ese cache **se vuelve incorrecto** apenas el valor
  dependa del arma. Dos opciones; tomá la primera:
  - **(elegida)** `get_stat_from(stat_key, base_value)` gana `weapon_id`
    opcional y **no cachea** cuando viene con scope — es el camino que ya usa
    `WeaponComponent`, que pasa su propia base desde el `WeaponData`, y que ya
    hoy no toca `_cache`.
  - Cachear por clave compuesta `stat_key + weapon_id`. Más rápido, más
    superficie para bugs de invalidación. No la tomes salvo que perfilado
    diga que hace falta.
- En `WeaponComponent`, cada llamada que hoy resuelve un stat de arma
  (`magazine_size`, `fire_rate`, `reload_time`, `recoil_magnitude`,
  `spread_multiplier`, `ads_transition_time`, `reserve_ammo_max`,
  `weapon_damage`) tiene que pasar `data.id`. Buscá con
  `grep -n "get_stat_from\|_stat(" scripts/components/weapon_component.gd`.

**Paso 3 — `WeaponHolder` de un arma.**

- `_owned` deja de ser un array y pasa a ser una referencia única:
  `var current: WeaponComponent` ya existe; hacé que sea la única fuente de
  verdad y borrá `_owned`.
- `acquire(weapon_id)` pasa a ser **reemplazo**: equipa la nueva y descarta la
  anterior. Devolvé `false` si ya tenés esa arma equipada (el shop lo usa para
  rechazar la compra).
- **`reset()` de la nueva arma:** cuando el arma anterior se descarta, su
  munición y estado siguen viviendo en su `WeaponComponent` hijo (que no se
  destruye). Decidí explícitamente: **el arma descartada conserva su
  estado**, por si más adelante se quisiera volver a comprar. Documentalo.
- Borrar `cycle()` y `select_slot()`, y sacar del `handle_input()` el manejo de
  `weapon_next`/`weapon_prev`/`weapon_1..4`. **No borres las acciones del
  input map** — están definidas en `project.godot` y hay tests que cuentan
  acciones. Dejalas huérfanas y anotalo en el docstring.
- `add_reserve_ammo_fraction()` se simplifica: ahora hay una sola arma.
- `get_owned()` / `get_all()`: `get_all()` sigue teniendo sentido (el shop
  necesita saber qué armas existen). `get_owned()` pasa a devolver el arma
  actual o nada — o mejor, reemplazalo por `owns(weapon_id)`, que ya existe.
  Buscá todos los llamadores con `grep -rn "get_owned()" scripts/ tests/`.

**Paso 4 — Shop.**

- En [shop.gd](scripts/systems/shop.gd), `_buy_weapon()` ya rechaza el arma
  poseída con `MAX_STACKS`. Con reemplazo eso sigue siendo correcto: no podés
  comprar la que ya tenés.
- `_build_pool()` filtra armas con `holder.owns(weapon.id)` — sigue bien.
- **Nuevo:** al comprar un upgrade de categoría `WEAPON`, el shop tiene que
  pasarle a `EconomyManager.try_purchase_upgrade()` / `UpgradeManager` el
  `weapon_id` del arma **actualmente equipada**. Ese es el punto donde el
  scope se ata.
- **Nuevo, importante para la legibilidad del diseño:** la tarjeta de un
  upgrade de arma en el shop tiene que decir a qué arma se aplica, y la
  tarjeta de un arma tiene que advertir que reemplaza la actual y que se
  pierden sus mejoras. Si el jugador no ve eso antes de comprar, el diseño se
  siente como un bug. Es un cambio en
  [shop_screen.gd](scripts/ui/shop_screen.gd).

**Paso 5 — HUD.**

- [hud.gd](scripts/ui/hud.gd) tiene `_weapon_list` y `_rebuild_weapon_list()`
  que asumen hasta 4 slots con el equipado en rail cyan y el resto al 50% de
  opacidad. Con un arma sola, la lista es un solo elemento. Simplificá a un
  indicador de arma única (nombre + ícono), conservando el rail cyan del token.
  No inventes colores: usá `Tokens`.

**Paso 6 — Tests.** Estos hay que **reescribirlos, no ampliarlos**:

- `tests/integration/test_shop_and_loadout.gd` — asume acumulación.
- Cualquier test de `weapon_holder` (buscalo con
  `grep -rln "WeaponHolder\|weapon_holder" tests/`).
- `tests/unit/test_economy_manager.gd` y `test_stat_modifier.gd` si tocan
  categoría WEAPON.

Tests **nuevos** que hay que escribir:

- `test_buying_a_weapon_replaces_the_current_one`
- `test_weapon_upgrades_stay_with_the_weapon_they_were_bought_for`
- `test_mobility_and_survivability_upgrades_stay_global`
- `test_replacing_a_weapon_does_not_carry_its_upgrades_forward`
- `test_the_run_starts_with_the_pistol`

**Aceptación:** una corrida completa; comprás la escopeta con la pistola ya
mejorada; la escopeta arranca con stats base; el shop lo comunica antes de
comprar. Suite verde.

**Commit:** `feat(economy): carry one weapon at a time, and let upgrades stay with it`

---

### B2. Shop: menos opciones por visita + reroll

- **Notion:** P2, M, epic ECONOMY. **Hacer después de B1** — B1 cambia qué
  entra al pool.

**Qué hacer**

1. **Tuning (trivial):** bajar `offers_per_visit` en el `.tres` del
   `ShopCatalog` en `data/economy/`. El campo ya existe en
   [shop_catalog.gd](scripts/resources/shop_catalog.gd). Valor sugerido de
   arranque: **4** (hoy 6). Es tuning, se reajusta en la tanda G.
2. **Reroll (nuevo):**
   - Campos nuevos en `ShopCatalog`, en el grupo `Offer`:
     ```gdscript
     ## Costo del primer reroll de una visita. 0 desactiva el reroll.
     @export var reroll_base_cost: int = 50
     ## Cuánto sube el costo por cada reroll dentro de la MISMA visita.
     @export var reroll_cost_increment: int = 50
     ```
   - En [shop.gd](scripts/systems/shop.gd):
     ```gdscript
     signal reroll_cost_changed(cost: int)

     var _rerolls_this_visit: int = 0

     func get_reroll_cost() -> int
     func can_reroll() -> bool
     func reroll() -> EconomyManager.PurchaseResult
     ```
   - `reroll()` valida fondos vía `EconomyManager.try_spend()` con un id
     dedicado (p. ej. `&"shop_reroll"`), incrementa `_rerolls_this_visit`,
     llama a `roll_offers()` y emite `reroll_cost_changed`. Si `try_spend`
     falla, **no** se rerollea y suena `denied_sound`. La validación va acá,
     nunca en la UI — es la regla que ya sigue `buy()`.
   - `_rerolls_this_visit` se resetea al abrir la tienda. Enganchalo donde ya
     se llama a `roll_offers()` al abrir (buscá `EventBus.shop_opened` /
     `roll_offers` en [match_director.gd](scripts/systems/match_director.gd)).
3. **Decisión de diseño que el plan resuelve:** el reroll **respeta**
   `guarantee_one_per_category`. Razón: la garantía existe para que la mala
   suerte no encierre al jugador en una sola vía; un reroll que la ignora
   reintroduce exactamente ese problema y encima cobrando. Documentalo en el
   docstring de `reroll()`.
4. **UI:** botón de reroll en [shop_screen.gd](scripts/ui/shop_screen.gd) con
   el costo actual visible, deshabilitado (estado no-afford del sistema de
   tokens, el mismo que ya usan las tarjetas) cuando no alcanza la plata.

**Tests nuevos** (`tests/integration/test_shop_and_loadout.gd`):

- `test_rerolling_costs_more_each_time_within_a_visit`
- `test_the_reroll_cost_resets_when_the_shop_reopens`
- `test_a_reroll_the_player_cannot_afford_changes_nothing`
- `test_a_reroll_still_offers_one_of_each_category`

**Commit:** `feat(shop): offer fewer picks per visit, and let the player reroll them`

---

### B3. Semi-tutorial: hints contextuales de primera vez

- **Notion:** P1, M, epic UI.

**Restricción de diseño, no negociable:** esto **no** puede salir como línea
del Host. El Host le habla a la audiencia, no al jugador (ver *Game Treatment*).
Tiene que ser un overlay neutro del HUD. No uses `NarratorManager`.

**Qué hacer**

1. **Autoload nuevo** `scripts/autoload/tutorial_hint_manager.gd`, registrado
   en `project.godot`. Escucha `EventBus` y `MovementComponent` y dispara un
   hint la **primera vez** que ocurre cada mecánica.
2. **Mecánicas a cubrir** (una por hint): mover, saltar, mantle, slide, dash,
   grapple, ADS, recargar, primera tienda.
   - Movimiento/salto/mantle/slide/dash: vienen de
     [movement_component.gd](scripts/components/movement_component.gd)
     (`state_changed`) y de `EventBus.dash_used`.
   - Grapple: `EventBus.grapple_started`.
   - ADS y recarga: `EventBus.weapon_reloaded` existe; para ADS puede que
     tengas que leer `WeaponComponent.ads_progress` o agregar una señal — si
     agregás señal, va en `EventBus` con el grupo de weapon.
   - Primera tienda: `EventBus.shop_opened`.
3. **Contenido como datos, no como literales.** Creá
   `scripts/resources/tutorial_hint.gd` (`id`, `text`, `duration`, y opcional
   el nombre de la acción del input map para mostrar la tecla real) y un
   `data/tutorial/tutorial_hints.tres` con la lista. Un hint que muestre la
   tecla debe leerla del input map, no hardcodearla — el juego tiene remapeo
   completo y un hint que dice "SHIFT" cuando el jugador rebindeó es peor que
   no tener hint.
4. **Persistencia:** el "ya lo vio" se guarda vía
   [save_manager.gd](scripts/autoload/save_manager.gd). Hoy ese autoload sólo
   maneja el leaderboard en `user://leaderboard.json`, y su docstring dice
   explícitamente *"nothing carries between runs"*. Esto lo cambia: agregá un
   archivo aparte `user://tutorial.json` (no lo mezcles con el leaderboard) y
   **actualizá el docstring** para que deje de mentir.
   API sugerida: `has_seen_hint(id) -> bool` / `mark_hint_seen(id) -> void` /
   `clear_hints() -> void`.
5. **UI:** un overlay discreto en [hud.tscn](scenes/ui/hud.tscn) — no un modal,
   no pausa el juego. Estilo con `Tokens` y `ChamferStyleBox` como el resto del
   HUD. Nunca dos hints a la vez: si llega uno mientras hay otro visible,
   encolalo o descartalo (elegí encolar, con un tope).
6. **Settings:** agregá en [settings_screen.gd](scripts/ui/settings_screen.gd)
   un botón "Reset tutorial hints" que llame a `clear_hints()`. Es lo que te va
   a salvar en la tanda G cuando quieras que un playtester vea los hints en
   frío.

**Tests nuevos** (`tests/integration/`, archivo nuevo `test_tutorial_hints.gd`):

- `test_each_hint_fires_only_the_first_time_its_mechanic_happens`
- `test_a_seen_hint_stays_seen_across_a_reload`
- `test_hints_never_overlap_on_screen`
- `test_a_hint_shows_the_currently_bound_key`

**Commit:** `feat(ui): teach each mechanic the first time the player does it`

---

## 4. TANDA C — VFX y game feel restantes

> Cuatro items independientes. Cierran cuatro tareas de Notion:
> *Impact VFX and decals keyed to surface material*, *Game feel polish*,
> *Full VFX pass* y *Movement VFX*. Se pueden hacer en cualquier orden, pero
> C1 y C2 son las de mayor retorno.

### C1. Impact VFX y decals por material de superficie

- **Notion:** *"Impact VFX and decals keyed to surface material"* — P1, M,
  In progress.
- **Estado:** [impact_effect.gd](scripts/systems/impact_effect.gd) sólo
  distingue mundo vs. carne (`play_at(pos, normal, is_flesh)`), con
  `world_sound` / `flesh_sound` y un `Decal` que se oculta en carne.

**Qué hacer**

1. **Resource nuevo** `scripts/resources/surface_material_data.gd`:
   ```gdscript
   class_name SurfaceMaterialData
   extends Resource

   @export var id: StringName = &""
   @export var impact_sound: AudioStream
   @export var decal_texture: Texture2D
   @export var particle_color: Color = Color.WHITE
   @export var spawns_decal: bool = true
   ```
   Instancias `.tres` en `data/surfaces/`: al menos `concrete`, `metal`,
   `flesh`, `glass` o similar según lo que tenga la arena. Mantené el set
   chico — cada material nuevo es contenido de audio que hay que producir.
2. **Cómo se identifica la superficie.** Elegí **grupos de nodo**
   (`add_to_group(&"surface_metal")`) o una `meta` en el `StaticBody3D`
   (`set_meta(&"surface", &"metal")`). Tomá **la meta**: no ensucia el árbol de
   grupos, que ya se usa para lógica de gameplay (`&"player"`), y se ve en el
   inspector. El lookup vive en un helper estático — ponelo en
   `scripts/util/` junto a [physics_layers.gd](scripts/util/physics_layers.gd).
   **Fallback obligatorio:** una superficie sin meta usa el material por
   defecto y **no** loguea error por frame.
3. `ImpactEffect.play_at()` cambia de firma: en vez de `is_flesh: bool`, recibe
   el `SurfaceMaterialData` (o el `StringName` del id y lo resuelve). Actualizá
   los llamadores — buscalos con `grep -rn "play_at" scripts/`; los principales
   son [projectile.gd](scripts/systems/projectile.gd) y
   [enemy_projectile.gd](scripts/systems/enemy_projectile.gd).
4. El decal usa la textura del material; las partículas toman su color. Carne
   sigue sin decal (`spawns_decal = false` en su `.tres`, no un `if` en el
   código).
5. **Presupuesto de decals.** Los decals son el ítem que más fácil rompe el
   objetivo de 60 FPS de la tanda G. `ImpactEffect` ya sale del `ObjectPool`
   con `LIFETIME = 1.2`, así que hay tope natural — **verificá que el tamaño
   del pool esté acotado** y no lo subas sin medir.

**Tests** (`tests/integration/test_shooting_and_hitboxes.gd` o archivo nuevo):

- `test_each_surface_material_picks_its_own_impact_sound`
- `test_flesh_impacts_leave_no_decal`
- `test_an_unmarked_surface_falls_back_without_erroring`

**Commit:** `feat(vfx): key impacts, decals and sound to the surface that was hit`

---

### C2. Números de daño flotantes

- **Notion:** parte de *"Game feel polish: hitstop, damage numbers, transitions"* —
  el hitstop ya está hecho
  ([hitstop_controller.gd](scripts/systems/hitstop_controller.gd)).

**Qué hacer**

1. Escena nueva `scenes/vfx/damage_number.tscn` con un `Label3D` (billboard),
   script `scripts/ui/damage_number.gd`. `Label3D` y no un `Control`
   proyectado: sigue al enemigo en el mundo sin cálculo de pantalla y respeta
   la oclusión.
2. **Va por `ObjectPool`.** En una ola elite hay decenas por segundo; es
   exactamente el caso que el pool existe para cubrir.
3. Se dispara desde `EventBus.damage_dealt(target, amount, is_headshot)` — la
   misma señal que ya consume `HitstopController`. Poné el listener en un nodo
   de `game.tscn` al lado de `HitstopController`, con el mismo patrón.
4. **Tratamiento visual, con `Tokens`:**
   - Daño normal: color de texto base, tamaño base.
   - Headshot: color de acento + más grande. El headshot ya se diferencia en
     hitstop y en hitmarker; que también se diferencie acá.
   - Animación: sube y hace fade en ~0.6 s con un `Tween`. Un jitter horizontal
     chico por número evita que golpes simultáneos se apilen en la misma
     columna ilegible.
5. **Toggle en settings.** Los números de daño son divisivos y el menú de
   settings del proyecto es un argumento de portfolio. Agregá el toggle en
   [settings_manager.gd](scripts/autoload/settings_manager.gd) y
   [settings_screen.gd](scripts/ui/settings_screen.gd), al lado del de
   screenshake.

**Tests** (`tests/unit/test_damage_numbers.gd`):

- `test_a_hit_spawns_exactly_one_number`
- `test_headshots_read_differently_from_body_shots`
- `test_numbers_come_from_the_pool_and_go_back`
- `test_turning_damage_numbers_off_spawns_nothing`

**Commit:** `feat(vfx): float a damage number on every hit`

---

### C3. Transiciones de escena

- **Notion:** el tercer item de *"Game feel polish"*. Con C2 esto **cierra esa
  tarea**.
- **Ya existe** `assets/shaders/scene_change.gdshader` sin usar. Usalo.

**Qué hacer**

1. Un `CanvasLayer` de transición con capa alta, en un autoload o en la escena
   raíz, con un `ColorRect` usando `scene_change.gdshader`.
2. [game_manager.gd](scripts/autoload/game_manager.gd) hace los cambios de
   escena hoy. Envolvé ese camino: `fade_out → change_scene → fade_in`,
   `await` de por medio. Toda transición pasa por ahí; ningún llamador debería
   poder cambiar de escena salteando el fade.
3. **`process_mode`:** la capa de transición tiene que ser
   `PROCESS_MODE_ALWAYS`, igual que `NarratorManager`, o se congela si el
   cambio ocurre desde el menú de pausa.
4. Cubrí las cuatro transiciones reales: menú→partida, partida→game over,
   game over→menú, reintentar.

**Tests:** `tests/integration/test_match_flow.gd` — que los cambios de escena
sigan funcionando y **no se cuelguen** si la transición nunca termina
(poné un tope de tiempo duro en el fade).

**Commit:** `feat(ui): fade between scenes instead of cutting`

---

### C4. Speed lines

- **Notion:** último item pendiente de *"Movement VFX: dash trail, slide sparks,
  speed lines"*. Con esto **esa tarea cierra**.
- Dash trail y slide sparks ya están en
  [movement_vfx_component.gd](scripts/components/movement_vfx_component.gd).

**⚠ Nota de conflicto:** esto toca `player.tscn`, que la rama
`feature/held-weapon-visual` está editando. **Mantené el cambio de escena al
mínimo**: agregá un solo nodo hijo y toda la lógica en script. Rebaseá antes
de mergear.

**Qué hacer**

1. Efecto de pantalla (no partículas 3D): un `ColorRect` a pantalla completa
   en el HUD con un shader radial de líneas, cuya intensidad sale de la
   velocidad horizontal del jugador.
2. La intensidad se mapea desde `MovementComponent`: cero por debajo de la
   velocidad base de caminata, sube hasta el máximo cerca de la velocidad
   pico de slide/grapple. **Ese umbral es tuning y va en un `@export`**, no
   hardcodeado.
3. **Suavizá la interpolación.** Sin suavizado el efecto parpadea en cada
   micro-cambio de velocidad y marea.
4. **Respetá el toggle de screenshake.** Quien apaga screenshake apaga por
   incomodidad; las speed lines caen en la misma categoría. Reusá esa
   preferencia o agregá una propia junto a ella.

**Tests** (ampliando el archivo que ya cubre movement VFX):

- `test_speed_lines_stay_off_at_walking_speed`
- `test_speed_lines_ramp_with_horizontal_speed`

**Commit:** `feat(vfx): draw speed lines when the player is actually fast`

---

## 5. TANDA D — Arena

### D1. Rediseño y vestido real de la arena (salir de greybox)

- **Notion:** P1, **XL**, epic ARENA. La tarea individual más grande del plan
  junto con F1.
- **Restricción de Notion:** va **antes** del lighting pass, y hay que
  verificar con tests de conectividad que el dressing nuevo no rompe los
  `NavigationLink3D` ni el navmesh.

**Antes de tocar nada**

1. Leé [Level Design Document — La Arena](https://app.notion.com/p/3b47604d073b816cab20e8a6a421a27b)
   y el [Art Bible](https://app.notion.com/p/3b47604d073b8130942de79c4430f2cc).
   El estilo es base oscura + acentos emisivos de alta saturación
   (refs: Deadlock, The Finals).
2. Corré `tests/integration/test_navigation_connectivity.gd` y
   `test_arena_navigation.gd` **antes** de cambiar nada y guardá la salida.
   Es tu línea de base; sin ella no vas a saber qué rompiste.
3. Contá los `NavigationLink3D` reales. El backlog dice 12; en
   `greybox_arena.tscn` no aparecen como nodos directos —
   vienen instanciados desde [jump_link.tscn](scenes/arena/jump_link.tscn).
   **Verificá el número antes de empezar** y anotalo.

**Cómo trabajar (crítico para no perder trabajo)**

- **Hacelo en pasos chicos y commiteables.** Un XL de geometría en un solo
  commit es irrecuperable si algo sale mal.
- Releé la advertencia de auto-resave de la sección 0. `greybox_arena.tscn` ya
  perdió contenido una vez por eso.
- **Nunca borres un elemento de gameplay para hacerle lugar al dressing.** Los
  anchors de grapple, bounce pads, plataformas que desaparecen, hazards,
  pickups de munición y spawn doors tienen un sistema de color-coding y
  telegrafía ya cerrado. La geometría nueva se acomoda alrededor de ellos.

**Secuencia sugerida**

1. **Pase de silueta.** Ajustá la geometría mayor (niveles, rampas, coberturas)
   con el layout de combate ya validado. Rebakeá el navmesh con
   [bake_navmesh.gd](tools/bake_navmesh.gd) y corré los tests de navegación
   **en cada paso**.
2. **Pase de dressing.** Props y detalle. Sci-fi; ya hay un `scifi_container`
   integrado como cobertura. El dressing es **no colisionable** salvo que sea
   deliberadamente cobertura — un prop decorativo con colisión es un enganche
   de momentum, y el pilar de movilidad ya pasó su gate.
3. **Pase de legibilidad.** Verificá que el color-coding siga leyéndose contra
   el fondo nuevo. Este es el riesgo real del dressing: la telegrafía funciona
   hoy porque el fondo es gris plano.
4. **Rebakear navmesh + verificar links** al final, otra vez.
5. **Volvé a jugar el gate de fase 2**: la arena tiene que seguir siendo
   divertida de recorrer sin combate. Si el dressing mató el flow, el dressing
   está mal, no el flow.

**Aceptación:** navmesh bakeado, conectividad en verde, los 12 (o N) links
funcionando, todos los elementos de gameplay presentes y legibles, el gate de
movilidad sigue subjetivamente en pie. Suite verde.

**Commits:** varios, `feat(arena): ...` por pase.

---

### D2. Lighting pass en la arena

- **Notion:** P1, L, epic ARENA. **Sólo después de D1.**
- **Estado:** un `DirectionalLight3D` + `WorldEnvironment` básico.

**Qué hacer**

1. **Iluminación clave** coherente con el Art Bible: base oscura, los acentos
   emisivos hacen el trabajo de color. La arena es un espectáculo televisado —
   luces de estadio son una justificación diegética válida.
2. **`WorldEnvironment`:** pase real de bloom/glow (los acentos emisivos lo
   necesitan), tonemap, ambient. Hay un `aurora_sky.gdshader` sin usar en
   `assets/shaders/` — evaluá si entra.
3. **La legibilidad manda sobre la belleza.** Los enemigos tienen que leerse
   contra el fondo en cada zona. Si una zona queda linda y los rushers no se
   ven, la zona está mal.
4. **El costo es real y se paga en la tanda G.** Cada luz dinámica con sombra
   sale cara. Decidí qué es estático (bakeable) y qué dinámico, y anotá esa
   decisión — vas a volver a ella durante el profiling.
5. Actualizá [08 VFX and Shaders.md](docs/Mayhem/08%20VFX%20and%20Shaders.md)
   con el setup final.

**Commit:** `feat(arena): light the arena like the broadcast it is`

---

## 6. TANDA E — Audio

### E1. Agregar música

- **Notion:** P2, M. `assets/audio/music/` está vacío; el bus `Music` está
  cableado y sin usar.

**Qué hacer**

1. Conseguí las pistas (licencia libre o propias — **verificá la licencia y
   anotala** en un `assets/audio/music/CREDITS.md`, hace falta para publicar).
   Mínimo: menú, combate, tienda/entre-olas.
2. Un `MusicManager` — como autoload nuevo, o dentro de
   [audio_pool.gd](scripts/autoload/audio_pool.gd) si encaja sin inflarlo.
   Responsabilidades: reproducir en el bus `Music`, loopear, y hacer
   crossfade entre estados.
3. Los estados se enganchan a señales que ya existen: `EventBus.wave_started`,
   `wave_completed`, `shop_opened`, `shop_closed`, `player_died`,
   `match_completed`.
4. **Crossfade, no corte.** Un corte seco entre combate y tienda se nota más
   que no tener música.
5. **Ducking:** la música tiene que bajar cuando habla el Host. El
   `NarratorManager` ya duckea otros buses — enganchate a ese mecanismo en vez
   de inventar uno.
6. Volumen de música separado en settings (ya hay controles de volumen; agregá
   el de música si falta).

**Tests:** `test_music_follows_the_match_state`, `test_music_ducks_under_the_host`.

**Commit:** `feat(audio): score the match`

---

### E2. Voces del presentador seleccionables (voice packs)

- **Notion:** P2, M. Depende de **A2** (el guion exportado) y de que los amigos
  hayan grabado. **Podés implementar el sistema sin esperar las grabaciones**:
  `NarratorManager` ya cae a subtítulo si falta el audio.

**Qué hacer**

1. **Resource nuevo** `scripts/resources/host_presenter.gd`:
   ```gdscript
   class_name HostPresenter
   extends Resource

   @export var id: StringName = &""
   @export var display_name: String = ""
   @export var icon: Texture2D
   ## Línea que suena al previsualizar el presentador en Settings.
   @export var preview_line_id: StringName = &""
   ```
   Instancias en `data/host/presenters/`. Incluí siempre un presentador
   **"Subtitles only"** que no tenga audio: es el fallback y también el estado
   inicial mientras no haya grabaciones.
2. **Convención de archivo** (definida en A2, respetala tal cual):
   `res://assets/audio/voice/<presenter_id>/<line_id>.ogg`.
   Sumar un presentador nuevo tiene que ser **sólo copiar una carpeta** — si
   hace falta editar un `.tres` por línea, el diseño está mal.
3. **Resolución del stream:** en
   [narrator_manager.gd](scripts/autoload/narrator_manager.gd), cuando se pide
   una línea, construir la ruta con el presentador activo y cargar con
   `ResourceLoader.exists()` antes de `load()`. Si no existe, **subtítulo solo**
   — que es lo que el manager ya sabe hacer. Cero errores en consola por una
   línea sin grabar: es el estado normal durante producción.
4. **Cachear** los streams resueltos por `line_id`, y **limpiar el cache al
   cambiar de presentador**.
5. **Selector en Settings** ([settings_screen.gd](scripts/ui/settings_screen.gd)):
   dropdown de presentadores + botón de escucha que reproduce
   `preview_line_id`. Persistir en
   [settings_manager.gd](scripts/autoload/settings_manager.gd).

**Tests** (`tests/integration/test_host_voice.gd`, que ya existe):

- `test_a_missing_recording_still_shows_the_subtitle`
- `test_switching_presenter_switches_the_audio_path`
- `test_adding_a_presenter_needs_no_code_change` (verificable armando un
  presentador de prueba en el test)

**Commit:** `feat(audio): let the player pick who hosts the show`

---

### E3. Mezcla completa y balance de buses

- **Notion:** P1, L. **Última tarea de audio.** No tiene sentido mezclar antes
  de que exista todo el material (música de E1, voces de E2, impactos por
  material de C1).

**Qué hacer**

1. Trabajá sobre `default_bus_layout.tres`. Buses existentes:
   `Master > SFX > {Weapons, Impacts, Enemies, World}`, `Music`, `VO`, `UI`.
2. **Jerarquía de mezcla, en este orden de prioridad** (es una decisión de
   diseño, no una preferencia): el jugador tiene que poder identificar
   amenazas sin mirar (es requisito explícito del audio de enemigos).
   1. `VO` (el Host, cuando habla) y audio de enemigos crítico (windup).
   2. `Weapons` — es el pilar #1 del portfolio.
   3. `Impacts` — el feedback que cierra el loop de disparo.
   4. `Enemies` ambiental, `World`.
   5. `Music` — cama, nunca protagonista.
   6. `UI`.
3. **Ducking:** VO duckea todo lo demás (ya existe). Música duckea contra VO.
   Verificá que el ducking no se sienta como un bug de volumen.
4. **Compresión/limitación en `Master`** para que una ola elite no clippee. Es
   el escenario de peor caso: 27 enemigos, disparo automático, impactos.
5. **Probá con headphones y con parlantes de laptop.** Una mezcla que sólo
   funciona en headphones falla en el 100% de los playtests presenciales.
6. **Rango dinámico:** el momento más fuerte del juego no puede ser 40 dB más
   alto que el más silencioso, o el jugador vive tocando el volumen.
7. Documentá los valores finales y el porqué en
   [Audio Design Document](https://app.notion.com/p/3b47604d073b81acaa6ac608c7492edc)
   o en un doc local.

**Aceptación:** una ola elite completa no clippea; el Host se entiende con
todo sonando; los windups de enemigo se identifican sin mirar.

**Commit:** `feat(audio): mix the whole thing`

---

## 7. TANDA F — Arte de enemigos

### F1. Modelar y animar enemigos propios por arquetipo

- **Notion:** P1, **XL**, epic AI. Depende de **A1** (bake tool).
- **Estado:** los 5 arquetipos comparten `spiderbot.res`, diferenciados a
  propósito por escala y color.

**Orden de producción** (por tiempo en pantalla, según Notion):

1. **Elite** — el que más se mira, el que más importa.
2. **Rusher** y **Ranger** — el grueso de las olas.
3. **Healer** y **Summoner** — los últimos.

**Por cada arquetipo**

1. Modelo low-poly acorde al Art Bible.
2. Clips mínimos de animación: **idle, locomoción, ataque/windup, muerte**. El
   windup es funcional, no cosmético: es la telegrafía que el jugador lee para
   esquivar. Un windup que no se lee es un bug de diseño.
3. Importar y bakear con el tool de **A1**.
4. Wiring: `EnemyData` ya es data-driven, así que el cableado final es rápido.
   Mirá [enemy_data.gd](scripts/resources/enemy_data.gd) y
   [enemy.tscn](scenes/enemies/enemy.tscn) — probablemente necesites permitir
   una escena de modelo por arquetipo en `EnemyData` en vez de la malla
   compartida.
5. **Verificá que las hitboxes sigan alineadas.** Cabeza y cuerpo son zonas
   separadas con multiplicador; un modelo nuevo con la hitbox de cabeza mal
   puesta rompe el headshot en silencio. Hay tests de hitbox
   (`test_shooting_and_hitboxes.gd`) — extendelos por arquetipo.
6. **Escala y silueta:** hoy la diferenciación por escala/color es intencional
   y **funciona** — el jugador distingue arquetipos de un vistazo. Los modelos
   nuevos tienen que **preservar esa legibilidad de silueta**, no perderla en
   nombre del detalle. Si el Elite nuevo no se distingue del Rusher a 30 m, el
   modelo está mal aunque sea más lindo.
7. **Costo de rendimiento:** 27 enemigos simultáneos en la ola más grande, con
   pool prewarmeado a 32. El presupuesto de polígonos y de material por
   enemigo se paga ×32. Medilo apenas entre el primer arquetipo, no al final.

**Commits:** uno por arquetipo, `feat(enemies): give the elite its own body`, etc.

---

## 8. TANDA G — Ship

> Orden estricto. Cada una depende de la anterior.

### G1. Export pipeline y `docs/EXPORT.md`

- **Notion:** P0, M, In progress. [EXPORT.md](docs/EXPORT.md) ya documenta los
  presets Windows Dev/Release planeados, pero `project.godot` **no tiene
  feature tags custom** — hoy sólo `config/features=PackedStringArray("4.7",
  "Forward Plus")`.

**Qué hacer**

1. Configurar los feature tags custom que `EXPORT.md` describe (`dev` /
   `release` o los que el doc nombre — **seguí el doc, no inventes nombres**).
2. Configurar los presets reales en `export_presets.cfg`. Ojo: la convención
   de Notion dice que `export_presets.cfg` está gitigneado. **Verificá el
   `.gitignore` real** — si está ignorado, el doc tiene que traer los valores
   exactos para reconstruirlo, porque si no el pipeline no es reproducible.
3. Diferencias entre presets: el build dev conserva herramientas de debug
   (Debug Draw 3D, visualizador de recoil); el release no.
4. **Probá que ambos exporten** de verdad, no sólo que estén configurados.
5. Actualizá `EXPORT.md` para que describa lo implementado y no lo planeado.

**Commit:** `chore(release): make the export presets real`

---

### G2. Profiling: sostener 60 FPS en una ola elite llena

- **Notion:** P0, L. *"Frame drops in the arena are as severe as a crash."*
- **Va después de D1/D2/F1**: son las tres tandas que agregan costo.

**Qué hacer**

1. **Definí el escenario de medición y dejalo fijo:** la ola más grande
   autorada (27 enemigos), con el jugador disparando, en la zona más cargada
   de la arena. Todas las mediciones sobre el mismo escenario o no son
   comparables.
2. Medí con el profiler de Godot: tiempo de frame, draw calls, tiempo de
   física, tiempo de script.
3. **Sospechosos habituales, en orden:**
   - Luces dinámicas con sombra (D2).
   - Decals de impacto (C1) — cada uno es un draw call.
   - Partículas: muzzle flash, casquillos, dash trail, slide sparks, impactos.
   - Números de daño (C2) si el pool está mal dimensionado.
   - Consultas de navegación de 27 agentes.
4. **Arreglá lo que midas, no lo que supongas.** Anotá el antes/después de
   cada cambio.
5. **Medí en la máquina más lenta a la que tengas acceso**, no sólo en la de
   desarrollo.
6. Documentá el resultado y el escenario en un doc para poder re-medir tras
   G5.

**Aceptación:** 60 FPS sostenidos en el escenario definido. Si no llega,
documentá qué falta y cuánto.

**Commit:** `perf(arena): hold 60 in a full elite wave`

---

### G3. Playtesting externo, ronda 1

- **Notion:** P0, L. *"Do not rely on your own read — you are the most skilled
  player of this game by far."*

**Esto no lo hace el agente.** Lo que sí puede preparar:

1. **Build jugable** vía G1.
2. **Cuestionario escrito.** Cubrí: claridad de las mecánicas (¿los hints de
   B3 funcionaron?), sensación del gunplay, sensación de movimiento,
   comprensión de la economía, dificultad percibida por ola, momento de
   abandono, y una pregunta abierta.
3. **Guía de observación** para mirar mientras juegan: dónde se traban, qué
   mecánica nunca usan, en qué ola mueren, si usan la tienda o la saltean.
4. **Instrumentación mínima** si es barata: loguear a un archivo la ola
   alcanzada, tiempo por ola, daño recibido, compras hechas, rerolls. Los
   datos objetivos valen más que el recuerdo del tester.
5. **Reset de hints entre testers** (el botón de B3).

**Salida:** un doc de hallazgos crudos, sin filtrar todavía.

---

### G4. Iteración de balance desde el feedback

- **Notion:** P0, **XL**. Cierra también *"First balance pass on economy and
  difficulty curve"* (In progress: se subieron conteos ~40-50% y se reajustó
  `par_time`, falta el pase real con playtesting).

**Qué hacer**

1. Consolidá los hallazgos de G3 en cambios concretos. Distinguí *"un tester
   sufrió"* de *"cinco testers sufrieron en el mismo lugar"*.
2. **Todo cambio de balance es un `.tres`, nunca código.** Las palancas:
   - `data/waves/` — conteos por ola, `par_time`.
   - `data/economy/` — `EconomyConfig` (recompensas por arquetipo, bonus sin
     daño, escalones de bonus de velocidad), `ShopCatalog` (precios,
     `offers_per_visit`, costos de reroll de B2).
   - `data/upgrades/` — magnitudes y `max_stacks`.
   - `data/enemies/` — vida, velocidad, daño, alcance, cooldown.
   - `data/weapons/` — daño, cadencia, cargador, falloff, patrones de recoil.
3. **Cambiá una variable por iteración cuando puedas.** Diez cambios a la vez
   y no vas a saber cuál ayudó.
4. **La curva importa más que los números absolutos.** Diez olas tienen que
   sentirse como una escalada, no como una meseta con un pico.
5. **B1 cambió la economía de raíz** (un arma a la vez, upgrades atados al
   arma). Los precios de armas y de upgrades de arma casi seguro necesitan
   revisión: comprar un arma nueva ahora tiene un costo oculto (perdés sus
   mejoras) que el precio tiene que reflejar.
6. Verificá que los tests de contenido de olas
   (`tests/unit/test_wave_content.gd`) sigan pasando y **actualizalos** si
   codifican conteos viejos.

**Commit:** `balance(economy): retune the curve from playtest feedback`

---

### G5. Ronda 2 de playtesting

- **Notion:** P1, M. Igual que G3, sobre la build ya balanceada. El objetivo es
  **confirmar que G4 arregló lo que rompía**, no abrir una lista nueva.
  Alcance más chico a propósito.

---

### G6. Pase de bug fixing

- **Notion:** P0, **XL**.

**Qué hacer**

1. Consolidá una lista: hallazgos de G3/G5, los items abiertos de
   [12 Known Issues and Gaps.md](docs/Mayhem/12%20Known%20Issues%20and%20Gaps.md),
   y todo lo que el plan haya ido anotando.
2. **Deudas ya identificadas que hay que cerrar acá:**
   - **Root-causear el test flaky** `test_the_navmesh_at_all`. Un test flaky
     en CI degrada la confianza en toda la suite.
   - **Cobertura faltante.** El doc de gaps está desactualizado en esto:
     `GrappleComponent` y `BouncePad` **ya tienen** test commiteado
     (`tests/unit/test_grapple_component.gd`, `test_bounce_pad.gd`) —
     corregí el doc. Lo que sigue sin cubrir es **`StatsComponent`**, que es
     el camino de lectura de *todos* los upgrades del juego y no tiene ni un
     test; después de B1 es todavía más crítico. También `GameManager` y
     `AudioPool`.
   - **Menú principal placeholder.** `main_menu.gd` sigue siendo `Control` y
     `Button` planos, sin tema, sin `ChamferStyleBox`, mientras todo el resto
     de la UI usa el sistema de tokens. Es la **primera pantalla que ve
     cualquiera que abra el juego** y el primer frame del trailer de G8.
     Rehacela.
   - **Drift de `Tokens.CROSSHAIR_COLORS`** (todavía tiene el verde hazard
     viejo `#C6FF3D` cuando `Tokens.HAZARD` pasó a naranja lava `#FC3A00`).
   - **Uniforms de shader hardcodeados** en `.tscn` en vez de derivados del
     token en runtime — al menos dejá un test que atrape el drift.
   - **Housekeeping:** `assets/materials/Lava.tres` superseded,
     `assets/shaders/vhs.gdshader` stub vacío. Confirmá y borrá.
3. Priorizá: crashes → progresión bloqueada → feel roto → cosmético.

**Commits:** varios `fix(...)`.

---

### G7. Build final de Windows

- **Notion:** P0, M. Con G1 hecho es mecánico: exportar con el preset release,
  probar la build exportada **en una máquina limpia** (no la de desarrollo —
  las dependencias faltantes sólo aparecen ahí), subir al Drive de builds.

---

### G8. Trailer de portfolio y gameplay reel

- **Notion:** P0, L. *"Record DURING this phase, not after. Lead with gunplay
  and movement — the two pillars."*
- **Empezá a grabar apenas D2 y F1 estén cerrados**, no después de G7. Vas a
  querer material de sobra.
- El orden importa: gunplay y movimiento primero. Son los dos pilares y los dos
  ganchos del portfolio.

---

### G9. Case study / postmortem de portfolio

- **Notion:** P1, M. *"For a solo dev this is often what gets you the
  interview."*
- Materia prima ya existente y muy buena: `docs/PHASE_*.md`, `docs/Mayhem/*`,
  el historial de git, y las decisiones documentadas en este plan (B1 en
  particular es un caso de estudio de refactor con motivo de diseño).
- Contá **los tradeoffs**, no sólo el resultado: Phantom Camera instalado y
  descartado en favor de un componente propio, Dialogic removido, recoil
  determinístico como decisión explícita contra la aleatoriedad, hitstop sólo
  al infligir daño y nunca al recibirlo, un arma a la vez como cambio de
  diseño a mitad de camino y lo que costó.

---

## 9. Opcionales P3 — sólo si sobra tiempo

Ambas están marcadas explícitamente como fuera de alcance en Notion. **No las
empieces mientras quede algo de las tandas A–G.**

### P3-a. Soporte de gamepad

Notion: *"Explicitly out of scope. Only if everything else is done."* Las ~21
acciones del input map ya son remapeables, así que la base está. El costo real
no es el binding: es el aim assist, sin el cual un shooter con este techo de
skill es injugable con stick.

### P3-b. Espectadores reactivos (crowd)

Stretch goal. El patrón está definido y es claro: calcar `HostDirector` /
`EventBus` con un autoload `CrowdManager` + un resource `CrowdReactionSet`,
reaccionando a `wave_cleared`, `player_damaged`, kill streak, ola elite,
`player_died`, clear sin daño, con audio de multitud + un estado de animación
sobre un pool de figuras low-poly en la tribuna. El asset de multitud puede ser
deliberadamente barato.

---

## 10. Resumen de dependencias

```
A1 (bake tool) ───────────────────────► F1 (modelos de enemigos)
A2 (guion Host) ──────────────────────► E2 (voice packs)

B1 (un arma) ──► B2 (reroll) ─┐
B3 (hints) ───────────────────┤
C1..C4 (VFX) ─────────────────┤
D1 (arena) ──► D2 (lighting) ─┼──────► G2 (perf) ──► G3 (playtest 1)
E1 (música) ──┐               │                          │
E2 (voces) ───┼► E3 (mix) ────┤                          ▼
F1 (enemigos) ────────────────┘                     G4 (balance)
                                                         │
G1 (export) ──────────────────────────► G3              ▼
                                                    G5 (playtest 2)
                                                         │
                                                         ▼
                                                    G6 (bugs)
                                                         │
                                              ┌──────────┼──────────┐
                                              ▼          ▼          ▼
                                          G7 (build) G8 (trailer) G9 (case study)
```

**Fuera de este grafo:** el viewmodel de primera persona, en
`feature/held-weapon-visual`. Cerrarlo antes de G8 — el trailer arranca con
gunplay y el arma flotando sin manos se ve en el primer segundo.
