---
tags: [mayhem, plan, enemies, nice-to-have]
---

# MAYHEM — Nuevos tipos de enemigos (nice to have)

**Esta rama no entra en el entregable universitario.** Es una rama de features
a futuro, igual que `feat/coop-p2p`: se deja planteada y documentada para que el
trabajo esté listo para arrancar cuando haya tiempo, sin presionar el alcance de
la entrega.

Estado: **sólo plan**. No hay código en esta rama todavía, y no debería haberlo
hasta que las decisiones abiertas de §4 estén tomadas.

Base: `develop` @ `b76b80e`. Todo lo que dice "medido" abajo fue verificado
contra ese commit leyendo el código, no asumido.

---

## 0. Los cuatro agregados

| Enemigo | Rol en el combate | Dificultad de implementación |
|---|---|---|
| **Bomber** | Presión de área: obliga a soltar la posición | Baja |
| **Ranged Flyer** | Rompe la lectura horizontal del arena | **Alta** (no hay vuelo) |
| **Environmental** | Niega terreno, controla por dónde se puede pasar | Media |
| **Gladiadores** | Caos: tercera facción que pelea contra todos | **Muy alta** (ver §4) |

Las reglas del proyecto siguen valiendo enteras — tipado estricto, datos en
`.tres` y no en código, audio por `AudioPool`, colores desde `Tokens`, y
telegrafía obligatoria antes de todo ataque (CLAUDE.md 5.3). Ver el bloque de
reglas de [PLAN_BACKLOG_RESTANTE.md](PLAN_BACKLOG_RESTANTE.md) §0, que aplica
igual acá.

---

## 1. Lo que ya existe y hay que reusar

Nada de esto hay que construirlo:

- **`ActionTelegraph`** — la preparación (glow + sonido + `attack_windup`,
  cancelable por stagger). Es un leaf reusable a propósito; todo ataque nuevo se
  cuelga detrás de él en vez de reimplementar su propia telegrafía.
- **`HazardZone`** (`scripts/systems/hazard_zone.gd`) — volumen de daño con
  decal del tamaño exacto del daño y 0.6s de aviso. Radio, daño y duración son
  argumentos, no constantes, justamente porque el slam del Elite ya lo reusa.
  `ActionEliteSlam._leave_pool()` es el precedente de cómo se deja un charco.
- **Arco balístico resuelto** — `JumpLink.get_launch_velocity(from, to, gravity)`
  y `Enemy.start_leap()` resuelven un arco para caer en un punto exacto. Sirve
  igual para el salto del Bomber y para la parábola del frasco del Environmental.
- **`EnemySpawner.spawn_at(data, position)`** — spawn directo sin puerta ni
  telegrafía. Es el que usa el Summoner, y es el que usarían los Gladiadores si
  entran por evento en vez de por puerta.
- **`ObjectPool`** para todo lo de alta rotación, y **`attack_cooldown_jitter`**
  (de `feat/enemy-attack-variation-and-leap`) para que un grupo nuevo no ataque
  al unísono.

> **Dependencia:** el Bomber y los Gladiadores se apoyan en el salto
> (`Enemy.start_leap()`) y en el jitter de cadencia, que viven en
> `feat/enemy-attack-variation-and-leap` y **todavía no están en `develop`**.
> Esta rama sale de `develop`, así que hay que mergear esa primero o rebasar
> encima cuando se empiece a codear.

---

## 2. Los tres bloqueos arquitectónicos (medido)

Estos son el trabajo real. Ninguno de los cuatro enemigos es difícil por sí
mismo; son difíciles porque el código actual asume cosas que dejan de ser
ciertas.

### 2.1 El objetivo está cableado al jugador

`Enemy` no tiene concepto de "mi objetivo": tiene `get_player()`, que resuelve
el grupo `&"player"` (`enemy.gd:289`). Y de ahí cuelga todo:

- `get_player_position()`, `get_distance_to_player()`, `face_player()`
- `deal_melee_damage()` y `_check_leap_contact()` piden `get_player()` y le
  buscan el `HealthComponent`
- `fire_projectile()` apunta a `get_player_position()`
- Los leaves de Beehave: `action_chase_player`, `action_keep_distance`,
  `condition_player_in_range` (que mide con `get_distance_to_player()`)

**Sin una abstracción de objetivo no hay Gladiadores**, y tampoco hay enemigos
que se peleen entre sí de ninguna forma. Es el ítem más grande del plan y está
detallado en §4.2.

### 2.2 Un proyectil enemigo no puede tocar a un enemigo

`EnemyProjectile` enmascara `WORLD | PLAYER` y además verifica
`is_in_group(&"player")` antes de aplicar daño (`enemy_projectile.gd:43,55`).
O sea que hay **dos** filtros que hay que abrir, no uno. El daño entre NPCs
simplemente no existe hoy: las hitbox de los enemigos están en la capa `HITBOX`,
que sólo enmascaran los proyectiles del jugador.

Hay bits de capa libres (`PhysicsLayers` llega hasta `TRIGGER`, 1 << 11), así
que hay lugar para una capa de facción sin tocar las existentes.

### 2.3 No hay vuelo

`Enemy._steer()` hace `direction.y = 0.0` (`enemy.gd:519`): el movimiento es
estrictamente horizontal, y la altura la maneja sólo la gravedad más los saltos
balísticos, que siempre terminan aterrizando. Un `NavigationAgent3D` sobre un
navmesh horneado tampoco da altura.

El Ranged Flyer necesita un **modo de movimiento** alternativo, no un ajuste de
número. Ver §3.2.

---

## 3. Los tres primeros enemigos

### 3.1 Enemy Bomber

**Fantasía:** te obliga a soltar la posición. No mata por daño puro, mata porque
te empuja a moverte hacia donde están los otros.

- Arquetipo nuevo en el enum `Archetype` + `data/enemies/bomber.tres` + árbol
  `scenes/enemies/ai/tree_bomber.tscn`.
- Se acerca, telegrafía largo (es la clave: el aviso tiene que ser proporcional
  al daño, y este pega fuerte), y explota en un radio.
- Reusa `HazardZone` con `duration` corta para la explosión, o un
  `Area3D` de un solo tick si se quiere que sea instantánea.
- **Decisión de diseño:** ¿explota al morir también? Un bomber que explota
  cuando lo matás premia matarlo lejos y castiga el cuerpo a cuerpo, que es un
  buen contrapeso al Rusher. Pero hay que cuidar que no se sienta injusto: si
  explota al morir, el radio tiene que dibujarse igual que cualquier hazard.

**Riesgo:** con `projectiles_per_shot` y el slam del Elite ya existiendo, el
Bomber puede quedar sintiéndose como "un Elite más chico". Lo que lo separa es
que se **autodestruye** — es un recurso que el enemigo gasta, no un ataque
repetible.

### 3.2 Ranged Flyer

**Fantasía:** rompe la lectura horizontal del arena. Te obliga a mirar para
arriba, que es algo que el juego hoy nunca pide.

Es el más caro de los tres primeros, por §2.3. Necesita:

- Un modo de movimiento que no dependa del navmesh: mantener una altura objetivo
  sobre el terreno (raycast hacia abajo), moverse en línea recta hacia un punto
  y esquivar geometría con probes, sin `NavigationAgent3D`.
- Que la gravedad no le aplique. Hoy `_physics_process` se la aplica a todo lo
  que no está en el piso.
- `preferred_distance` ya existe y sirve para que se mantenga lejos, igual que
  el Ranger.

**Cuidado con el navmesh:** `AGENT_RADIUS = 0.85` en el bake está dimensionado
para el Elite. Un volador no participa del navmesh, así que no lo afecta — pero
tampoco puede usar `JumpLink`, ni obstruction handling, ni nada de §2.3 del doc
de enemigos. Conviene que el modo de vuelo sea una rama temprana en
`_physics_process`, hermana de `_is_leaping`, y no un caso especial embutido en
`_steer()`.

**Test que va a hacer falta:** que un volador mantenga altura sobre terreno
irregular y no se hunda en una rampa ni se clave en el techo.

### 3.3 Environmental Enemy

**Fantasía:** no te ataca a vos, le pelea al terreno. Decide por dónde no podés
pasar.

Tira frascos en parábola (reusando el solver balístico de §1) que al aterrizar
dejan una zona. Dos tipos de frasco:

- **Frasco de hazard** — `HazardZone` tal cual, ya existe entera. Trabajo casi
  nulo: instanciar, `setup(damage, radius, duration)`, listo.
- **Frasco de atrapado** — zona que inmoviliza al jugador un tiempo si la pisa.
  **Esto no existe y es lo único caro de este enemigo.**

Sobre el frasco de atrapado, dos advertencias serias:

1. **Quitarle el control al jugador es lo más hostil que puede hacer un shooter.**
   El juego se apoya en movilidad (dash, gancho, deslizada); congelar eso pelea
   con el pilar de movimiento. Recomendación fuerte: que **no sea inmovilización
   total** sino una ralentización fuerte con salida — que el dash o el gancho
   permitan romperla, o que se salga rompiendo a los golpes. Que siempre haya
   algo que hacer.
2. Necesita una capacidad nueva del lado del jugador (`MovementComponent`): hoy
   `apply_slow()` existe en `Enemy`, no en el jugador. Hay que ver cómo se
   expresa sin romper `test_view_bob_can_never_move_the_aim` ni la sensación de
   movimiento.

La zona tiene que respetar la misma ley que `HazardZone`: **el decal es la
promesa**, el área que atrapa es exactamente la dibujada, y hay aviso antes de
armarse.

---

## 4. Gladiadores — la tercera facción

Este es el que hay que planear con cuidado, y el que puede salir mal de las
formas más interesantes.

**Fantasía:** el arena deja de ser "vos contra la horda" y pasa a ser un lugar
donde están pasando cosas sin vos. Los Gladiadores te matan si te ven, pero
también se matan con los enemigos, y eso genera caos que podés leer y explotar.

### 4.1 Por qué es caro: el modelo de facciones

Hoy hay dos bandos implícitos y hardcodeados: el jugador, y todo lo demás. Los
Gladiadores introducen un **tercer bando**, y eso convierte varias constantes en
variables.

Lo mínimo:

```
Facción      Hostil a
-----------  ------------------------
PLAYER       HORDE, GLADIATOR
HORDE        PLAYER, GLADIATOR
GLADIATOR    PLAYER, HORDE
```

Es decir: **todos contra todos**. Que es exactamente el punto — el caos sale de
ahí, no de un aliado temporal.

### 4.2 Abstracción de objetivo (el trabajo de fondo)

Reemplazar el cableado de §2.1 por algo como:

- `EnemyData.faction` (enum) — a qué bando pertenece este arquetipo.
- `Enemy.get_target() -> Node3D` — devuelve el objetivo actual, que puede ser el
  jugador **o** otro `Enemy`. `get_player()` queda como caso particular.
- `Enemy.get_distance_to_target()`, `face_target()`, etc. — los leaves de Beehave
  pasan a hablar de "target" y no de "player".
- Una política de selección: probablemente **el hostil más cercano**, con
  histéresis para que no cambie de objetivo cada frame (ver 4.4).

**Compatibilidad:** los cinco arquetipos actuales quedan en la facción `HORDE`
y su objetivo se resuelve siempre al jugador, así que su comportamiento no
cambia. Esto es importante — la refactorización tiene que ser demostrablemente
neutral para lo que ya existe. Los tests actuales de `test_enemy_behavior.gd`
son la red: si pasan sin tocarlos, la abstracción no rompió nada.

Además hay que abrir §2.2: capa/máscara por facción para que un proyectil de la
horda pueda pegarle a un Gladiador, y el filtro `is_in_group("player")` tiene
que pasar a ser una pregunta de facción.

### 4.3 Decisiones abiertas — necesitan tu llamada

Ninguna de estas la debería decidir yo solo, porque las cuatro cambian a qué se
parece el juego:

1. **¿Quién cobra la recompensa?** Si un Gladiador mata a un enemigo, ¿el
   jugador recibe la moneda? Si sí, esconderse es rentable. Si no, el jugador
   pierde economía cada vez que los Gladiadores "le roban" muertes, lo que
   castiga algo que no controla.
2. **¿Cuentan para el fin de oleada?** `WaveManager` cuenta enemigos vivos. Si
   los Gladiadores cuentan, esconderse limpia la ola. Si no cuentan, pueden
   quedar dando vueltas cuando la ola ya terminó.
3. **¿Entran por puerta o por evento?** Por puerta (`EnemySpawner.spawn`) usan la
   telegrafía de spawn que ya existe. Por evento (`spawn_at`) aparecen en medio
   del arena y son más una irrupción.
4. **¿Aparecen en oleadas normales o son un modificador de ola?** Un tipo de ola
   "arena de gladiadores" es más fácil de balancear y más legible que meterlos
   de a poco en cualquier ola.

### 4.4 Riesgos concretos, y qué mirar

- **Estrategia degenerada: esconderse y esperar.** Es *el* riesgo. Si los
  Gladiadores limpian la ola mientras el jugador se queda atrás de una columna,
  el juego se juega solo. Contramedidas posibles: que la recompensa dependa de
  participar (daño hecho), que los Gladiadores prioricen fuerte al jugador
  cuando lo ven, o que la ola tenga par time (ya existe, `WaveData.par_time`) y
  esconderse cueste el bono.
- **Ping-pong de objetivo.** Con "el más cercano" puro, dos hostiles casi
  equidistantes hacen que el bicho gire en el lugar. Necesita histéresis: no
  cambiar de objetivo salvo que el nuevo esté significativamente más cerca, o
  hasta que pase un tiempo mínimo.
- **Costo N².** Hoy nadie busca objetivos: el jugador es una consulta de grupo
  cacheada. Con selección por cercanía, cada Gladiador recorre a todos los
  hostiles. Con 27 enemigos en una ola elite eso escala mal. Ya hay dos
  precedentes de cómo se resolvió esto en este repo: el array estático `_flock`
  y el `_separation_timer` desfasado — la selección de objetivo debería
  recalcularse cada N ms y desfasada por bicho, no cada frame.
- **La separación no sabe de facciones.** `_flock` es estático y contiene todos
  los enemigos vivos, así que un Gladiador y un Rusher se van a empujar como si
  fueran del mismo bando. Puede estar bien (son cuerpos, se estorban) o puede
  quedar raro. Decisión chica, pero hay que tomarla a propósito.
- **Legibilidad.** El jugador tiene que poder responder "¿quién le está pegando
  a quién?" de un vistazo, en medio de una ola. Esto es ley de color
  (`Tokens`, ver [09 Design Tokens and Color Law](Mayhem/09%20Design%20Tokens%20and%20Color%20Law.md)):
  los Gladiadores necesitan un color propio que no se confunda con el rojo de la
  horda ni con el acento de hazard. Silueta distinta también (CLAUDE.md 5.3).
- **Audio.** Cada arquetipo tiene que ser identificable sólo por sonido
  (CLAUDE.md 6). Con tres bandos peleando, el mix se llena — y ya hay un
  hallazgo previo de que `AudioPool` descarta sonidos sin prioridad cuando se
  satura (ver [HANDOFF_FEEL_AND_FIXES.md](HANDOFF_FEEL_AND_FIXES.md) §3). **Los
  Gladiadores van a empeorar eso.** Conviene cerrar el ítem de prioridad de voces
  antes que esto, no después.

### 4.5 Qué sería "terminado"

- Los cinco arquetipos existentes se comportan **exactamente** igual que antes
  (los tests actuales pasan sin modificarse).
- Un Gladiador y un Rusher en el arena se pelean entre ellos sin el jugador
  presente.
- El jugador puede pegarle a ambos, y ambos pueden pegarle al jugador.
- Un test de que la selección de objetivo no hace ping-pong.
- Un test de que la facción decide el daño: un proyectil de la horda le pega a
  un Gladiador y no a otro miembro de la horda.

---

## 5. Orden sugerido

El orden importa porque los bloqueos de §2 se comparten.

1. **Bomber** (S) — no toca ningún bloqueo, entrega valor solo, y valida que
   agregar un arquetipo nuevo hoy sea barato.
2. **Environmental, sólo frasco de hazard** (S) — `HazardZone` ya está entera.
3. **Prioridad de voces en `AudioPool`** (M) — pendiente previo, y precondición
   real para que tres facciones no se pisen el audio.
4. **Abstracción de objetivo + facciones** (L) — §4.2. Es el trabajo grande, y
   hay que hacerlo con los tests actuales como red.
5. **Gladiadores** (L) — encima de 4, y después de que las decisiones de §4.3
   estén tomadas.
6. **Ranged Flyer** (L) — independiente de todo lo demás; se puede adelantar si
   se prefiere, pero es el que más riesgo de sensación tiene.
7. **Environmental, frasco de atrapado** (M) — último a propósito: es el que más
   puede pelear con el pilar de movilidad, y conviene decidirlo jugando.

## 6. Recordatorio

Nada de esto está empezado. Cuando se arranque: mergear o rebasar
`feat/enemy-attack-variation-and-leap` primero (§1), y correr `gut` después de
cada paso — la suite está en 396 verdes sobre esa rama.
