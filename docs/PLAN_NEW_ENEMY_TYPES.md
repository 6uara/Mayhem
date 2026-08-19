---
tags: [mayhem, plan, enemies, nice-to-have]
---

# MAYHEM — Nuevos tipos de enemigos (nice to have)

**Esta rama no entra en el entregable universitario.** Es una rama de features a
futuro, igual que `feat/coop-p2p`: se deja planteada y documentada para que el
trabajo esté listo para arrancar cuando haya tiempo, sin presionar el alcance de
la entrega.

Estado: **sólo plan**. No hay código en esta rama todavía.

Base: `develop` @ `b76b80e`. Todo lo marcado "medido" fue verificado leyendo el
código contra ese commit, no asumido.

---

## 0. Los cuatro agregados

| Enemigo | Rol en el combate | Dificultad |
|---|---|---|
| **Bomber** | Presión de área con espoleta: te obliga a decidir *dónde* revienta | Media |
| **Ranged Flyer** | Rompe la lectura horizontal del arena | **Alta** (no hay vuelo) |
| **Environmental** | Niega terreno, decide por dónde no se pasa | Media |
| **Gladiadores** | Tercera facción: caos, competencia por botín | **Muy alta** |

Valen las reglas del proyecto: tipado estricto, balance en `.tres` y no en
código, audio por `AudioPool`, colores desde `Tokens`, y telegrafía obligatoria
antes de todo ataque (CLAUDE.md 5.3). Ver el bloque de reglas de
[PLAN_BACKLOG_RESTANTE.md](PLAN_BACKLOG_RESTANTE.md) §0.

---

## 1. Lo que ya existe y hay que reusar

- **`ActionTelegraph`** — la preparación (glow + sonido + `attack_windup`,
  cancelable por stagger). Todo ataque nuevo se cuelga detrás de él.
- **`HazardZone`** — volumen de daño con decal del tamaño exacto del daño y 0.6s
  de aviso. Radio, daño y duración son argumentos, porque el slam del Elite ya lo
  reusa (`ActionEliteSlam._leave_pool()` es el precedente).
- **Arco balístico resuelto** — `JumpLink.get_launch_velocity()` y
  `Enemy.start_leap()`. Sirve para el frasco del Environmental.
- **`AmmoPickup`** — el molde del botín del piso: `Area3D`, disponibilidad,
  color desde `Tokens.WORLD_PICKUP`, sonido idle.
- **`EnemySpawner.spawn_at(data, position)`** — spawn directo sin puerta.
- **`ObjectPool`**, y **`attack_cooldown_jitter`** para que un grupo nuevo no
  ataque al unísono.

> **Dependencia:** el Bomber y los Gladiadores se apoyan en el salto
> (`Enemy.start_leap()`) y en el jitter de cadencia, que viven en
> `feat/enemy-attack-variation-and-leap` y **todavía no están en `develop`**.
> Hay que mergear esa rama primero, o rebasar encima.

---

## 2. Los bloqueos arquitectónicos (medido)

Ninguno de los cuatro enemigos es difícil por sí mismo. Son difíciles porque el
código actual asume cuatro cosas que dejan de ser ciertas.

### 2.1 El objetivo está cableado al jugador

`Enemy` no tiene concepto de "mi objetivo": tiene `get_player()`, que resuelve el
grupo `&"player"` (`enemy.gd:289`). De ahí cuelga todo — `get_distance_to_player()`,
`face_player()`, `deal_melee_damage()`, `_check_leap_contact()`,
`fire_projectile()`, y los leaves `action_chase_player`, `action_keep_distance`,
`condition_player_in_range`.

### 2.2 Un proyectil enemigo no puede tocar a un enemigo

`EnemyProjectile` enmascara `WORLD | PLAYER` **y además** verifica
`is_in_group(&"player")` antes de aplicar daño (`enemy_projectile.gd:43,55`).
Son dos filtros, no uno.

Hay bits de capa libres (`PhysicsLayers` llega a `TRIGGER`, 1 << 11).

### 2.3 No hay vuelo

`Enemy._steer()` hace `direction.y = 0.0` (`enemy.gd:519`). La altura sale sólo
de la gravedad y de saltos balísticos que siempre aterrizan.

### 2.4 No existe atribución de muertes

**Este es nuevo y es el que habilita toda la economía de abajo.** Hoy `Enemy`
emite `EventBus.enemy_killed(id, position, reward)` al morir
(`enemy.gd:1138`), y `EconomyManager._on_enemy_killed()` suma la moneda **sin
preguntar quién mató** (`economy_manager.gd:97`).

O sea: no hay concepto de "asesino". La regla de last-hit no es un ajuste de
balance, es un sistema que no existe.

---

## 3. Bomber

**Fantasía:** una cuenta regresiva con patas. La pregunta no es "¿escapo?" sino
"¿dónde lo hago explotar?".

**Espoleta (decidido):**

1. Al entrar en rango del jugador, **arma** la espoleta: X segundos, con aviso
   claro (sonido de espoleta + telegrafía creciente).
2. **Alejarse no la desarma.** Una vez armada, la explosión va a pasar sí o sí.
3. Si muere antes de que termine la cuenta, **explota en ese momento**, donde
   esté.

Eso lo convierte en un recurso que el jugador puede usar: matarlo parado al lado
de un grupo es una jugada, no un accidente. Se conecta directo con §5.4.

**Es la única fuente de fuego amigo dentro de la horda** (ver la matriz en §5.2):
su explosión lastima a todo el mundo, incluidos otros miembros de la horda.

Trabajo: arquetipo nuevo en el enum + `data/enemies/bomber.tres` + árbol
`tree_bomber.tscn`. La explosión reusa `HazardZone` con duración corta, o un
`Area3D` de un solo tick.

**Hueco abierto:** si un Gladiador mata a un Bomber que nunca llegó a armarse
(nunca vio al jugador), ¿explota igual? Asumo que **sí** — es una bomba, y que
explote siempre es más legible que una regla condicional. Confirmar al construir.

---

## 4. Ranged Flyer y Environmental

### 4.1 Ranged Flyer

El más caro de los tres simples, por §2.3. Necesita un modo de movimiento que no
dependa del navmesh: mantener altura objetivo sobre el terreno (raycast hacia
abajo), moverse en línea recta y esquivar geometría con probes, sin
`NavigationAgent3D` y sin gravedad.

Conviene que el vuelo sea una rama temprana en `_physics_process`, hermana de
`_is_leaping`, y **no** un caso especial embutido en `_steer()`. Un volador no
participa del navmesh, así que tampoco usa `JumpLink` ni obstruction handling.

`preferred_distance` ya existe y sirve para que se mantenga lejos, igual que el
Ranger.

**Test necesario:** que mantenga altura sobre terreno irregular sin hundirse en
una rampa ni clavarse en el techo.

### 4.2 Environmental

Tira frascos en parábola (reusando el solver balístico) que al aterrizar dejan
una zona. Dos tipos:

- **Frasco de hazard** — `HazardZone` tal cual. Trabajo casi nulo.
- **Frasco de atrapado** — zona que inmoviliza. **Lo único caro.**

Dos advertencias sobre el frasco de atrapado:

1. **Quitarle el control al jugador es lo más hostil que puede hacer un shooter.**
   El juego se apoya en movilidad (dash, gancho, deslizada) y congelar eso pelea
   con el pilar de movimiento. Recomendación fuerte: que no sea inmovilización
   total sino ralentización fuerte **con salida** — que el dash o el gancho la
   rompan, o que se salga a los golpes. Que siempre haya algo que hacer.
2. Necesita una capacidad nueva del lado del jugador: `apply_slow()` hoy existe
   en `Enemy`, no en el jugador.

La zona respeta la ley de `HazardZone`: **el decal es la promesa**, el área que
atrapa es exactamente la dibujada, y avisa antes de armarse.

---

## 5. Gladiadores

### 5.1 Qué son

Tres unidades fijas que **están en el arena desde el principio de la run**. No
son spawn de oleada: son habitantes. Si muere uno, **no vuelve a entrar otro** —
son un recurso que se agota para siempre.

Eso crea la tensión central del arquetipo: cada Gladiador que matás es un
competidor menos por el botín, pero también un aliado de conveniencia menos
contra la horda. Y la decisión es permanente.

- **Cantidad: 3.** Suficiente para que pasen cosas lejos del jugador y para que
  perder uno se note, sin volver ilegible un arena que ya tiene 27 enemigos en
  una ola elite.
- **Regeneran lento y constante durante toda la run**, incluso en combate.
  Herirlos sin rematarlos no sirve de nada: hay que comprometerse a la muerte.
- **No cuentan para terminar la oleada**, y se quedan en el arena entre olas y
  durante la tienda. Son amenaza ambiental, no objetivo obligatorio.

> **Restricción de tuning que sale de la regeneración:** la tasa tiene que ser
> lo bastante lenta como para que fuego concentrado los mate, y lo bastante
> rápida como para que el daño de goteo de una ola entera no los borre por
> acumulación. Si esa ventana resulta ser muy angosta al probar, la alternativa
> es curación completa entre olas.

### 5.2 Facciones y matriz de daño

Tres bandos, todos contra todos:

| Atacante \ Recibe | Jugador | Horda | Gladiador |
|---|---|---|---|
| **Jugador** | — | sí | sí |
| **Horda** | sí | **solo explosión de Bomber** | sí |
| **Gladiador** | sí | sí | sí |

La única celda rara es horda→horda, y es a propósito: el fuego amigo dentro de la
horda existe **exclusivamente** por la explosión del Bomber. Un Rusher no puede
lastimar a otro Rusher de un golpe, ni un Ranger errarle al jugador y pegarle a
un compañero.

Implementación: `EnemyData.faction` (enum), y abrir los dos filtros de §2.2 —
capa/máscara por facción, y el `is_in_group("player")` pasa a ser pregunta de
facción.

### 5.3 Selección de objetivo: cercanía ponderada por net worth

Todos (horda y Gladiadores) atacan **al hostil más cercano, ponderado por su net
worth**. El que va ganando se vuelve el más cazado.

```
prioridad(objetivo) = distancia / (1 + peso * net_worth_normalizado)
                      → se elige la prioridad más baja
```

Esto resuelve solo el problema de esconderse detrás de los Gladiadores: si no
matás ni juntás, sos poco atractivo como blanco — pero tampoco cobrás nada. La
seguridad tiene el precio exacto de la pobreza, sin ninguna regla extra.

**El net worth se mide por moneda efectivamente juntada del piso, no por muertes
hechas.** Eso agrega la mejor capa táctica del sistema: el botín tirado en el
piso es seguro, y levantarlo te pinta el blanco. Decidir *cuándo* enriquecerte
pasa a ser una decisión de combate.

- **Se reinicia cada oleada.** Así la presión sube dentro de la ola y se vuelve
  a abrir la competencia en la siguiente, en vez de dejar al jugador competente
  bajo fuego permanente desde la ola 4.
- **Legibilidad (obligatoria):** el que lidera lleva una marca visible **en el
  mundo**, sobre sí mismo — aura, corona o tinte, desde `Tokens`. El jugador
  tiene que poder ver quién es el blanco sin mirar la HUD, incluido cuando el
  blanco es él. Sin esto el sistema entero se lee como aggro aleatorio.

**Histéresis:** con cercanía pura, dos hostiles casi equidistantes hacen que el
bicho gire en el lugar. No se cambia de objetivo salvo que el nuevo esté
significativamente mejor, o hasta que pase un tiempo mínimo.

**Costo:** hoy nadie busca objetivos (el jugador es una consulta de grupo
cacheada). Con selección por cercanía cada entidad recorre a todos los hostiles,
y con 27 enemigos eso escala mal. Los dos precedentes del repo son el array
estático `_flock` y el `_separation_timer` desfasado: **recalcular cada N ms y
desfasado por bicho**, nunca cada frame.

### 5.4 Economía: solo cobrás lo que rematás

La regla: **el jugador cobra únicamente las muertes en las que dio el golpe
final.** Requiere el sistema de atribución que hoy no existe (§2.4).

Para que eso no genere una espiral de muerte — te roban muertes, cobrás menos,
te debilitás, te roban más — el botín no se evapora:

1. Una muerte hecha por un Gladiador **suelta moneda al piso**, con vida útil de
   unos segundos.
2. Esa moneda hay que **ir a buscarla**, normalmente al peor lugar del arena.
3. **Los Gladiadores también la juntan**, y les sube su propio net worth. Es una
   carrera, no un depósito que espera.
4. Matar a un Gladiador **suelta todo su net worth acumulado** como botín. No se
   transfiere al asesino: un Gladiador gordo es un banco andante, y cazarlo es
   una decisión con recompensa concreta.

Así la regla se mantiene intacta — no cobrás por no hacer nada — pero perder una
muerte pasa a ser una decisión de riesgo en vez de una pérdida seca.

**Cadena del Bomber:** si el jugador mata a un Bomber y la explosión mata tres de
la horda, **esas tres son del jugador**. Requiere propagar el origen del daño a
través de la explosión, y es lo que premia elegir dónde matarlo.

Trabajo concreto:

- `EventBus.enemy_killed` pasa a llevar **quién** mató.
- `EconomyManager._on_enemy_killed()` deja de pagar incondicionalmente.
- `CurrencyPickup` nuevo, con `AmmoPickup` de molde, pero con chequeo de facción
  en vez de `is_in_group("player")` porque los Gladiadores también lo levantan.
- Propagación de origen de daño para explosiones (y para cualquier hazard que un
  actor cause).

### 5.5 Riesgos que quedan vivos

- **Audio.** Cada arquetipo tiene que ser identificable sólo por sonido
  (CLAUDE.md 6). Con tres bandos peleando el mix se llena, y ya hay un hallazgo
  previo de que `AudioPool` descarta sonidos sin prioridad cuando se satura (ver
  [HANDOFF_FEEL_AND_FIXES.md](HANDOFF_FEEL_AND_FIXES.md) §3). **Los Gladiadores
  lo van a empeorar.** Conviene cerrar el ítem de prioridad de voces antes, no
  después.
- **Legibilidad general.** Con tres bandos, el jugador tiene que responder
  "¿quién le pega a quién?" de un vistazo. Color propio para los Gladiadores que
  no se confunda con el rojo de la horda ni con el acento de hazard, y silueta
  distinta.
- **La separación no sabe de facciones.** `_flock` es estático y tiene todos los
  enemigos vivos, así que un Gladiador y un Rusher se empujan como si fueran del
  mismo bando. Puede estar bien (son cuerpos) o quedar raro; decidirlo a
  propósito.
- **El jugador como espectador.** Si el caos es demasiado autosuficiente, se
  mira en vez de jugarse. El net worth lo mitiga (el que gana es cazado), pero
  hay que verificarlo jugando.

### 5.6 Qué sería "terminado"

- Los cinco arquetipos existentes se comportan **exactamente** igual que antes:
  los tests actuales de `test_enemy_behavior.gd` pasan **sin modificarse**. Esa
  es la red de la refactorización de objetivo.
- Un Gladiador y un Rusher se pelean sin el jugador presente.
- El jugador cobra una muerte propia y **no** cobra una de un Gladiador.
- El botín de una muerte ajena se puede juntar, y un Gladiador puede ganártelo.
- Un test de que la selección de objetivo no hace ping-pong.
- Un test de la matriz de §5.2: una explosión de Bomber lastima horda, y un
  disparo de Ranger no.
- Un test de que el net worth se reinicia entre olas.

---

## 6. Orden sugerido

El orden importa porque los bloqueos se comparten.

1. **Bomber** (M) — no toca ningún bloqueo salvo el fuego amigo de su explosión;
   valida que agregar un arquetipo hoy sea barato.
2. **Environmental, sólo frasco de hazard** (S) — `HazardZone` ya está entera.
3. **Atribución de muertes** (M) — §2.4. Es independiente de los Gladiadores y
   mejora el juego solo: que la moneda venga de lo que hacés es correcto igual.
4. **Prioridad de voces en `AudioPool`** (M) — pendiente previo y precondición
   real para tres facciones.
5. **Abstracción de objetivo + facciones** (L) — §2.1 y §2.2, con los tests
   actuales como red.
6. **Gladiadores** (L) — encima de 3 y 5: facciones, net worth, botín, marca del
   líder.
7. **Ranged Flyer** (L) — independiente de todo lo demás.
8. **Environmental, frasco de atrapado** (M) — último a propósito: es el que más
   puede pelear con el pilar de movilidad, y conviene decidirlo jugando.

---

## 7. Registro de decisiones

Tomadas (no re-discutir sin motivo nuevo):

- Recompensa sólo por golpe final propio; el botín ajeno cae al piso y se disputa.
- El net worth mide **moneda juntada**, no muertes; se reinicia por oleada.
- Objetivo = más cercano ponderado por net worth, para todos los bandos.
- Matar a un Gladiador suelta su net worth como botín; no se transfiere.
- Los Gladiadores juntan botín y compiten por él.
- Marca del líder **en el mundo**, no en la HUD.
- 3 Gladiadores, fijos desde el inicio, sin reaparición, con regeneración lenta.
- No cuentan para terminar la oleada y se quedan en el arena.
- Fuego amigo en la horda **sólo** por explosión de Bomber.
- La espoleta del Bomber no se desarma huyendo; morir la adelanta.
- La cadena de la explosión se le acredita a quien la causó.

Abiertas:

- ¿Un Bomber que nunca se armó explota al morir? (asumo que sí, §3)
- Tasa exacta de regeneración de los Gladiadores (§5.1) — puede forzar el cambio
  a curación completa entre olas.
- Peso exacto del net worth contra la distancia en la fórmula de §5.3.
- Si la separación (`_flock`) debe respetar facciones.

## 8. Recordatorio

Nada de esto está empezado. Al arrancar: mergear o rebasar
`feat/enemy-attack-variation-and-leap` primero (§1), y correr `gut` después de
cada paso.
