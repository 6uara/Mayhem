# Plan de performance

Rama `perf/optimizacion-rendimiento`. El objetivo es el que fija CLAUDE.md
seccion 10: sostener 60 FPS con una oleada elite completa (wave_10, 27 enemigos).

## Como medir

`tools/profile_elite_wave.gd` ya hace la medicion real:

    godot --path . -s tools/profile_elite_wave.gd -- 20

Debe correr **con render real, nunca con `--headless`** (lo explica el propio
script: headless saltea el renderer y solo mediria el costo de script/fisica,
perdiendo la mitad GPU de la pregunta).

## Numeros (2026-08-11, Windows 11, d3d12, 1920x1080)

Oleada 10 completa, 27 enemigos vivos, 20s de muestreo:

| | min | avg | max | frames < 60 |
|---|---|---|---|---|
| Antes | 453.0 | 619.9 | 663.0 | 0.0% |
| Despues | 655.0 | 716.0 | 761.0 | 0.0% |
| Despues (2da corrida) | 671.0 | 721.0 | 755.0 | 0.0% |

**El objetivo de 60 FPS ya se cumplia con ~10x de margen antes de tocar nada.**
No hay un problema de performance en esta maquina; lo que hay es trabajo por
frame que no compra nada, y eso es lo que se saco. La mejora medida es ~+16% en
promedio y ~+45% en el minimo, con dos corridas consistentes despues del cambio.

El minimo es el numero que mas importa de la tabla: es el frame peor, el que se
convierte en un tiron perceptible cuando alguien corre esto en una maquina 10x
mas lenta que esta. Que subiera de 453 a 655 es la parte del resultado que va a
seguir importando fuera de este equipo.

Advertencia honesta sobre la medicion: es una corrida por configuracion (dos en
la de despues), en una maquina sin control de ruido termico ni de procesos de
fondo. La direccion es clara y consistente, la magnitud exacta no.

## Aplicado

### 1. `Enemy._has_navmesh()` - asignacion por frame por enemigo

`scripts/actors/enemy.gd`. `_steer()` preguntaba cada frame de fisica si hay
navmesh, y `NavigationServer3D.map_get_regions()` asigna un `Array[RID]` nuevo en
cada llamada. Con una oleada elite caminando eso era ~1600 arrays descartables
por segundo, para una respuesta que no cambia: el navmesh se hornea offline y se
commitea (ver `ArenaNavigation`).

Ahora la respuesta se cachea. Solo se cachea el `true`, y el latch se limpia en
`setup()`: un enemigo del pool sobrevive a la arena donde nacio, y cachear un
`false` de un mapa todavia sin resolver lo dejaria caminando en linea recta el
resto de su vida.

Es exactamente el mismo arreglo que ya se le habia hecho a `_find_link_ahead()`.

### 2. `SegmentStrip` - `queue_redraw()` sin guarda

`scripts/ui/segment_strip.gd`. Los setters de `filled` y `progress` redibujaban
en cada escritura. El HUD escribe ambos desde `_process()` todos los frames en la
barra de par, los pips de dash y los de municion, asi que eran cinco `_draw()`
completos por frame - un rebuild del command buffer por segmento - para numeros
que cambian unas pocas veces por segundo. Ahora salen temprano si el valor no
cambio.

### 3. `HUD._tick_wave()` - overrides de tema por frame

`scripts/ui/hud.gd`. Llamaba `add_theme_color_override()` dos veces por frame sin
condicion. Ese metodo invalida el control y renotifica su subarbol en cada
llamada, cambie o no el color, asi que se pagaba 60 veces por segundo para cruzar
un limite que se cruza una vez. Ahora los dos bloques (pasar el par, perder el
"sin dano") disparan solo en la transicion, y la etiqueta PAR se formatea al
cambiar de oleada en vez de reconstruirse cada frame.

## Pendiente - y por que no se toco

Con 700 FPS en la oleada mas cargada, nada de lo que sigue se justifica *hoy* en
esta maquina. Queda anotado porque el dia que aparezca un target mas debil (una
notebook con GPU integrada, una build de consola) esta es la lista por donde
empezar, en este orden. Ninguno se toca sin volver a correr el profiler antes y
despues.

### 4. `arena_glitch_panel.gdshader` (probable el item mas caro)

Es el shader de todas las paredes y pisos de `greybox_arena.tscn`: la mayor
cobertura de pixeles del juego, y el fragment mas pesado que hay - triplanar con
3 `grid_line`, 6 `hash21`, dos `pow`. Ademas, las escenas lo instancian con
`glitch_speed = 0` y `scanline_speed = 0` (congelado), pero como son uniforms el
compilador no puede plegar esa rama: se sigue evaluando el pulso por celda entero
cada pixel para un resultado constante.

Si el perfil da GPU-bound, este es el primer lugar donde mirar. La salida limpia
es una variante del shader sin la parte animada, no bajarle los numeros.

### 5. `HUD._tick_movement()` - slot de grapple

Resuelve `_grapple_slot.get_node("Keybind")` por string cada frame y reescribe
`theme_type_variation` cada frame. Cachear el nodo y guardar el estado, igual que
el punto 3. Chico pero gratis.

### 6. `host_mark.gd`

`_process()` llama `queue_redraw()` incondicionalmente, y `_draw()` hace un
`draw_arc` de 32 puntos. Solo importa si la marca esta visible seguido.

### 7. Shaders nuevos sin usar

`vhs`, `glitch`, `hologram`, `aurora_sky`, `dissolve`, `lightning`, `ui_onfire`
estan en `assets/shaders/` pero ninguna escena los referencia. Hoy no cuestan
nada. Si se cablean - sobre todo los de pantalla completa - hay que volver a
medir antes de mergear.

### 8. Settings de render del proyecto

`project.godot` no declara nada bajo `[rendering]` mas alla del driver d3d12:
todo queda en los defaults de Forward+. Vale revisar glow, SSAO/SDFGI, atlas de
sombras y MSAA una vez que haya un numero base - pero recien despues de medir,
porque son los knobs que mas facil arruinan el look a cambio de FPS que, segun la
tabla de arriba, no hacen ninguna falta.
