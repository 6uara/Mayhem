# Herramientas en juego

Tres cosas que existen en el juego corriendo: la consola de dev, el panel de
bonos y el editor de arenas in-game. El plugin del editor de Godot (dock de
arenas y de balance) está en
[`addons/mayhem_tools/README.md`](../addons/mayhem_tools/README.md).

## Consola de dev — tecla `` ` `` (backtick)

`scripts/autoload/dev_console.gd`, autoload `DevConsole`. **Solo en builds de
debug**: en release el nodo se libera solo en `_ready()`, así que una build
exportada no lleva una línea de comandos que regala plata.

Congela el árbol mientras está abierta (razón de freeze propia, así que no pelea
con el menú de pausa), libera el mouse, y lo devuelve todo al cerrarse.

Flecha arriba/abajo recorre el historial, Tab completa el nombre del comando.

| Comando | Qué hace |
|---|---|
| `help [comando]` | Lista todo, o explica uno |
| `give <monto>` | Suma moneda |
| `wave <n>` | Salta a la ronda n |
| `kill_all` | Mata todo lo vivo |
| `spawn <enemy_id> [n]` | Spawnea enemigos delante del jugador |
| `upgrade <upgrade_id> [stacks]` | Otorga un upgrade (los de arma se escopan al arma equipada) |
| `upgrades` | Lista los bonos activos |
| `clear_upgrades` | Los borra todos |
| `heal [monto]` | Cura, o cura del todo |
| `god [on\|off]` | Invulnerabilidad |
| `tp <x> <y> <z>` | Teletransporta |
| `timescale <v>` | `Engine.time_scale`, clampeado a 0.05-8 |
| `shop` | Abre la tienda sin tener que limpiar una ronda |
| `balance` | Recarga los `.tres` de balance desde disco |
| `stats` | Ronda, enemigos, moneda, fps |
| `clear`, `quit` | |

Los comandos viven en el diccionario `_commands` como datos: agregar uno es una
línea en `_register_commands()`, y `help` y el autocompletado lo toman solos.
Ninguno implementa reglas propias: todos llaman a un sistema que ya existe, así
que la consola no puede desviarse del juego que sirve para probar.

## Panel de bonos — tecla `O`

`scripts/ui/bonus_panel.gd` (el badge y el desplegable) sobre
`scripts/ui/bonus_list.gd` (la lista en sí).

Plegado es un glifo con la cantidad de bonos y la tecla, sobre el borde
izquierdo, fuera de la zona sin UI de 900x500. Desplegado muestra los bonos
agrupados por las tres categorías de `UpgradeData.Category` — MOBILITY, WEAPON,
SURVIVABILITY — con los stacks (`x2`), el arma a la que está escopado un upgrade
de arma, y la cuenta regresiva de los temporales.

La misma `BonusList` está en la tienda, abajo de las cartas, en su variante
horizontal y con las tres columnas siempre visibles para que no se muevan de
lugar entre visitas. El panel del HUD se esconde mientras la tienda está abierta:
dos copias de la misma lista en pantalla es ruido.

El texto de la tecla sale de `InputMap`, así que rebindear `toggle_bonuses` en
opciones no deja al HUD diciendo "O".

`UpgradeManager.get_owned_entries()` es lo que alimenta ambas: una entrada por
compra, con stacks, arma y segundos restantes. `get_owned()` sigue existiendo
para las consultas de gameplay, que no necesitan el scope.


## Editor de arenas in-game — botón CREAR ARENA en el menú

`scenes/main/arena_editor.tscn` con
[`arena_editor_screen.gd`](../scripts/ui/arena_editor_screen.gd) (control),
[`arena_editor_camera.gd`](../scripts/ui/arena_editor_camera.gd) (cámara) y
[`arena_editor_hud.gd`](../scripts/ui/arena_editor_hud.gd) (interfaz).

Es la segunda cara de la misma herramienta: el dock de Godot y esta pantalla
manejan el mismo `PlacementModel`, validan con el mismo `ArenaValidator` y
previsualizan con el mismo `ArenaPreview`. Lo único distinto es quién hace click.
Esa separación entre lógica y UI, que el handoff pedía desde el primer commit, es
exactamente lo que hizo que esto fuera una capa de arriba y no una reescritura.

| Control | Acción |
|---|---|
| Click izquierdo | Aplica la herramienta activa en la celda |
| Botón derecho / medio arrastrando | Orbita |
| WASD | Paneo |
| Rueda | Zoom |
| `1`-`4` | Construir / Borrar / Spawn del jugador / Spawn enemigo |
| `R` | Rota la pieza 90° |
| `Q` / `E` | Baja / sube de nivel |
| `Z` | Deshacer (un nivel) |
| `H` | Muestra u oculta el panel de controles |

El tamaño de grilla sale de `ArenaData.SIZE_PRESETS` — chica, media o grande, las
mismas tres que usa el dock de Godot. Agrandar siempre se puede; achicar se
rechaza mientras alguna pieza quede afuera, en vez de borrarle el trabajo a
alguien en silencio.

El panel de controles se abre solo la primera vez que un jugador entra al editor
(la marca queda en `editor/help_seen`, junto al resto de las settings) y después
sale con `H` o el botón `?`.

Hay dos venues: `Stands` (el cuenco entero, escalado) y `Stands (tiled)` (el
anillo armado repitiendo secciones, que calza exacto a cualquier tamaño y es el
que usa la arena default). La barra tiene además el selector de **venue** (el tema): lo que rodea a la
grilla. Es dato de la arena, no una preferencia global, así que dos arenas pueden
querer estadios distintos y el archivo se acuerda de cuál.

Abajo de la lista de validación hay una línea de **calce del venue**: dice cuánto
va a tener que estirarse el tema para rodear lo que construiste y, cuando el
estiramiento pasa de 1.25x, qué medida en celdas entraría sin deformar nada. No
es una regla de validación — un venue estirado es feo, no está roto — por eso
avisa en ámbar en vez de bloquear el PLAY.

El panel de validación lista errores y advertencias en vivo; hacer click en uno
lleva la cámara a la celda. Los errores deshabilitan PLAY y lo dicen en el botón;
guardar sí se permite con errores, porque parar a mitad de una arena es normal.

**Elegir arena.** Con una sola arena instalada, PLAY en el menú arranca una run.
Con más de una — la del juego más las que hizo el jugador — abre
[arena_select.tscn](../scenes/ui/arena_select.tscn), que lista cada una con su
nombre, si es del juego o tuya, y cuántas piezas tiene. Lo elegido queda en
`ArenaSession.run_arena_path` y lo levanta el `ArenaHost`; borrar esa arena desde
el editor limpia la elección, así que una run nunca apunta a un archivo que ya no
está.

**La partida carga arenas.** `game.tscn` ya no lleva una arena adentro: tiene un
`ArenaHost` ([arena_host.gd](../scripts/systems/arena_host.gd)) que decide cuál
cargar — la que estás probando desde el editor, la que dejó el botón Play del
dock, o `data/arenas/default_arena.tres`, que es la de una run normal. La arena
vieja (`scenes/arena/greybox_arena.tscn`) quedó sin usar; el archivo sigue ahí
por si querés sacarle algo.

**Dónde viven las arenas**: `user://arenas/*.tres`, al lado del save. Un juego
exportado no puede escribir en `res://`, y además son archivos del jugador — por
eso SAVE siempre escribe ahí adentro: abrir la arena de ejemplo que viene en
`res://data/arenas/` y guardar produce una copia propia, nunca pisa el archivo
del proyecto. LOAD lista lo guardado, más reciente primero, y borra con dos
clicks (DELETE pasa a SURE? por tres segundos) en vez de con otro modal encima
del modal.
[`ArenaSession`](../scripts/autoload/arena_session.gd) es el autoload que sabe de
las dos puntas: tiene la arena en mano, la carpeta del jugador, y el viaje de ida
y vuelta al playtest. PLAY guarda, valida y entra a la partida real de MAYHEM en
esa arena; el menú de pausa muestra **Back to the editor** solamente durante ese
playtest, y volver no pierde nada porque la arena nunca salió de memoria.
