# MAYHEM Tools

Dos herramientas de autoría para MAYHEM, en un solo plugin de editor de Godot
4.7: un **editor de arenas** modular sobre grilla y un **editor de balance** con
curva de economía y aplicación en caliente.

## El problema

MAYHEM es un arena shooter con economía entre rondas. Dos cosas eran caras de
iterar: construir una arena nueva (mover cajas a mano en una escena, re-bakear
navegación, acomodar puertas de spawn) y tunear la economía (abrir un `.tres`,
adivinar qué significa el número en la ronda 7, reiniciar la partida).

## Decisiones de arquitectura

**La lógica no conoce la UI.** Todo lo que decide algo vive en
`arena_editor/core/`: colocación, validación, alcanzabilidad, pathfinding,
serialización. Ninguno de esos archivos referencia un nodo de interfaz ni el
editor de Godot, así que la suite de tests los maneja de frente y una futura
herramienta in-game reusa el 100%.

**Los datos son la fuente de verdad.** Una arena es un `ArenaData`. El editor lo
escribe, el juego lo lee, y `runtime/arena_loader.gd` es la única superficie de
contacto entre los dos.

**Resource nativo, JSON exportable.** El guardado nativo es `.tres`
(serialización gratis, tipado, inspector); `to_dict()`/`from_dict()` y el botón
*Export JSON* dan la versión legible y diffeable. `format_version` se migra en
`ArenaData._migrate`, con un test que carga un archivo v1 contra la versión
actual.

**El catálogo de piezas son datos.** 12 piezas en `data/arena_pieces/`. Agregar
una es escribir un `.tres` y sumarlo al catálogo — nunca tocar código. Una pieza
sin escena asociada se greyboxea desde su huella, así que el catálogo es usable
antes de que exista el arte.

**Navegación: las dos opciones, con roles separados.** Ver
[`docs/DECISION_navegacion_arenas.md`](../../docs/DECISION_navegacion_arenas.md).

**La escena de partida carga arenas.** `game.tscn` ya no lleva una arena adentro:
tiene un `ArenaHost` que carga la arena default, la que el jugador está
probando desde el editor in-game, o la que el botón Play del dock dejó en las
settings del proyecto. Un solo camino de entrada para las tres cosas.

## Cómo probarlo

**Sin abrir el editor** (es lo que corre en CI):

```
godot --headless --path . -s tools/make_default_arena.gd
```

Construye `data/arenas/default_arena.tres` — *The Pit*, la única arena que
viene con el juego — manejando el mismo `PlacementModel` que maneja el dock. La
valida antes de guardar, falla si alguna pieza fue rechazada, e imprime piezas,
celdas caminables, spawns y enlaces de navegación. Si eso corre, el núcleo está
sano.

Después, para jugarla:

```
godot --path . res://scenes/main/game.tscn
```

Arranca la partida en la arena default (`data/arenas/default_arena.tres`), que
es la que `ArenaHost` carga cuando nadie pidió otra.

**En el editor**: abrí el proyecto, el dock *Arena* aparece a la derecha. El
switch **Build mode** arriba del todo decide si el plugin toca el viewport 3D:
apagado (el default) el click izquierdo y la `R` siguen siendo de Godot y no se
mete ningún nodo en la escena abierta, así que podés autorar escenas con el dock
a la vista. Prendelo para construir. Abrí
cualquier escena 3D (la vista previa se dibuja ahí y nunca se guarda con ella),
elegí tamaño y pieza, click izquierdo para colocar, **R** para rotar, *Level*
para cambiar de altura. Cambiá de herramienta para borrar o poner spawns.
*Play* valida, guarda a `data/arenas/_playtest.tres` y lanza la partida.

## Piezas de traversal y enlaces

`bounce_pad`, `jump_link`, `zip_line`, `grapple_anchor`, `moving_platform` y
`hazard_zone` son piezas del catálogo que instancian las escenas que el juego ya
tiene. Las que mueven al jugador declaran además un **enlace**:

```
link_offsets      = [Vector3i(0, 2, 0)]   # celdas que conecta con la suya
link_players_only = true                  # un pad lanza al jugador, a nadie más
link_is_one_way   = true                  # te sube, no te baja
```

El grafo suma esas aristas, así que el flood fill, el A\* y la validación las
entienden solas. Y como el editor pregunta dos cosas distintas — "¿llega el
jugador?" y "¿llega la horda?" — los enlaces `players_only` cuentan para la
primera y no para la segunda: una cornisa a la que sólo se sube con pad es un
diseño, no una región aislada, pero un spawn enemigo del otro lado sigue siendo
un error. En el load, los enlaces compartidos se publican como `NavigationLink3D`
para que los enemigos los usen de verdad.

**El offset tiene que coincidir con el tuning de la escena.** Un pad a
`bounce_velocity` 20 llega a 8.3 m, o sea dos niveles de 3 m. Si alguien mueve
ese número, el `.tres` de la pieza queda mintiendo; los dos archivos se apuntan
entre sí en un comentario.

## Temas de arena

`ArenaTheme` es lo que rodea a la grilla: shell, cielo, sol y kill plane. Vive en
`data/arena_themes/*.tres` y cada arena guarda cuál usa (`ArenaData.theme_id`,
migrado desde las arenas viejas).

El shell es una escena común y corriente. Si expone

```gdscript
func setup(bounds: AABB) -> void:
```

el runtime le pasa la caja real de la arena (`grid_size * cell_size`) para que
acomode paredes y gradas alrededor; si no la expone, se instancia tal cual, que
es lo que quiere un fondo fijo. Un tema sin shell igual da cielo, luz y kill
plane, así que la arena nunca sale a un vacío gris.

Para medir un modelo de gradas nuevo:
`godot --headless --path . -s tools/measure_shell_pit.gd`. Imprime el `pit_size`
y el `pit_center` listos para pegar en el shell, el perfil de altura de cada cara
(un cuenco cerrado sube en las cuatro) y cuántos triángulos tienen la normal
invertida — que es lo que Godot dibuja como agujeros y Blender no muestra.

El shell que viene, `scenes/arena/shells/default_shell.tscn`, envuelve el cuenco
de gradas (`assets/models/arena/Stands.blend`) con `ArenaShell`: mide el pozo del
modelo (19 x 9.5 en sus unidades), lo escala para que el pozo contenga la arena
más un margen, apoya una losa de hormigón en el piso del pozo y levanta cuatro
paredes de colisión en el borde jugable. El hormigón es triplanar en espacio de
mundo, así que la losa mide lo mismo en una arena chica que en una grande por
más que el cuenco se estire.

Ojo con una cosa: **el shell se calza al contenido construido, no a la grilla**
(`ArenaRuntime.get_content_bounds()`). Una arena que usa un cuarto de una grilla
grande no recibe gradas rodeando tres cuartos de vacío.

## Dos formas de venue

`ArenaShell` toma **un cuenco cerrado** y lo escala hasta que su pozo rodea la
arena. Sirve cuando el modelo tiene la proporción de la arena; cuando no, estira
las terrazas en un eje y las deja cortas en el otro.

`ArenaTiledShell` arma el anillo **repitiendo una sección recta y una esquina**
alrededor de lo construido. No hay proporción que pelear: la cantidad de copias
sale del tamaño real de la arena y cada copia conserva lo que se modeló. Coloca
por caja envolvente y no por origen, así que una sección autorada alrededor de
cualquier origen cae donde tiene que caer. Es lo que usa la arena default
(tema `tiled`).

## Convención de celdas

Una celda mide `cell_size` (4x3x4 por defecto) y su origen es el **piso** de la
celda, no su centro. Las piezas se construyen hacia arriba desde ahí.

Cada celda tiene dos capas: **suelo** (FLOOR, RAMP, PLATFORM) y **cuerpo** (WALL,
PROP). Una pared y el piso sobre el que se apoya comparten celda y eso no es una
superposición; dos pisos en la misma celda sí. Borrar y rotar se llevan primero
la pieza de cuerpo, que es la que estás viendo.

Cada pieza declara qué necesita en su celda con `support`:

- `ANY` — estructura (paredes, pilares, cobertura). Va donde su capa esté libre,
  y se apila para hacer altura.
- `FLOOR` — pad, tirolesa, munición, lava, plataforma móvil, jump link, campo de
  freno. Sólo **sobre una celda con piso plano**: ni al aire, ni sobre una rampa,
  donde la escena quedaría inclinada en un ángulo para el que no fue modelada.
- `EMPTY` — el ancla de grapple, que **cuelga**: va en una celda sin piso, y con
  `min_level = 2` para que quede sobre la cabeza del jugador. Un ancla al alcance
  de la mano no es un gancho, es una decoración. Cuando el modelo rechaza una colocación devuelve un código
(`cell_taken`, `needs_floor`, `out_of_bounds`) y las dos interfaces lo traducen a
una frase, en vez de dejarte adivinando.

## Uso

### Arena Editor (dock derecho, pestaña *Arena*)

1. Abrí cualquier escena 3D: la vista previa se dibuja ahí y nunca se guarda con
   la escena.
2. Elegí tamaño y pieza, click izquierdo para colocar, **R** para rotar.
3. Cambiá de herramienta para borrar o poner spawns; el nivel de trabajo se elige
   con *Level*.
4. El panel de validación lista errores y advertencias; al hacer click en uno se
   selecciona un marcador en esa celda (F para enfocar).
5. *Save* y *Play* están bloqueados mientras haya errores.

### Editor in-game (botón CREAR ARENA en el menú del juego)

La misma herramienta para el jugador final, sin abrir Godot: cámara de
construcción, paleta, validación en vivo, guardado en `user://arenas/` y playtest
con vuelta al editor. Comparte el 100% de `core/` con el dock — ver
[`docs/DEV_TOOLS.md`](../../docs/DEV_TOOLS.md).

### Balance Editor (panel inferior, *Balance*)

Pestaña **Economy** para los valores de `economy_config.tres`, **Archetypes**
para los stats de los ocho `EnemyData`. El gráfico proyecta el oro acumulado por
ronda contra la escalera de precios de la tienda; el slider modela qué tan bien
juega el jugador proyectado.

*Apply to game* escribe los `.tres`. El autoload `BalanceHub` (solo en builds de
editor) vigila esos archivos y los recarga en su lugar con `CACHE_MODE_REPLACE`,
así que la partida corriendo toma el valor nuevo en medio segundo, sin
reiniciar y sin que ningún sistema del juego tuviera que suscribirse.

## Qué quedó fuera a propósito

Undo multinivel (hay un nivel), iluminación bakeada, materiales por pieza,
terreno de altura libre, edición colaborativa, y cualquier forma de compartir
niveles online — nada de workshop, cuentas ni servidores. Los archivos se pasan
a mano.

## Estado

Núcleo, validación, serialización, loader, plugin y ambos paneles están
implementados y cubiertos por tests en `tests/unit/test_arena_*.gd` y
`test_balance_curve.gd`. Falta lo que necesita ejecutar el editor: las
mediciones del bake de navegación, las tres arenas de ejemplo y los GIFs.
