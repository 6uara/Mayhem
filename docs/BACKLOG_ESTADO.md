---
tags: [mayhem, backlog, estado]
---

# MAYHEM — Estado del backlog al 2026-08-25

Auditoría del repo (`develop` @ `ae71de0`, más el árbol de trabajo sin
commitear) cruzada contra [PLAN_BACKLOG_RESTANTE.md](PLAN_BACKLOG_RESTANTE.md),
que estaba escrito contra el estado del 2026-08-10 y quedó desactualizado: de
las 24 tareas que listaba, **16 están cerradas y verificadas en el repo**.

Cada fila dice cómo se verificó. Nada acá está asumido: si dice "hecho", hay un
archivo, un test o una medición que lo respalda.

---

## 1. Resumen

| Tanda | Cerradas | Abiertas |
|---|---|---|
| A — Tooling | 2 / 2 | — |
| B — Diseño de gameplay | 3 / 3 | — |
| C — VFX y game feel | 4 / 4 | — |
| D — Arena | 0 / 2 | D1, D2 |
| E — Audio | 3 / 3 | — |
| F — Arte de enemigos | parcial | F1 (4 de 8 arquetipos) |
| G — Ship | 2 / 8 | G3…G9 |
| P3 — Opcionales | 0 / 2 | gamepad, crowd |

**Lo que queda para entregar es, en orden: vestir la arena (D1+D2), terminar los
modelos que faltan (F1), y toda la tanda G a partir de los playtests.** Todo el
trabajo de sistemas está hecho.

---

## 2. Cerradas — con la evidencia

### Tanda A — Tooling

- **A1. Bakeo de mallas de enemigos a `tools/`** — hecho.
  `tools/bake_enemy_meshes.gd` está commiteado, con su `.uid`. Además apareció
  `tools/preview_enemy_model.gd` + `tools/run_preview.ps1`, que no estaban en el
  plan.
- **A2. Export del guion de voicelines del Host** — hecho.
  `tools/export_host_script.gd` y la salida generada en `docs/host_script/`
  (`host_script.csv`, `host_script.md`) están en el repo, con los archivos de
  traducción que Godot derivó del CSV.

### Tanda B — Cambios de diseño de gameplay

- **B1. Loadout de un arma a la vez** — hecho. `StatsComponent.get_stat_from()`
  toma `weapon_id: StringName` opcional y lo pasa a `UpgradeManager.get_stat()`,
  que es exactamente la opción elegida en el plan (scope por arma, sin cachear).
  Cubierto por `tests/unit/test_stats_component.gd`.
- **B2. Shop con reroll** — hecho. `reroll` aparece en `ShopCatalog`,
  `scripts/systems/shop.gd`, `scripts/ui/shop_screen.gd` y
  `data/economy/shop_catalog.tres`, o sea el par regla-en-el-sistema /
  precio-en-datos que pedía el plan.
- **B3. Hints contextuales de primera vez** — hecho.
  `scripts/resources/tutorial_hint.gd` + `tutorial_hint_catalog.gd` +
  `scripts/autoload/tutorial_hint_manager.gd`, con tests verdes
  (`test_hints_never_overlap_on_screen`,
  `test_a_hint_shows_the_currently_bound_key`,
  `test_clearing_tutorial_hints_forgets_everything`).

### Tanda C — VFX y game feel

- **C1. Impact VFX y decals por material** — hecho.
  `impact_effect.gd` resuelve el material con `SurfaceMaterials.resolve()` y de
  ahí saca decal, color de chispa y sonido. Nota honesta: el propio script se
  declara *"grey-box first pass — the particle/decal art"*, así que el sistema
  está y el arte final no.
- **C2. Números de daño flotantes** — hecho, con toggle y con perf.
  `damage_number.gd`, `damage_number_spawner.gd`, `damage_indicators.gd`, dos
  tests unitarios, y el commit `05304d5` que bajó su costo de 66% a 16% del
  frame.
- **C3. Transiciones de escena** — hecho.
  `assets/shaders/scene_change.gdshader` + `tests/unit/test_scene_transition.gd`
  y `test_loading_screen.gd`.
- **C4. Speed lines** — hecho.
  `assets/shaders/speed_lines.gdshader` + `test_speed_lines_overlay.gd`.

### Tanda E — Audio

- **E1. Música** — hecho. `assets/audio/music/` con `menu`, `combat` y `shop`, y
  `tests/unit/test_music_manager.gd` verde.
- **E2. Voice packs del presentador** — hecho. `data/host/presenters.tres` junto
  al `host_catalog.tres`, que es la selección de pack que pedía el plan.
- **E3. Mezcla y buses** — hecho. `default_bus_layout.tres` tiene exactamente el
  árbol especificado: `Weapons`, `Impacts`, `Enemies`, `World`, `Music`, `VO`,
  `UI`. Hay tool dedicado (`tools/configure_audio_mix.gd`).

### Tanda G — Ship

- **G1. Export pipeline** — hecho. `docs/EXPORT.md`, `export_presets.cfg`, y
  `builds/release/` existente.
- **G2. Profiling de 60 FPS en ola elite** — hecho y **medido**.
  [PLAN_PERFORMANCE.md](PLAN_PERFORMANCE.md) tiene la corrida real (wave_10, 27
  enemigos, 20s, d3d12 @1080p): 655/716/761 FPS min/avg/max, 0% de frames bajo
  60. El objetivo se cumple con ~10x de margen; la optimización igual ganó +45%
  en el frame peor (453 → 655), que es el número que va a importar en una
  máquina más lenta.

### Deudas técnicas que el plan listaba en G6 — ya cerradas

- **Cobertura faltante**: `StatsComponent`, `GameManager` y `AudioPool` **ya
  tienen** test unitario (`test_stats_component.gd`, `test_game_manager.gd`,
  `test_audio_pool.gd`). Era la deuda de cobertura más crítica y no está más.
- **Menú principal placeholder**: rehecho. `main_menu.gd` ya no es `Control` +
  `Button` planos; documenta su propio pase visual y reusa las mismas escenas de
  settings que el menú de pausa.

---

## 3. Abiertas

### D1. Rediseño y vestido de la arena — **abierta, es el bloqueo grande**

La arena sigue siendo greybox: `scenes/arena/greybox_arena.tscn` es la escena
viva. Hay trabajo de arte empezado — `assets/Arena/Arena.blend` está en el repo —
pero no llegó al juego. XL, y bloquea a D2, a G3 (playtest) y a G8 (trailer).

### D2. Lighting pass — **abierta, depende de D1**

`greybox_arena.tscn` tiene un `DirectionalLight3D` y un `WorldEnvironment`, nada
más: cero luces de área, cero GI. Las únicas `OmniLight3D` del proyecto están en
`ammo_pickup` y `spawn_door`.

### F1. Modelos de enemigos — **parcial, 4 de 8**

Cambió mucho desde el plan: el commit `86a68dd` ("el Bomber, el Ranger y el
Flyer dejan de ser primitivas") sacó a tres arquetipos de la cápsula. Estado real
por `.tres`:

| Con modelo | Todavía cápsula |
|---|---|
| `rusher`, `bomber`, `ranger`, `flyer` | `elite`, `environmental`, `healer`, `summoner` |

Los `.blend`/`.fbx` fuente ya están en `assets/models/enemies/` (Bomber, Elite,
Enviromental, Melee, Ranged, RangedFlyer), así que para Elite y Environmental
falta el bake + el `model_scene` en el `.tres`, no el modelado. Healer y Summoner
no tienen fuente.

### G3–G9. Playtests, balance, bugs, trailer, build, case study — **abiertas**

No arrancaron, y es correcto que no lo hayan hecho: G3 (playtest ronda 1) exige
la arena vestida. La cadena queda: **D1 → D2 → G3 → G4 (balance) → G5 → G6 →
G7/G8/G9**.

### P3 opcionales — **no arrancadas**

- **Gamepad**: `project.godot` no tiene una sola entrada de joypad. Sin empezar.
- **Crowd reactivo**: hay `arenastands.tscn` (las gradas físicas, del commit
  `7722071`), pero ningún script de espectadores.

---

## 4. Lo que apareció y no estaba en el backlog

Trabajo real hecho después del 2026-08-10 que Notion no tiene registrado:

- **Rama de nuevos enemigos, casi entera.** Bomber, Environmental (los dos
  frascos), Ranged Flyer, rumbos de aproximación por arquetipo, atribución de
  muertes, prioridad de voces y la abstracción objetivo+facciones. Según
  [PLAN_NEW_ENEMY_TYPES.md](PLAN_NEW_ENEMY_TYPES.md) lo único que queda de ese
  plan son los **Gladiadores**, en su propia rama.
- **Dos fixes de navmesh** (`2e7f39e`, `8b51960`): un enemigo ya no camina donde
  no hay navmesh ni aparece en una isla sin salida.
- **Remoción completa del multijugador** (`95f563c`). El juego volvió a ser
  solo-un-jugador y el backlog de Notion debería dejar de tener tareas de red.
- **Packs de VFX** (`ae71de0`): flipbooks, partículas y sprites predibujados en
  `assets/flipbooks/`, `assets/particles/`, `assets/predrawn/`. Entraron crudos y
  **ya están aplicados en los tres efectos que estaban sin textura** — ver §6.
- **Tarea nueva sugerida:** *"HUD: la ranura del gancho nombra su tecla real"* —
  está en el árbol sin commitear, ver §5.

---

## 5. Estado del árbol de trabajo — suite en verde

**577 de 577 tests pasan.** Había 3 en rojo; los dos problemas de fondo eran
distintos y están arreglados:

1. **Los dos tests de `test_enemy_models.gd`** usaban `ranger` como "el arquetipo
   sin modelo", y el Ranger recibió el suyo en `86a68dd`. Eran tests que
   caducaban con el arte. Ahora **eligen el arquetipo desde los datos**
   (`_capsule_archetype()` busca el primer `.tres` sin `model_scene`), así que
   siguen a la tanda F en vez de fecharse contra ella. Si algún día todos tienen
   modelo, pasan por `pass_test()` en lugar de mentir: el camino de la cápsula
   tiene que seguir funcionando para el próximo que alguien grey-boxee, pero no
   quedaría nada shipeado con qué probarlo.
2. **`test_ads_sensitivity_scales_off_the_same_base`** era un problema de
   aislamiento, no de código de juego. `SettingsManager` es un autoload que al
   arrancar carga el `user://settings.cfg` **de la máquina que corre la suite**;
   este equipo tenía `ads_sensitivity_multiplier=2.0` guardado, que es una
   posición legal del slider (la pantalla de settings llega a 2.0 a propósito).
   El test seteaba la sensibilidad de cadera pero no el multiplicador, así que
   medía la preferencia del dev.

   El arreglo: `before_each` pone en su default toda clave que el test lea, y
   `after_each` le devuelve a la máquina sus propios settings. Además se separó
   el assert de *"apuntar frena la mirada"* a su propio test, porque es una
   afirmación sobre **el default que shipeamos**, no un invariante de la
   perilla — el jugador tiene derecho a subirla más allá de 1.0.

⚠ **Queda una deuda relacionada, sin cerrar:** cualquier otro test que lea
`SettingsManager` sigue expuesto al `settings.cfg` local. Los dos que había están
cubiertos, pero conviene la regla general *"seteá lo que leas"* al escribir tests
nuevos. Es de la misma familia que el flaky de navmesh que G6 ya tenía anotado.

**Cambios sin commitear en el árbol**, todos coherentes entre sí:

- **El Bomber vuelve a armar la espoleta mientras flanquea.** Se revirtió el
  commit a `fuse_arm_range`: el costo era que los últimos 6m —toda la parte
  visible de la aproximación— venían de frente y el Bomber se leía como un
  Rusher lento. `approach_bearing_weight` sube de 0.85 a 1.0. Los tests y la
  documentación de `05 Enemies and AI.md` acompañan el cambio, con el
  razonamiento de por qué se probó al revés.
- **El HUD lee el `InputMap`** para la ranura del gancho, así que un rebind ya no
  la deja mintiendo ("E GRAPPLE" en vez de "GRAPPLE" fijo).

**Corrupción de tabs en los markdown — corregida.** El diff de `docs/*.md` había
convertido sangrías de espacios a **tabs** en listas anidadas y dentro de bloques
de código: 64 líneas en `PLAN_BACKLOG_RESTANTE.md`, y unas pocas en `PHASE_2.md`,
`PLAN_NEW_ENEMY_TYPES.md` y `PLAN_PERFORMANCE.md`. Parecía un *"convertir
indentación a tabs"* del editor aplicado sobre markdown por la convención de tabs
de GDScript, y en markdown eso rompe el anidado de listas.

Se verificó con `git diff -w` que en esos cuatro archivos **no había ningún
cambio de contenido** —eran whitespace y nada más— antes de restaurarlos desde
`HEAD`. `05 Enemies and AI.md`, que sí tenía contenido real (el razonamiento del
Bomber), quedó intacto.

> Vale revisar la config del editor: si convierte indentación a tabs por
> proyecto, va a volver a pasar en cada `.md` que se toque.

---

## 6. Los packs de VFX, aplicados

Los tres efectos que estaban dibujados como quads sin textura ahora usan el pack.
Ninguno cambió de comportamiento: sólo dejaron de ser primitivas.

| Efecto | Antes | Ahora |
|---|---|---|
| Impacto de bala | quad naranja liso de 3cm | `particles/alpha/spark_01_a.png` |
| Muzzle flash | quad naranja liso | `particles/alpha/muzzle_01_a.png`, aditivo |
| Explosión del Bomber | esfera lisa | esfera **+** flipbook `predrawn/explosion_6x5.png` |

Tres decisiones que vale dejar escritas:

- **La esfera de la explosión no se reemplazó, se le sumó el fuego encima.** La
  esfera es la ley del arquetipo: crece hasta `explosion_radius` y hasta ahí,
  porque es de donde el jugador aprende cuánto abarca la próxima. Un billboard no
  puede sostener esa promesa —se ve del mismo tamaño desde cualquier distancia y
  no tiene volumen que leer—. Así que el arte se suma y la medida se queda. El
  flipbook sale 20% más ancho que la esfera a propósito: el fuego se desborda del
  volumen que hace daño, y el borde que importa sigue siendo el de la esfera.
- **El impacto lleva `spark`, no el flipbook de puff.** El sistema de partículas
  ya tenía velocidad 2-5 m/s, gravedad y damping: eso es movimiento de chispa. La
  textura acompaña el movimiento que ya estaba diseñado en vez de pelearse con
  él. Sigue tiñéndose por superficie — `impact_effect.gd` escribe
  `albedo_color` desde `SurfaceMaterialData.accent_color`, y sobre un sprite
  blanco eso multiplica bien.
- **`HazardZone` y `SnareZone` se dejaron como estaban.** Tienen shader de lava
  propio (`lava_pool.gdshader`) manejado por `TelegraphComponent`; cambiarlos por
  un anillo del pack sería cambiar arte hecho a medida por arte genérico, y
  además rompería la telegrafía. No todo lugar donde entra una textura es un
  lugar donde corresponde.

**Lo que sigue sin usarse del pack:** los flipbooks `.tga` de humo, fuego y nubes,
y la mayor parte de `particles/`. Son el material para el pase de VFX de la arena
(D1) y para el humo residual de la explosión — trabajo de arte, con la arena
vestida, no ahora.
