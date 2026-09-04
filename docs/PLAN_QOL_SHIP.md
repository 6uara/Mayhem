---
tags: [mayhem, plan, qol, ship]
---

# MAYHEM — Plan de QoL y cierre para Steam

Seis puntos levantados el 2026-09-04 sobre `develop` @ `2f95707`. Escrito para
ejecutarse tarea por tarea. Valen las reglas de
[PLAN_BACKLOG_RESTANTE.md](PLAN_BACKLOG_RESTANTE.md) §0 (tipado estricto,
datos en `.tres`, señales en `EventBus`, audio por `AudioPool`, tests con
`tools/run_tests.ps1`).

> **Estado: los seis puntos estan implementados** (2026-09-04, sobre `develop`).
> Suite completa en verde: 840 tests, 0 rojos. Lo que se hizo distinto de lo
> planeado esta anotado al final, en "Desvios".

Orden sugerido: **1 → 3 → 2 → 4 → 5 → 6**. El grapple es el que más cambia la
sensación del juego, y la arena fija hay que hacerla antes de vestir las
plataformas para no iluminar geometría que después se re-autora.

---

## 1. Grapple: apuntado más permisivo + mejoras de shop

### Estado actual

[grapple_component.gd](../scripts/components/grapple_component.gd) resuelve el
apuntado con **un solo raycast** desde `aim_node` (`_find_anchor()`): o el
centro exacto de la retícula toca el collider del ancla, o no hay grapple. Cero
tolerancia angular — de ahí que se sienta duro.

Ya existen dos stats y sus upgrades: `grapple_range` (Long Line, ×1.25, 2
stacks) y **`grapple_cooldown` (Fast Winch, ×0.75, 2 stacks — la mejora de
cooldown que pedías ya está implementada y en el catálogo)**. Lo que falta es la
de apuntado, y decidir si Fast Winch se queda como está.

### Qué construir

**1.1 — Asistencia angular en `_find_anchor()`.**
Mantener el raycast como primera pasada (si pega directo, gana). Si falla,
segunda pasada por el grupo `&"grapple_anchor"` (ya lo puebla
[grapple_anchor.gd](../scripts/systems/grapple_anchor.gd) en `_ready`):

- descartar anclas fuera de `get_max_range()`;
- descartar las que estén detrás (`dot` con el forward del `aim_node` ≤ 0);
- calcular el ángulo entre el forward y la dirección al ancla, descartar las que
  superen `get_aim_assist_degrees()`;
- de las que quedan, elegir el **menor ángulo** (no la más cercana: lo que el
  jugador está mirando, no lo que tiene al lado);
- confirmar línea de vista con un raycast contra `PhysicsLayers.WORLD` — la
  asistencia no puede grapplear a través de paredes, que es la garantía que hoy
  da el raycast único y no se puede perder.

Devolver un `Dictionary` con la misma forma que `intersect_ray` (`position`,
`collider`) para no tocar `try_fire()`.

**1.2 — Stat nuevo `grapple_aim_assist`.**
`StatsComponent.GRAPPLE_AIM_ASSIST: StringName = &"grapple_aim_assist"`.
Export `aim_assist_degrees: float = 4.0` en el componente (arranque
conservador: "un poco más permisivo, no por mucho") y
`get_aim_assist_degrees()` con el mismo patrón que `get_cooldown()` /
`get_max_range()`.

**1.3 — Upgrade nueva `data/upgrades/grapple_aim_assist.tres`.**
`display_name = "Magnet Hook"`, multiplicador `1.6`, `max_stacks = 2`
(4° → 6.4° → 10.2°), categoría movilidad, `cost ≈ 180`. Agregarla al array
`upgrades` de [shop_catalog.tres](../data/economy/shop_catalog.tres).

**1.4 — Cooldown.** Fast Winch ya existe. Decisión de balance: subirla a
`max_stacks = 3` (×0.42 acumulado sobre 5s → ~2.1s) o dejarla en 2. Recomiendo
dejarla en 2 y medirlo en playtest, porque el cooldown ya es diferido por
`_tick_chain_debt()` y encadenando casi nunca se paga.

### Tests

Nuevo caso sobre `_find_anchor`: ancla apenas fuera del rayo pero dentro del
cono ⇒ engancha; la misma ancla con una pared en el medio ⇒ no engancha; ancla a
30° ⇒ no engancha; dos anclas en el cono ⇒ gana la de menor ángulo. Verificar
que con `stats == null` el componente sigue usando el export (los stubs de test
no tienen `StatsComponent`).

### Cerrada cuando

Se puede enganchar un ancla con la retícula levemente afuera, no se puede a
través de una pared, y comprar Magnet Hook ensancha el cono de forma
perceptible.

---

## 2. Visibilidad de las plataformas en la ambientación nocturna

### Estado actual

Las plataformas (`platform_2x2`, `catwalk_1x3`, `floor_*`) no tienen `scene`:
[piece_mesh_builder.gd](../addons/mayhem_tools/arena_editor/core/piece_mesh_builder.gd)
les arma un `BoxMesh` con `StandardMaterial3D` y `albedo_color = greybox_color`
(`0.45, 0.55, 0.62` — gris azulado, mate).
[coliseum_env.tres](../data/arena_themes/coliseum_env.tres) da ambiente `0.85` y
sol `0.35`: un albedo mate a esa luz es exactamente lo que desaparece. **El
problema no es falta de luz, es falta de contraste y de borde.**

### Qué construir — en este orden, midiendo después de cada paso

**2.1 — Borde emisivo en la definición de pieza (sin costo de luces).**
Agregar a `PieceDefinition`: `edge_color: Color` y `edge_energy: float = 0.0`.
En `build_greybox()`, cuando `edge_energy > 0`, agregar por celda un marco
delgado (4 `BoxMesh` finos en el perímetro superior, o un `QuadMesh` con
material unshaded) con `emission_enabled` y `emission_energy = edge_energy`. Es
geometría emisiva: la agarra el glow del environment (ya está en `1.1`) y no
cuesta una sola luz. Cyan/magenta del token cyberpunk que ya usa el coliseo,
para que lea como parte de la ambientación y no como un debug overlay.

**2.2 — Subir el contraste del albedo de las piezas transitables.**
Las plataformas van más claras y con `roughness` más baja (highlight especular
del sol y de las luces del coliseo); el piso base va más oscuro. La lectura
"esto se pisa / esto es fondo" tiene que venir del valor, no del color.

**2.3 — Luces, sólo si 2.1 + 2.2 no alcanzan.**
Una `OmniLight3D` sin sombras (`shadow_enabled = false`, `omni_range` ~4m) por
plataforma, apuntada hacia abajo desde el borde. **Techo duro: presupuesto de
luces.** Hoy sólo llevan `OmniLight3D` los pickups, las puertas de spawn y los
proyectiles, todas sin sombra — hay que contar cuántas plataformas tiene la
arena de 32×32 antes de comprometerse, y cruzarlo con
[PLAN_PERFORMANCE.md](PLAN_PERFORMANCE.md). Si el conteo pasa de ~30, se
resuelve con emisión y no con luces.

### Cerrada cuando

En una captura de la arena de noche se distingue el borde de cada plataforma a
20m sin subir el brillo del monitor, y el frametime no se movió respecto de la
medición de PLAN_PERFORMANCE.

---

## 3. Arena fija en el tamaño grande (32×8×32)

### Estado actual

`ArenaData.SIZE_PRESETS` ofrece Small 16, Medium 24 y Large 32.
[default_arena.tres](../data/arenas/default_arena.tres) está autorada en
`24×8×24`. El editor expone el selector en
[editor_dock.gd](../addons/mayhem_tools/arena_editor/ui/editor_dock.gd) y en
[arena_editor_hud.gd](../scripts/ui/arena_editor_hud.gd).

### Qué construir

**3.1 — Un solo preset.** Dejar `SIZE_PRESETS` con `"Large  32x8x32"` como única
entrada, y `grid_size` con default `Vector3i(32, 8, 32)`. Sacar el selector del
dock y del HUD del editor (o dejarlo deshabilitado mostrando el tamaño fijo —
más barato y menos código muerto que borrarlo entero).
`ArenaSession.new_arena()` pasa a defaultear a 32.

**3.2 — Migración.** `ArenaData.from_dict()` fuerza `grid_size` a 32 para
cualquier arena guardada con formato viejo, así las arenas que el jugador ya
construyó siguen cargando. Bump de `CURRENT_FORMAT_VERSION` si la migración lo
amerita.

**3.3 — Re-autorar `default_arena.tres` a 32×32.** Decidido: la arena tiene que
sentirse más grande, no tener 8 celdas de vacío. Concretamente:

- extender el piso al perímetro nuevo;
- recolocar `player_spawn` y los 7 `enemy_spawns` al nuevo borde/centro;
- agregar plataformas, anclas de grapple y cobertura en el anillo nuevo — el
  anillo exterior es justo donde el grapple encadenado tiene sentido, así que
  las anclas nuevas son parte del punto 1;
- rebalancear las alturas para que el nivel 2 siga siendo alcanzable.

Hacerlo **en el editor de arenas del proyecto**, no editando el `.tres` a mano.

**3.4 — Verificar lo que depende del tamaño.** El shell/gradas usa
`get_content_bounds()`, así que se re-enmarca solo; confirmarlo igual. Rebakear
navegación y correr una wave completa: `AGENT_RADIUS`, los `jump_link` y los
caminos de los flyers se tienen que revalidar sobre la planta nueva.

### Cerrada cuando

No hay forma de crear una arena que no sea 32×8×32, `default_arena` llena la
grilla, el navmesh bakea sin islas y una run de 10 waves corre sin enemigos
atascados.

---

## 4. Leaderboard local con nombre de jugador

### Estado actual

[save_manager.gd](../scripts/autoload/save_manager.gd) ya persiste hasta 10
entradas en `user://leaderboard.json` (`score`, `time`, `waves`, `date`), y
[leaderboard_panel.gd](../scripts/ui/leaderboard_panel.gd) las muestra desde el
menú. [match_director.gd:146](../scripts/systems/match_director.gd#L146) llama a
`submit_score()` automáticamente al terminar la run. **Falta el jugador: no hay
nombres, y el submit es silencioso.**

Decidido: **queda local** (sin Steam, sin backend), con perfiles de nombre.

### Qué construir

**4.1 — Nombre en la entrada.** Agregar `"name": String` al dict de
`submit_score()`. Migración al cargar: entradas viejas sin `name` toman
`"PLAYER"`, para no perder los scores existentes.

**4.2 — Registro de nombres conocidos.** `user://profiles.json` (archivo aparte,
mismo criterio que ya separa leaderboard de tutorial): lista de nombres usados,
más `last_used`. API en `SaveManager`: `get_profiles()`,
`remember_profile(name)`, `get_last_profile()`.

**4.3 — Prompt al final de la run.** `MatchDirector` deja de llamar a
`submit_score()` directo; emite el resultado y el overlay de fin
([match_overlay.gd](../scripts/ui/match_overlay.gd), `_show_end()`) abre un
panel nuevo `ScoreEntryPanel`:

- si hay nombres registrados, lista para elegir con el último preseleccionado,
  más un botón "Nuevo nombre";
- si no hay ninguno, campo de texto directo;
- validación: 3–12 caracteres, alfanuméricos y espacio, trim;
- "Guardar" persiste; "Saltar" guarda igual como `PLAYER` (un score perdido
  molesta más que una fila anónima).

**4.4 — Columna NAME en el panel.** `COLUMNS` y `WEIGHTS` en
`leaderboard_panel.gd` pasan a `["#", "NAME", "SCORE", "WAVES", "TIME",
"DATE"]`. Resaltar la fila recién ingresada cuando el panel se abre desde el fin
de run.

**4.5 — Subir el tope.** `MAX_ENTRIES` de 10 a 20: con varios nombres en una
misma máquina, 10 filas se llenan con un solo jugador bueno.

### Tests

`submit_score` con nombre ordena y trunca bien; una entrada legacy sin `name` se
carga sin romper; `remember_profile` no duplica; nombre inválido se rechaza.

### Nota para más adelante

Si en algún momento se quiere ranking global, el camino natural con el target
Steam es Steam Leaderboards vía GodotSteam: `submit_score()` queda como el único
punto de entrada, así que sumar un backend después es agregarle una llamada, no
rehacer el sistema.

---

## 5. Créditos en el menú

### Estado actual

[main_menu.gd](../scripts/ui/main_menu.gd) tiene Play / Create Arena /
Leaderboard / Options / Quit, y un `Footer` con versión y copyright. Los paneles
(`Settings`, `Leaderboard`, `ArenaSelect`) siguen todos el mismo patrón: escena
instanciada como hijo, `open()` / `closed`, `_root.visible = false`.
[THIRD_PARTY.md](../THIRD_PARTY.md) ya tiene el material de atribución.

### Qué construir

**5.1 —** `scenes/ui/credits_panel.tscn` + `scripts/ui/credits_panel.gd`,
copiando la estructura de `leaderboard_panel` (mismo `open()`/`close()`/
`closed`, mismo manejo de `ui_cancel`, `PROCESS_MODE_ALWAYS`).

**5.2 — Contenido generado desde datos**, no texto autorado en el `.tscn`: una
constante `SECTIONS` (igual que el `SCHEMA` de `settings_screen`) con autoría,
herramientas (Godot, Beehave, GUT, phantom_camera, debug_draw), fuentes (IBM
Plex, Archivo), audio y assets de terceros. Así se mantiene sincronizado con
`THIRD_PARTY.md` y es una línea agregar una atribución.

**5.3 —** Botón "CREDITS" en `Root/Panel/Margin/Layout`, entre Options y Quit, y
el wiring en `main_menu.gd` idéntico al de leaderboard.

**5.4 — Licencias.** Chequear que cada dependencia con licencia que exige
atribución (MIT/CC-BY) esté nombrada. Es requisito de la página de Steam, no
sólo cortesía.

### Cerrada cuando

El panel abre y cierra con teclado y gamepad, no deja el foco perdido, y lista
todo lo de `THIRD_PARTY.md`.

---

## 6. Formulario de feedback

Decidido: **guardado local + copiar al portapapeles + abrir un form web**. Cero
infraestructura, funciona offline, y no manda nada sin que el jugador lo decida.

### Qué construir

**6.1 —** `scripts/autoload/feedback_manager.gd` (autoload) que escribe a
`user://feedback/feedback_<timestamp>.json`:

- texto del jugador;
- categoría (Bug / Balance / Idea / Otro);
- contexto automático: versión de `application/config/version`, arena de la run,
  wave alcanzada, score, tiempo de sesión, OS, resolución, GPU
  (`RenderingServer.get_video_adapter_name()`), FPS promedio.

El contexto automático es lo que hace útil un reporte; escrito a mano nunca
llega.

**6.2 —** `scenes/ui/feedback_panel.tscn` + script, mismo patrón `open()` /
`closed` que los demás. `TextEdit` para el cuerpo, `OptionButton` para la
categoría, y tres acciones:

- **Guardar** — escribe el archivo y confirma en pantalla la ruta;
- **Copiar** — `DisplayServer.clipboard_set()` con el texto + el contexto
  formateado en markdown, listo para pegar;
- **Abrir formulario** — `OS.shell_open()` a un Google Form (URL en un `.tres`
  de config, no hardcodeada, para poder cambiarla sin recompilar).

**6.3 — Puntos de entrada:** botón en el menú principal y en el pause menu
([pause_menu.gd](../scripts/ui/pause_menu.gd)) — el momento en que algo molesta
es durante la run, no en el menú.

**6.4 — Privacidad.** Una línea en el panel diciendo exactamente qué se incluye
y que nada se envía solo. Es lo correcto y además evita un problema con la
política de datos de Steam.

### Cerrada cuando

Se puede reportar desde el pause menu, el archivo aparece en `user://feedback/`
con el contexto completo, y el botón de copiar deja algo pegable en un issue.

---

## Resumen de archivos por tarea

| # | Toca |
|---|---|
| 1 | `grapple_component.gd`, `stats_component.gd`, `data/upgrades/grapple_aim_assist.tres` (nuevo), `shop_catalog.tres`, tests |
| 2 | `piece_definition.gd`, `piece_mesh_builder.gd`, `data/arena_pieces/*.tres` |
| 3 | `arena_data.gd`, `editor_dock.gd`, `arena_editor_hud.gd`, `arena_session.gd`, `default_arena.tres` |
| 4 | `save_manager.gd`, `match_director.gd`, `match_overlay.gd`, `leaderboard_panel.gd`, `score_entry_panel` (nuevo), tests |
| 5 | `credits_panel` (nuevo), `main_menu.gd`, `main_menu.tscn` |
| 6 | `feedback_manager.gd` (nuevo, autoload), `feedback_panel` (nuevo), `main_menu.gd`, `pause_menu.gd`, `project.godot` |

---

## Desvios respecto del plan

Tres cosas salieron distintas de lo escrito arriba. Ninguna cambia el objetivo
del punto, pero conviene tenerlas anotadas.

**1. La arena se re-autoro por script, no en el editor.** El editor de arenas es
una GUI y esto se hizo headless. En vez de editar 2700 lineas de `.tres` a mano,
se reescribio [tools/make_default_arena.gd](../tools/make_default_arena.gd), que
es el script que habia generado la arena original y que estaba desactualizado
respecto del `.tres` commiteado. Ahora la arena vuelve a ser reproducible:
`godot --headless --path . -s tools/make_default_arena.gd`. Valida sin un solo
error ni warning, y sale con 300 piezas, 1311 celdas caminables y 8 nav links.

**Numero a mirar en el playtest:** el piso paso de 72m a **128m** de lado, 3,2
veces el area anterior. Es lo que significaba "llenar la grilla", pero es mucho.
Si se siente vacia, la perilla es `FLOOR` en ese script: bajarlo a 24 deja una
arena de 96m sin tocar nada mas.

**2. El piso ya no son `floor_1x1`.** 32x32 celdas en piezas de 1x1 son 1024
StaticBody con su malla. Se paso a bloques `floor_3x3` con tiras de `floor_2x2`:
mismo piso, 131 piezas.

**3. Morir ahora tambien deja puntaje.** No estaba en el plan, pero un
leaderboard que solo anota las runs en que te pasaste las diez waves esta vacio
para siempre, y eso no es "funcional" en ningun sentido util. `MatchDirector`
emite `EventBus.run_finished(score, time, waves, victory)` en las dos salidas, y
lo que se anota son las waves efectivamente limpiadas. `match_completed` sigue
significando lo mismo que antes para el Host y la musica.

**Ademas:** `Tokens.LEADERBOARD_ENTRIES` paso de 10 a 20 (con su linea en
`docs/Mayhem/09 Design Tokens and Color Law.md`), porque el test de conformidad
al spec compara contra ese token y subir el tope sin tocarlo hubiera sido
romperlo en silencio.

---

## Lo que quedo abierto

- **La URL del formulario de feedback esta vacia.** Hasta que haya un Google
  Form (o lo que sea) al que mandar gente, el boton "Open form" no aparece.
  Encenderlo es escribir la URL en
  [data/feedback/feedback_config.tres](../data/feedback/feedback_config.tres):
  no hace falta tocar codigo ni volver a exportar.
- **`Fast Winch` sigue en 2 stacks.** La decision de balance del punto 1.4 quedo
  para despues del playtest.
- **El punto 2.3 (luces) no se hizo, y probablemente no haga falta.** Se hizo
  2.1 (filete emisivo) y 2.2 (contraste de albedo y rugosidad en lo elevado),
  ambos a costo cero de luces. Mirar la arena de noche antes de agregar una sola
  `OmniLight3D`.
- **El OFL sigue sin su texto junto a las fuentes**, como ya avisaba
  THIRD_PARTY.md. Los creditos nombran la licencia, que es necesario pero no
  suficiente para publicar.
