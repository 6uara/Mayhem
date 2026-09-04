---
tags: [mayhem, plan, arena, utilities, crowd]
---

# MAYHEM — El público y los gadgets que tira a la arena

Rama: `feat/crowd-drops`. Base: `develop` @ `6b31aa4`.

Dos cambios que en realidad son uno solo. La arena tiene gradas vacías, y los
tres gadgets del jugador se compran en una pantalla de menú. Poner al público en
las gradas y hacer que sea *él* quien tira los gadgets resuelve las dos cosas
con el mismo gesto: el público deja de ser decorado y pasa a ser una fuente de
recursos, y el gadget deja de ser una línea de gasto para pasar a ser algo que
se agarra corriendo, en el medio del combate, arriesgando la posición — que es
el pilar de movilidad de siempre.

> Todo lo marcado **(medido)** fue verificado leyendo el código en `6b31aa4`,
> no asumido.

## 0. Las cuatro decisiones tomadas

| Pregunta | Decisión |
|---|---|
| Qué sale del shop | **Las tres utilidades**: granada, muro temporal y campo lento. El shop queda con armas y upgrades. |
| Qué hace el pickup | **Suma una carga al slot que corresponde**. Se conserva entero el sistema de slots, `max_carried` y cooldown. |
| Cadencia del drop | **Timer random escalado por oleada**, y el Host lo anuncia. |
| Espectadores | **Cápsulas en un MultiMesh** con un idle barato. Placeholder explícito. |

---

## 1. Lo que ya existe (medido)

- `UtilityComponent` (`scripts/components/utility_component.gd`) tiene tres
  slots fijos, `_carried` por slot, cooldown por slot, y **ya expone
  `add_charge(utility_id, amount)`** que respeta `max_carried` y devuelve
  `false` cuando el slot está lleno. Es exactamente la puerta que necesita el
  pickup: no hay que abrir nada nuevo.
- `Shop` (`scripts/systems/shop.gd`) mete las utilidades en el pool de ofertas
  en `_build_pool()`, y las compra en `_buy_utility()`. `Shop.Kind.UTILITY`
  existe como enum.
- `ShopCatalog.utilities: Array[UtilityData]` y `find_utility()`.
- `AmmoPickup` (`scripts/systems/ammo_pickup.gd`) es el molde de pickup del
  proyecto: `Area3D`, chequea el grupo `player`, **pregunta antes de tomar** (si
  el jugador está lleno la caja se queda donde está), bob + rotación, luz, hum
  looping propio y color `Tokens.WORLD_PICKUP` — ámbar, que en este juego
  significa "la casa". El drop del público hereda esa gramática entera.
- `ArenaShell` y `ArenaTiledShell` comparten la firma **`setup(bounds: AABB,
  theme: ArenaTheme)`**, llamada por `ArenaRuntime`. Ese `bounds` es el
  footprint real de la arena en metros: es todo lo que hace falta para saber
  dónde empiezan las gradas.
- `HostDirector` (`scripts/systems/host_director.gd`) es el único lugar donde se
  decide que el Host hable; `NarratorManager.say(&"id")` con cooldowns por línea
  y por categoría. Las líneas viven en `data/host/host_catalog.tres`.
- `ThrownUtility` ya acepta `launch_with_velocity()`, abierto en su momento para
  que el enemigo Environmental pudiera tirar frascos. **El gadget que cae de la
  grada usa esa misma puerta**, no una nueva.

## 2. Lo que se construye

### 2.1 `CrowdStands` — el público placeholder

`scripts/systems/crowd_stands.gd`, un `MultiMeshInstance3D`.

- `populate(bounds: AABB, pit_margin: float, floor_y: float)`: arma filas
  concéntricas de asientos alrededor del rectángulo de la arena, cada fila un
  poco más afuera y más arriba (mismo paso que las gradas), y siembra una
  cápsula por asiento con jitter de posición y de altura.
- Un `RandomNumberGenerator` **con semilla fija** derivada del tamaño de la
  arena, para que la misma arena tenga siempre la misma multitud: un público que
  se reordena en cada carga se nota.
- Idle: un shader de vértices sobre el MultiMesh, no `_process`. Cada instancia
  sube y baja con un desfase sacado de su propio `INSTANCE_CUSTOM`, así el
  movimiento cuesta cero por espectador. **No hay un Node3D por espectador.**
- `pick_seat() -> Vector3`: devuelve la posición mundial de un asiento al azar
  de la primera o segunda fila. Es la única API que consume el director.
- Se agrega al grupo `&"crowd"`.
- Color: gris apagado. **No ámbar** — el ámbar es de la casa y de los pickups, y
  un público ámbar compite con la cosa que el jugador tiene que ver.

Los dos shells la instancian al final de su `setup()`. Como comparten firma, es
la misma línea en los dos archivos.

### 2.2 `CrowdDropDirector` — quién tira y cuándo

`scripts/systems/crowd_drop_director.gd`, un `Node` en `scenes/main/game.tscn`
al lado de `HostDirector`.

- Corre sólo durante una oleada (`EventBus.wave_started` /
  `wave_completed`): entre oleadas no hay a quién entretener.
- Timer con ventana `[min_interval, max_interval]`, ambos exportados, escalados
  por número de oleada — oleadas altas tiran más seguido, porque son las que
  piden más gadget.
- Elige una `UtilityData` de una lista exportada, con pesos, **filtrando los
  slots que el jugador ya tiene llenos**: tirar una granada a alguien con dos
  granadas es tirar basura a la arena.
- `crowd.pick_seat()` da el origen. Se resuelve una velocidad balística desde
  ese asiento hasta un punto de la arena (`ArenaRuntime` bounds, con margen), y
  se lanza un `CrowdDropPickup` con `launch_with_velocity()`.
- Emite `EventBus.crowd_drop_thrown(utility_id, landing)` (señal nueva).

### 2.3 `CrowdDropPickup` — el objeto en el aire y en el piso

`scripts/systems/crowd_drop_pickup.gd` + `scenes/arena/crowd_drop_pickup.tscn`.

Vuela con la misma matemática de `ThrownUtility` (arco escalonado, no
`RigidBody3D`), y al aterrizar se convierte en un pickup con la gramática de
`AmmoPickup`:

- Ámbar `Tokens.WORLD_PICKUP`, bob, rotación, luz, hum audible antes que
  visible. Lo mismo que la caja de munición, porque es la misma clase de cosa.
- Un rastro visible en el aire, para que se pueda seguir la caída desde el otro
  lado de la arena.
- `body_entered` → `utility.add_charge(data.id)`. **Si devuelve `false` (slot
  lleno) el objeto se queda en el piso**, igual que la munición.
- `despawn_time` exportado: si nadie lo levanta desaparece. Un piso sembrado de
  gadgets viejos convierte el recurso en algo que no hay que administrar.
- Pooleado por `ObjectPool`, como el resto de lo que vuela.

### 2.4 El Host lo anuncia

Una línea nueva `crowd_drop` en `data/host/host_catalog.tres`, disparada desde
`HostDirector` escuchando `EventBus.crowd_drop_thrown`. Prioridad `FEEDBACK`,
por debajo de las de estado: si el Host está avisando que te queda poca vida, el
regalo del público puede esperar. `NarratorManager` ya hace ese trabajo; sólo
hay que darle la prioridad correcta.

### 2.5 Sacar las utilidades del shop

- `Shop._build_pool()`: se borra el bloque que empuja utilidades al pool.
- `Shop._buy_utility()` y `Shop.Kind.UTILITY`: se borran.
- `ShopCatalog.utilities` **se queda en el recurso pero se vacía**, y el docstring
  dice por qué: el campo sigue siendo el catálogo de utilidades del que come el
  `CrowdDropDirector`. Es lo mismo que era, con otro consumidor.
- `UtilityData.cost` deja de tener consumidor. Se marca deprecado en el
  docstring antes que borrarlo, porque los tres `.tres` lo tienen serializado.

**Consecuencia de balance, y hay que decirla:** las utilidades eran un sumidero
de dinero. Sacarlas deja al jugador con más plata para armas y upgrades sin que
nadie lo haya decidido. El plan **no** compensa eso — el ajuste correcto se hace
jugando, no adivinando — pero queda anotado acá como lo primero a mirar en el
primer playtest.

---

## 3. Pasos, en orden

1. **`CrowdStands` + integración en los dos shells.** Entregable propio: las
   gradas dejan de estar vacías, sin tocar nada de gameplay.
2. **`CrowdDropPickup`**, lanzado a mano desde la consola de dev
   (`DevConsole`) para poder verlo caer y levantarlo.
3. **`CrowdDropDirector`** con el timer, cableado a las señales de oleada.
4. **Sacar las utilidades del shop.** Va último a propósito: hasta que el
   público no esté tirando gadgets de verdad, sacarlas del shop deja al jugador
   sin gadgets.
5. **Línea del Host** + señal nueva en `EventBus`.
6. **Docs**: `docs/Mayhem/06 Waves and Economy.md` (el shop cambia de contenido)
   y `03 Player and Movement.md` (de dónde salen los gadgets).

## 4. Tests

Con `tools/run_tests.ps1`, que es lo que corre GUT sin ensuciar el árbol.

- `test_crowd_stands.gd` — la misma arena da la misma multitud dos veces
  (semilla); ningún asiento cae dentro del `bounds` de la arena; `pick_seat()`
  devuelve siempre un punto de las gradas.
- `test_crowd_drop_director.gd` — no tira entre oleadas; no elige una utilidad
  cuyo slot está lleno; la ventana escala con el número de oleada.
- `test_crowd_drop_pickup.gd` — sumar carga con el slot lleno deja el objeto en
  el piso; con lugar, lo consume y sube el `carried`; el despawn devuelve el
  objeto al pool.
- `test_shop_and_loadout.gd` (existente) — hay que **actualizarlo**: hoy afirma
  que se pueden comprar utilidades. Pasa a afirmar lo contrario, que el shop no
  ofrece utilidades nunca.
- `test_utility_cast_modes.gd` (existente) — **no se toca**. Los dos esquemas de
  input no cambian; sólo cambia de dónde vienen las cargas.

## 5. Lo que este plan NO hace

- No cambia los tres gadgets ni sus efectos.
- No toca los dos esquemas de input (quick cast / equipar).
- No cambia el sistema de slots por un inventario genérico.
- No modela espectadores de verdad: son cápsulas, y se van a ver como cápsulas.
- No rebalancea la economía por el sumidero que desaparece (§2.5).
