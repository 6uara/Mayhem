# Decisión de navegación — arenas de autor

Hito 0 del handoff de MAYHEM Tools. Registra qué se eligió, por qué, y qué falta
medir.

## Decisión

**Se implementan las dos, con roles distintos y sin superposición:**

- **Opción A (grilla propia + A\*)** es la fuente de verdad del *editor*.
  `GridGraph` se deriva de `walkable_cells` de las piezas colocadas, y sobre ese
  mismo grafo corren el flood fill de alcanzabilidad, la validación y `NavGrid`
  (A\* con suavizado de waypoints colineales). Preparación instantánea, cero
  bakeo, determinista y testeable sin abrir el editor.
- **Opción B (bakeo de `NavigationRegion3D` en runtime)** es lo que usan los
  *enemigos* al entrar en modo play. `ArenaRuntime` arma la región con los mismos
  parámetros de agente que el navmesh del greybox (`agent_height` 2.0,
  `agent_radius` 0.85, `agent_max_climb` 0.5, `agent_max_slope` 50) y hornea al
  entrar al árbol.

## Por qué no una sola

El handoff prefiere A, y para todo lo que el editor necesita responder —
"¿se llega?", "¿hay región aislada?", "¿qué ruta hay?" — A es estrictamente
mejor: no cuesta nada preparar y se puede testear en CI.

Lo que A no da gratis es el comportamiento que MAYHEM ya tiene comprado. Los
enemigos del juego navegan con `NavigationAgent3D` y con un contrato explícito
entre `max_auto_step` y el `agent_max_climb` del bake (ver `enemy_data.gd`).
Reemplazar eso por seguimiento de waypoints en grilla implicaría reescribir el
movimiento de los cinco arquetipos y su evasión — o sea, tocar sistemas
existentes de MAYHEM, que el handoff marca como consulta obligatoria y no como
trabajo asumido del editor.

Entonces: la geometría es modular y conocida, el bake sale de esa misma
geometría, y ninguna de las dos representaciones puede contradecir a la otra
porque las dos salen de `ArenaData`.

## Lo que falta medir

**No se tomaron mediciones todavía.** El entorno de trabajo no tiene el binario
de Godot, así que el prototipo no se pudo cronometrar. Lo pendiente, con las tres
arenas de prueba (10x10, 24x24, 32x32):

1. Tiempo de `bake_navigation_mesh()` en la arena grande al apretar Play. Si pasa
   los ~1.5 s, va detrás de la pantalla de carga que el juego ya tiene
   (`loading_screen.tscn`), no en transición inmediata.
2. Costo por frame de las consultas con 10, 20 y 40 agentes.
3. Corrección: que los agentes lleguen, no se traben en las juntas de piezas y no
   atraviesen geometría.

Si el bake resulta caro en la arena grande, el reemplazo ya está escrito:
`NavGrid.find_world_path()` devuelve la ruta en espacio de mundo y el cambio se
acota a quién consulta la ruta, no a cómo se mueven los enemigos.

## Criterio de reversión

Si el bake supera los 3 s en la arena grande, o si aparecen agujeros de navmesh
entre piezas contiguas, se pasa a A también en runtime y se mide de nuevo.
