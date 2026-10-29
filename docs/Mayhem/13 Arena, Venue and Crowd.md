---
tags: [mayhem, arena, venue, crowd, host]
estado: referencia
actualizado: 2026-10-28
---

# Arena, Venue and Crowd

Lo que rodea a la pelea: de dónde sale la arena, el coliseo que la encierra, el
público que la mira y el Host que la narra. Hasta esta nota, todo esto estaba
documentado sólo en planes ya cerrados
([PLAN_COLISEO](../historial/PLAN_COLISEO.md),
[PLAN_CROWD_DROPS](../historial/PLAN_CROWD_DROPS.md),
[PLAN_QOL_SHIP](../historial/PLAN_QOL_SHIP.md)); acá queda el estado actual, y
los planes guardan el porqué.

## La arena es un archivo

`game.tscn` no lleva arena adentro. `ArenaHost` (`scripts/systems/arena_host.gd`)
carga un `ArenaData` en este orden de precedencia:

1. La arena que se está probando desde el editor in-game.
2. La elegida en la pantalla de Play.
3. La que el botón Play del dock de Godot escribió en project settings.
4. `data/arenas/default_arena.tres`.

`ArenaLoader` (`addons/mayhem_tools/arena_editor/runtime/arena_loader.gd`) es la
única superficie de contacto entre editor y juego: instancia piezas, puertas de
spawn y navegación.

- **Grilla:** celdas de **4 × 3 × 4 m** (`PieceCatalog.cell_size`), tamaño fijo
  **32 × 8 × 32** celdas (`ArenaData.FIXED_SIZE`) → 128 m de lado.
- **Lotes:** al cargar, `ArenaGeometryBatcher` junta las cajas greybox y el arte de las piezas en un
  `MultiMeshInstance3D` por malla+material (bajo `BatchedGeometry`). Cada pieza
  sigue siendo su nodo con su colision.
- **Catálogo:** 21 piezas en `data/arena_pieces/` (`default_catalog.tres`),
  categorías `FLOOR / RAMP / WALL / PLATFORM / PROP`. Una pieza con `scene`
  instancia esa escena (los interactuables: pad, munición, ancla…). El resto se
  arma en `piece_mesh_builder.gd` desde `footprint`, con el filete emisivo
  `edge_color`/`edge_energy` que las hace legibles de noche, y de dos maneras:
  - **Con arte** (`art_scene`): pisos, plataformas, cobertura baja y pared 1x1
    (una copia por celda), la pared 2x1 y
    la pasarela (`art_per_cell = false`, una sola estirada), las rampas, el pilar
    y la esquina.
    El arte se estira sobre la misma caja que usa la colisión greybox, así que el
    navmesh no cambia. Las excepciones son las rampas y la esquina, que chocan con
    la malla de su modelo entero (`art_collision`), barandas y base incluidas; las
    rampas además no llevan filete (`art_ramp_collision`). Antes las rampas
    chocaban como una cuña, y quedaban partes del modelo que se atravesaban.
    La esquina va dentro de su propia caja (`art_bounds`). Los `.glb` salen de
    `tools/blender/build_props.py`. Las piezas de arena salen normalizadas a una
    celda y la baldosa se hornea sobre una caja de 54 caras, porque va unas mil
    veces en la arena por defecto. El piso mezcla tres variantes de la baldosa
    (rota, con circuitos, con rejilla; `art_variants`) en un 30 % de las celdas
    (`art_variant_chance`), giradas un cuarto de vuelta al azar. Cuál va en cada
    celda sale de un hash de la celda, así que la arena se ve igual en cada carga
    y en el editor.
  - **Greybox** (`greybox_color`): lo que no tenga modelo (hoy, ninguna pieza
    del catálogo sin escena).
- **Props con modelo** (los fuentes de Meshy en `assets/models/props/`, con
  `importer="skip"`): la caja de munición, el bounce pad, la puerta de spawn, el
  gancho del ancla de grapple, la plataforma móvil (las flechas marcan su
  recorrido) y
  la pantalla del coliseo (`ArenaColiseum.jumbotron_scene`, colgada bajo el
  óculo, sin colisión). Munición y pad conservan su textura: el color de la ley
  lo llevan sus franjas, su luz y el anillo de abajo, en vez de pintarlos
  enteros. La luz de la munición va por encima de la caja (dentro del modelo
  iluminaba el piso y dejaba la caja a oscuras) y el anillo del pad es más ancho
  que las esquinas del modelo, para que se lea como un halo entero y no como
  medias lunas asomando por los costados. Los modelos se decimaban con las costuras
  de UV abiertas y salían agrietados: `build_props.py` suelda antes de decimar
  y rehornea el mapa de normales sobre la malla decimada, y
  `build_enemy_models.py` también suelda. El ancla y la plataforma pasan por
  `TelegraphComponent`, que pinta cada malla de un color plano y sin luz; con
  `overlay` el color va encima de la textura como un brillo aditivo
  (`overlay_strength`, 0.1: más alto, el glow lavaba el modelo a cyan liso).
  El jump link sigue invisible a propósito: es una ayuda de navegación para los
  enemigos (ver `jump_link.gd`).
- **Topes por pieza** (`max_instances`): los interactuables tienen techo para que
  una arena no deje de ser legible (6 bounce pads, 12 anclas, 4 zip lines…).
- **Navegación:** dos sistemas con roles separados — grilla + A* para el editor,
  navmesh horneado en runtime para los enemigos. Ver
  [DECISION_navegacion_arenas](../decisiones/DECISION_navegacion_arenas.md).
- **Arena por defecto:** generada por `tools/make_default_arena.gd` (headless,
  reproducible): ~300 piezas, piso de bloques `floor_3x3`.

Editor: in-game (botón CREAR ARENA, ver [DEV_TOOLS](../DEV_TOOLS.md)) y dock de
Godot (ver [`addons/mayhem_tools/README.md`](../../addons/mayhem_tools/README.md)).

## El venue: shells y temas

Un `ArenaTheme` (`data/arena_themes/*.tres`) junta un *shell* (lo que rodea a la
arena), un `Environment` y el sol. Hay tres shells en `scenes/arena/shells/`:

| Tema | Shell | Qué es |
|---|---|---|
| `coliseum` | `ArenaColiseum` | **El que se usa.** Coliseo ovalado generado por código |
| `tiled` | `ArenaTiledShell` | Gradas armadas repitiendo un tramo recto y una esquina (modelos `assets/models/arena/`) |
| `default` | `ArenaShell` | El primero: un modelo de gradas escalado |

### ArenaColiseum

`scripts/systems/arena_coliseum.gd`. Planta de superelipse (`oval_exponent`)
alrededor de la arena rectangular, foso (`pit_margin`), muro podio de 6 m, tres
anillos de gradas. **Una sola malla, sin colisión**: el jugador no puede llegar,
y los asientos salen de `get_seat_rows()` — el mismo código que hace el escalón
sabe dónde sentar a cada espectador. Material: `arena_glitch_panel.gdshader`.

**Luz** (`coliseum.tres` y `coliseum_env.tres`): luna a 1.1, ambiente 1.8 y
exposición 1.25. Era luna a 0.35 y ambiente 0.85, pensado para cajas greybox
claras; con las texturas oscuras de los modelos la arena quedaba casi negra.
El cielo sigue de noche: lo que sube es la luz sobre las piezas.

### EnergyWall

`scripts/systems/energy_wall.gd` + `energy_wall.gdshader`. El límite visible. La
colisión siguen siendo cuatro cajas del shell; la pared **contesta**: cuando el
jugador pasa cerca de un plano (medido por distancia, no por física) se abre una
onda desde ese punto. Hasta 8 ondas simultáneas (`MAX_IMPACTS`).

### ArenaRoof

`scripts/systems/arena_roof.gd`. Anillo estructural, vigas y óculo abierto
(`oculus_share`). Existe por una razón de juego: con gancho, picadas, pads y zip
lines, un techo abierto obliga a decidir qué pasa cuando alguien lo supera.
Colisión: una caja plana. Los haces de luz se sacaron en playtest (competían
con el área de juego).

### CitySkyline

`scripts/systems/city_skyline.gd` + `city_block.gdshader`. Torres de verdad (12
triángulos cada una), un solo `MultiMesh`, ventanas dibujadas por shader en
metros. La misma ciudad es el fondo del menú (`menu_backdrop`, ver
[[07 UI and HUD#Menu backdrop]]).

## El público

- **`CrowdStands`** — un `MultiMeshInstance3D` de quads; toda la silueta la
  dibuja `crowd_impostor.gdshader`, sin textura. Regla: cuesta lo mismo con mil
  que con diez mil. Gris apagado a propósito (`Tokens.LINE`/`DIM`): el ámbar es
  de la casa.
- **`CrowdMoodDirector`** — el entusiasmo sube con el *ritmo* de muertes y se
  enfría solo; dispara la ola y los celulares.
- **`CrowdDropDirector`** + **`CrowdDropPickup`** — el público tira los
  gadgets. **Es la única fuente de utilidades del juego** (salieron de la
  tienda): sólo durante una oleada, a 12-26 m del jugador, desde las dos
  primeras filas. Tabla en `data/crowd_drop_table.tres` (pesos 2:1:1:1.5
  granada / muro / campo lento / botiquin). El pickup suma una carga al slot;
  el **botiquin** (`UtilityData.heal_amount`) cura al levantarlo, solo cae si al
  jugador le falta mas del 20 % de vida y con la vida llena se queda en el piso.
- **Rating** — la espera entre regalos se acorta con el rating de la
  transmision (ver [[06 Waves and Economy#Rating]]) y con la regla *Crowd frenzy*.

## El Host

"Se escucha, no se ve" — sin retrato ni cara. Su presencia visual es el
`BroadcastBug` (borde ámbar, tag LIVE, la marca del anillo cruzado de
`HostMark`).

- **`HostDirector`** (`scripts/systems/host_director.gd`) decide *cuándo* habla:
  mira la partida y nombra la ocasión.
- **`NarratorManager`** (autoload) decide *qué* y *a qué ritmo*: cooldowns por
  línea y por categoría, prioridades, subtítulos. Ver [[02 Autoloads#NarratorManager]].
- **Guion:** `data/host/host_catalog.tres`, exportado a
  `docs/host_script/` por `tools/export_host_script.gd`. **No hay ninguna
  grabación**: el único presentador es `subtitles_only`.
