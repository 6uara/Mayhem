---
tags: [mayhem, arena, venue, crowd, host]
estado: referencia
actualizado: 2026-10-09
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
- **Lotes:** al cargar, `ArenaGeometryBatcher` junta las cajas greybox en un
  `MultiMeshInstance3D` por malla+material (bajo `BatchedGeometry`). Cada pieza
  sigue siendo su nodo con su colision.
- **Catálogo:** 21 piezas en `data/arena_pieces/` (`default_catalog.tres`),
  categorías `FLOOR / RAMP / WALL / PLATFORM / PROP`. Cada `PieceDefinition`
  puede traer `scene`; **ninguna la trae hoy**, así que todas se arman como caja
  greybox desde `footprint` + `greybox_color` (`piece_mesh_builder.gd`), con el
  filete emisivo `edge_color`/`edge_energy` que las hace legibles de noche.
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

### EnergyWall

`scripts/systems/energy_wall.gd` + `energy_wall.gdshader`. El límite visible. La
colisión siguen siendo cuatro cajas del shell; la pared **contesta**: cuando el
jugador pasa cerca de un plano (medido por distancia, no por física) se abre una
onda desde ese punto. Hasta 8 ondas simultáneas (`MAX_IMPACTS`).

### ArenaRoof

`scripts/systems/arena_roof.gd`. Anillo estructural, vigas y óculo abierto
(`oculus_share`). Existe por una razón de juego: con gancho, dash, pads y zip
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
