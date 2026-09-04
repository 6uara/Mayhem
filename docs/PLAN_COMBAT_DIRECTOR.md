---
tags: [mayhem, plan, enemies, performance, aplicado]
---

# MAYHEM — Combat Director

**Estado: construido y verde** (858 tests). Lo que sigue es el porqué de cada
decisión y lo que quedó explícitamente afuera.

---

## 1. El problema

Cada enemigo ya sabía pelear. Perseguía, kiteaba, flanqueaba, tiraba frascos —
todo eso está en `enemy.gd` y en las hojas de Beehave desde
[PLAN_ENEMY_BEHAVIOR.md](PLAN_ENEMY_BEHAVIOR.md). Pero lo decidía **solo**, con
los números de su `.tres` y un carril lateral al azar.

Eso alcanza para seis enemigos y deja de alcanzar bastante antes de los veinte,
que es a donde van las waves:

- Dos Rangers que elegían el mismo ángulo se tapaban entre sí. El jugador veía
  una silueta donde había dos amenazas.
- Los tres arquetipos que kitean (Ranger, Healer, Summoner) **no pedían rumbo en
  absoluto**: quedaban donde los dejaba el navmesh, que en la práctica es
  amontonados sobre la línea directa al jugador.
- Nada acotaba cuántos ataques telegrafiados salían a la vez. Quince Rushers
  saltando en el mismo frame no son quince amenazas: son una pared que aparece de
  golpe y no se puede leer.
- La separación —lo único que despegaba a la horda— costaba **N²** por ciclo,
  justo la parte que tiene que crecer.

Ninguna de esas cuatro cosas se puede arreglar desde adentro de un enemigo. Todas
requieren mirar a todos a la vez. Eso es el director.

---

## 2. Qué es y qué no es

`CombatDirector` (`scripts/autoload/combat_director.gd`) es un autoload. **No
mueve a nadie.** No hay una sola línea suya que toque `velocity` ni
`global_position`. La navegación, la esquiva, los saltos y los ataques siguen
enteros donde estaban.

Lo que hace es contestar cuatro preguntas que un enemigo no puede contestar solo:

| Pregunta | API | Frecuencia |
|---|---|---|
| ¿Dónde me paro? | `bearing_for(enemy)` | reparto cada 250 ms |
| ¿Quién está cerca mío? | `separation_for(enemy)`, `neighbors(point, r)` | grilla cada 50 ms |
| ¿Puedo comprometerme a este ataque? | `request_attack_token()` / `release_attack_token()` | por ataque |
| ¿Me alcanza el presupuesto del frame? | `request_repath()` | por frame |

Es autoload y no un nodo del arena a propósito: los enemigos son pooleados y
sobreviven al cambio de escena, así que el registro tiene que vivir más que
cualquier arena. `reset()` lo vacía entre runs y se engancha a `player_died`.

---

## 3. Roles, no arquetipos

El arquetipo dice **qué** hace un enemigo. El rol dice **dónde se para mientras lo
hace**. Son dos ejes distintos y mezclarlos es lo que hacía que agregar un
arquetipo obligara a tocar la posición de todos los demás.

`CombatDirector.role_of()` lo deduce del dato, nunca del nombre — un arquetipo
nuevo hereda su puesto sin tocar el director:

```
espoleta          → INFILTRATOR
ENVIRONMENTAL     → ARTILLERY
preferred_distance → SKIRMISHER
si no             → BRAWLER
```

Cada rol tiene una **banda angular** medida desde la mirada del jugador. El
`.tres` ya no elige el ángulo: elige el rol, y el director reparte adentro de la
banda sin repetir.

| Rol | Banda | Quién | Qué le pregunta al jugador |
|---|---|---|---|
| `BRAWLER` | 0°–35° | Rusher | Presión de frente. Es la que le da sentido a todo lo que llega por otro lado. |
| `SKIRMISHER` | 55°–115° | Ranger, Healer, Summoner, Flyer | "No te podés quedar mirando a uno solo." |
| `ARTILLERY` | 35°–80° | Environmental | Te corta el camino donde ibas. |
| `INFILTRATOR` | 145°–200° | Bomber | El punto ciego. |

Las bandas casi no se pisan, y ese es todo el diseño: si el mismo ángulo lo
pueden pedir un Rusher y un Ranger, el jugador no puede aprender qué significa
cada silueta según de dónde viene.

### El reparto

`_reassign_bearings()` agrupa por rol, arma los puestos de la banda en abanico
espejado (alternando lado a lado, para que tres tiradores no queden los tres a la
izquierda) y aparea enemigos con puestos **ordenando los dos conjuntos por
ángulo**. Eso da la asignación de costo mínimo sobre un círculo sin buscarla: un
`sort` en vez de una matriz N×N, y estable, que importa tanto como que sea barata
— reasignar al azar cada 250 ms haría que el grupo entero se cruce en el aire.

El que tiene `approach_bearing_weight = 0` no ocupa puesto: viene de frente y se
separa con el carril lateral, exactamente como antes.

---

## 4. El techo de compromiso

`ATTACK_TOKENS` limita cuántos enemigos de cada rol pueden estar comprometidos en
un ataque **telegrafiado** al mismo tiempo (3 brawlers, 4 skirmishers, 2 artillery,
2 infiltrators).

Sólo para los ataques que se **leen** — el salto de `ActionLeapAttack` es el que
está cableado hoy. El golpe básico no pide ficha, porque un cuerpo a cuerpo que
espera turno estando ya encima del jugador se lee como un bug y no como una
coreografía.

La ficha se devuelve en tres lugares, y los tres hicieron falta: al terminar la
recuperación del salto, en `after_run` (el árbol puede abandonar la rama a mitad
de vuelo por un aturdimiento) y en `unregister()` (un enemigo que muere saltando
no puede quedarse con el cupo del resto de la oleada). Esa última es la falla que
no tira ningún error: se ve como una horda que dejó de atacar.

---

## 5. Performance

### Lo que se sacó

1. **Separación N² → grilla espacial.** Cada enemigo recorría a los N enemigos
   cada 50 ms. Ahora mira su celda y las ocho de alrededor, que a densidad de
   horda son un puñado, y deja de importar cuántos hay del otro lado del arena.
2. **La grilla se rearma cada 50 ms**, no cada frame: rearmarla asigna un array
   por celda ocupada. En 50 ms un enemigo se corre menos de medio metro y la
   consulta ya mira una celda de margen. *Costo honesto:* los vecinos se
   resuelven con hasta 50 ms de retraso, que es invisible en juego pero obligó a
   que dos tests de separación esperen un frame entre teletransportar un cuerpo y
   medir.
3. **Histéresis de destino.** Un enemigo con rumbo camina a un punto que se mueve
   con el jugador **y** con hacia dónde mira el jugador, así que a intervalo fijo
   repatheaba siempre, aunque el destino se hubiera corrido diez centímetros. Un
   repath no es gratis: `set_move_target()` consulta el NavigationServer para
   bajar el punto al navmesh y después el agente recalcula el camino entero.
   Ahora sólo repathea si el destino se corrió más de `repath_tolerance`.
4. **Presupuesto de repath**, 6 por frame de física. El que no consigue turno
   reintenta al siguiente — 16 ms tarde sobre un intervalo de 200 ms.
5. **Snapshot del objetivo** una vez por frame en vez de una vez por enemigo.

### Los números

Máquina de medición: Windows 11, AMD Radeon integrada, d3d12, 1920x1080. **No es
la máquina de [PLAN_PERFORMANCE.md](PLAN_PERFORMANCE.md)** (ahí wave 10 daba 700
FPS); acá el mismo contenido da ~40. Los números de acá sirven como comparación
relativa entre configuraciones en el mismo equipo, no como absolutos.

Oleada 10, **42 enemigos vivos**, 20 s de muestreo:

| Configuración | min | avg | max |
|---|---|---|---|
| Sin director, sin tiradores flanqueando | 37–38 | 39.8 / 40.9 | 41 / 43 |
| Con director, tiradores flanqueando, sin histéresis | 18 | 23.1 | 26 |
| **Final** | 41 | **41.9 / 42.1** | 43 / 44 |

Lo importante de la tabla es la fila del medio: **el comportamiento nuevo, sin
las optimizaciones, costaba casi la mitad del framerate.** Que un Ranger flanquee
no es gratis, y sin la histéresis de destino esta rama habría sido una regresión
de performance disfrazada de mejora de IA. Con todo puesto queda por encima de la
línea de base **con 42 enemigos en vez de 27**, y el frame peor sube de 37 a 41,
que es el número que va a seguir importando fuera de este equipo.

### Bug encontrado midiendo

`tools/profile_elite_wave.gd` buscaba al jugador con
`_game.get_node("Player")`, y el jugador no está en la escena: lo instancia
`PlayerSpawnController` dentro de su contenedor cuando arranca el match. O sea que
**la invulnerabilidad nunca se aplicó**, y el único síntoma era un
`push_warning`. Con 27 enemigos el jugador aguantaba lo suficiente como para que
no se notara; con una oleada de masa se muere antes de que empiece el muestreo,
el arena queda vacía y la herramienta medía una escena sin enemigos —
alegremente, a 40 FPS. Ahora busca por grupo y reintenta hasta encontrarlo.

---

## 6. El Elite sale del pool

Está en el banco, no borrado: `data/enemies/elite.tres`, su hoja
`ActionEliteSlam` y sus tests siguen enteros. Lo que cambió es que ninguna wave lo
spawnea.

El motivo es el que el director dejó a la vista: es el único arquetipo cuya
pregunta al jugador **se superpone con la del Rusher** — viene de frente, pega
fuerte, y pide exactamente el mismo puesto que el melee básico sin aportar un
ángulo nuevo. Un elenco donde dos enemigos cobran el mismo recurso tiene uno de
más (§1 de [PLAN_ENEMY_BEHAVIOR.md](PLAN_ENEMY_BEHAVIOR.md)).

Las waves 5 y 10 siguen marcadas `is_elite_wave` y siguen siendo el pico de la
tanda, pero ahora son **olas de masa**: wave 5 pasa de 12 a 19 enemigos y wave 10
de 36 a 42. El `prewarm_count` del `EnemySpawner` sube a 48 para cubrirlas, que es
lo que el test `test_the_enemy_pool_covers_the_largest_wave` pinea.

La exclusión está **nombrada** en `test_wave_composition.gd` (`const BENCHED`),
no silenciada: sacar un arquetipo del juego cuesta una línea explícita, y el test
que exige que todo lo construido se use sigue corriendo para los otros siete.

---

## 7. Lo que no se hizo

- **No se tunearon números de balance.** Los `approach_bearing_weight` de Ranger,
  Healer y Summoner son nuevos (0.70, 0.55, 0.55) porque antes no pedían rumbo, y
  esos sí son de escritorio. Se juegan.
- **Un solo objetivo.** `_refresh_target()` toma el objetivo del primer enemigo
  vivo, porque hoy toda la horda pelea contra el mismo. Cuando existan facciones
  que se peleen entre sí (Gladiadores), el reparto pasa a ser por objetivo y ese
  campo se vuelve un diccionario. Está anotado en el código.
- **El slam del Elite no pide ficha.** No tiene sentido cablearlo mientras el
  arquetipo esté en el banco; entra en el rework.
- **La ficha de ataque sólo la usa el salto.** El disparo del Ranger y el frasco
  del Environmental podrían tener techo también, pero eso cambia el DPS de los
  arquetipos y es una decisión de balance, no de arquitectura.
