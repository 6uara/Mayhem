---
tags: [mayhem, plan, enemies, nice-to-have]
---

# MAYHEM — Nuevos tipos de enemigos (nice to have)

**Esta rama no entra en el entregable universitario.** Es una rama de features a
futuro, igual que `feat/coop-p2p`: se deja planteada y documentada para que el
trabajo esté listo para arrancar cuando haya tiempo, sin presionar el alcance de
la entrega.

Estado: **el Bomber y el Environmental están construidos** (pasos 1 y 2 de §6).
El resto sigue siendo plan.

Base: `develop` @ `7722071`. Todo lo marcado "medido" fue verificado leyendo el
código contra ese commit, no asumido.

**El Gladiador va en su propia rama**, que sale de ésta cuando la infraestructura
compartida esté lista — es decir después de los pasos 3, 4 y 5 de §6 (atribución
de muertes, prioridad de voces, abstracción de objetivo + facciones). Esos tres
mejoran el juego por sí solos y tocan el núcleo de `enemy.gd`, así que si viajaran
en la rama del Gladiador chocarían de frente con los arquetipos simples, que tocan
los mismos archivos. La rama del Gladiador va a contener sólo diseño de arquetipo:
los tres habitantes, el net worth, el botín disputado y la marca del líder.

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

> **Dependencia, ya resuelta:** el salto (`Enemy.start_leap()`) y el jitter de
> cadencia están en `develop` desde entonces, así que no hay nada que mergear
> antes de arrancar.

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

## 3. Bomber — **construido**

Lo de abajo era el plan y se cumplió tal cual, salvo por lo anotado al final de
la sección. Detalle de implementación en
[05 Enemies and AI](Mayhem/05%20Enemies%20and%20AI.md) §The fuse; los tests
viven en `tests/integration/test_bomber.gd`.

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

### 3.1 Lo que cambió al construirlo

- **La explosión no reusa `HazardZone`.** Se probó y está mal: un hazard avisa
  0.6s antes de armarse, y una explosión ya avisó — la espoleta *fue* el aviso, y
  duró 2.2s. Un charco con 0.6s de gracia después de que la bomba revienta no es
  una explosión. Quedó como `Explosion` (`scripts/actors/explosion.gd`), un solo
  tick, sin aviso propio. Lo que sí hereda es la ley: el radio que lastima es el
  que se dibujó.
- **Apareció una mitad visual que el plan no tenía.** "¿Dónde lo hago explotar?"
  no se puede contestar si no se ve dónde alcanza, así que el Bomber arrastra un
  anillo en el piso (`FuseRing`) del tamaño exacto de `explosion_radius`, que
  parpadea cada vez más rápido — el mismo idioma que la plataforma que se
  desvanece. Sin eso el arquetipo es un Rusher que pega más fuerte.
- **`Enemy` no pregunta por arquetipo.** La espoleta entera cuelga de
  `EnemyData.has_fuse`, así que cualquier arquetipo futuro que quiera explotar lo
  consigue prendiendo un flag. Los Gladiadores van a necesitar exactamente esto.
- **Se corrigió de paso la altura de las mallas primitivas.** Estaban clavadas a
  `y = 0.9` en `enemy.tscn` — media cápsula de 1.8m, correcta para ningún
  arquetipo existente. El Bomber mide 1m y habría flotado. Ahora se centran sobre
  la cápsula, que además es el pivote que `bake_enemy_meshes.gd` ya garantiza.
  Efecto colateral: el Elite y el Summoner dejaron de estar hundidos.

**Hueco cerrado:** un Bomber que nunca llegó a armarse **también explota** al
morir. Es lo que el plan asumía, y construirlo lo confirmó por un motivo que no
estaba escrito: la regla condicional no sólo se lee peor, además rompe la jugada.
Si matar un Bomber recién spawneado no revienta, el jugador no puede *elegir*
usarlo como bomba — sólo aprovecharlo cuando el juego ya decidió que estaba
armado.

**Sigue abierto:** el número. `fuse_time = 2.2`, `explosion_radius = 4.5`,
`explosion_damage = 55` y `move_speed = 5.4` están tuneados de escritorio, no
jugados. La relación entre los tres primeros y `fuse_arm_range` sí está atada por
un test; el *feel* no.

---

## 4. Ranged Flyer y Environmental

### 4.1 Ranged Flyer — **no construido**

**Requisito de posicionamiento (decidido, pendiente de implementar):** el Flyer
ataca **desde los costados**, y arranca **fuera del campo de visión del
jugador**. No debe aparecer nunca de frente.

La mitad barata ya está: el sistema de rumbos de §4.3 lo cubre con
`approach_bearing_degrees = 90` y `approach_bearing_mirrors = true`. Con el FOV
por defecto en 104° (o sea ±52°), un rumbo de 90° cae holgadamente fuera de
cámara, así que "por el costado" y "fuera de vista" son el mismo número — pero
son dos requisitos distintos y conviene no olvidarlo: si alguien sube el FOV a
120°, siguen siendo ±60° y 90 sigue alcanzando; a FOV 170° ya no.

La mitad cara sigue siendo §2.3, el vuelo. Y hay una interacción que todavía no
está resuelta: el sistema de rumbos actual trabaja sobre el navmesh, y un Flyer
no lo usa. `get_approach_position()` devuelve un punto en el plano; el Flyer va a
necesitar el mismo punto **más una altura**, resuelta por raycast contra el
terreno como dice §4.1 abajo.

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

### 4.2 Environmental — **frasco de hazard construido**

El frasco de hazard está hecho (paso 2 de §6). El de atrapado **no**, y sigue
siendo el paso 8: último a propósito. Detalle en
[05 Enemies and AI](Mayhem/05%20Enemies%20and%20AI.md) §The flask; tests en
`tests/integration/test_environmental.gd`.

El plan decía "trabajo casi nulo" y era cierto, pero por un motivo que no estaba
escrito: no fue que el charco ya existiera, fue que **el objeto que vuela también
existía**. `ThrownUtility` —la base de las tres utilidades del jugador— ya
resolvía el arco, el aterrizaje y el pool, y un frasco enemigo es literalmente el
mismo objeto con otra carga. Se le abrieron dos cosas, las dos casos en que la
versión del jugador era un caso particular tratado como el único:
`launch_with_velocity()` (una fuerza fija en una dirección es *una* forma de
conseguir una velocidad, no la única) y `hit_mask` (las utilidades del jugador
frenan contra enemigos a propósito; el frasco tiene que pasarles por encima).

El resto fue reusar `HazardZone` sin tocarlo, igual que el slam del Elite. Eso es
lo que hace que un arquetipo nuevo no pueda romper la telegrafía sin querer: el
aviso de 0.6s y el decal al radio exacto vienen incluidos.

**Decisión de diseño que salió al construirlo:** el Environmental no apunta al
jugador, apunta al piso bajo sus pies, y **errar es su modo normal de
funcionar**. Lo que hace es sacarte de donde estás parado. Un Environmental que
acierta y uno que erra por poco te obligan a moverte igual, y ahí está toda la
diferencia con el Ranger — si apuntara a pegar, sería un Ranger lento.

### 4.2.1 El plan original

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

## 4.3 De dónde llega cada arquetipo — **construido**

El problema no es cuántos enemigos hay, es **dónde**. Con todos llegando de
frente, la ola se resuelve girando lo menos posible: no hay que chequear la
espalda, no hay que reposicionarse, y dos arquetipos distintos se sienten iguales
porque ocupan el mismo sector de la pantalla.

`EnemyData` gana un rumbo preferido medido **desde la mirada del jugador**, no
desde una dirección del arena: `approach_bearing_degrees` (0 de frente, 90 al
costado, 180 por la espalda), `approach_bearing_weight` y
`approach_bearing_mirrors`. `Enemy.get_approach_position()` lo mezcla con el
carril lateral que ya existía.

| Arquetipo | Rumbo | Peso |
|---|---|---|
| Bomber | 180° (espalda, sin espejo) | 0.85 |
| Environmental | ±65° (flanco) | 0.6 |
| Ranged Flyer | ±90° — **pendiente**, ver §4.1 | — |
| Los cinco originales | 0° | **0.0** |

El peso 0 es el default y deja el comportamiento **idéntico** al anterior, que es
lo que permite meter esto sin tocar los cinco arquetipos existentes.
`test_an_archetype_without_a_bearing_is_untouched` es la red.

**Se desvanece de cerca, con la misma rampa que el carril lateral.** Un enemigo
que insiste en la espalda mientras el jugador gira se queda orbitando y no ataca
nunca. Flanquea de lejos y se compromete de cerca; sin eso, el Bomber es un
carrusel que no explota.

**El Environmental además se adelanta.** `ActionThrowFlask.lead_fraction` (0.65)
tira a donde el jugador va a estar cuando el frasco llegue. Tirarle a donde está
parado es tirarle a la espalda —para cuando aterriza ya se movió, y el charco
niega terreno que acababa de dejar—, y adelantarse el 100% es igual de malo por
el otro lado: se vuelve inesquivable corriendo derecho. En el medio el charco cae
*en el camino*, y la pregunta pasa a ser "sigo por acá o me desvío".

Sólo se adelanta la componente horizontal: un jugador saltando recibiría el
charco por encima o por debajo del piso, y el charco vive en el suelo.

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

1. ~~**Bomber** (M)~~ — **hecho.** Confirmó lo que se quería confirmar: agregar un
   arquetipo hoy es barato. Lo caro no fue el enemigo sino su telegrafía, que es
   más o menos la moraleja del proyecto entero.
2. ~~**Environmental, sólo frasco de hazard** (S)~~ — **hecho.** Salió más barato
   que el Bomber: `HazardZone` estaba entera y `ThrownUtility` también.
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

- Un Bomber que nunca se armó **explota igual** al morir (§3.1, cerrada al
  construir).
- La explosión es un nodo propio y no un `HazardZone` (§3.1).

- El Environmental apunta al piso y no al jugador; errar es su modo normal (§4.2).
- El frasco de hazard reusa `ThrownUtility` y `HazardZone` sin escribir ni el
  arco ni el área (§4.2).

Abiertas:

- Tuning del Bomber: espoleta, radio, daño y velocidad están sin jugar (§3.1).
- Tuning del Environmental: cadencia de 4.5s, arco de 1.1s, charco de 3.2m por
  5s. Tampoco jugado. El riesgo concreto es que tres Environmentals a la vez
  pavimenten el arena y el jugador se quede sin piso.
- Tasa exacta de regeneración de los Gladiadores (§5.1) — puede forzar el cambio
  a curación completa entre olas.
- Peso exacto del net worth contra la distancia en la fórmula de §5.3.
- Si la separación (`_flock`) debe respetar facciones.

## 8. Recordatorio

Correr `gut` después de cada paso (`pwsh tools/run_tests.ps1`). La suite está en
**484/484**, así que cualquier rojo es nuestro.

**Si aparece `Could not find type "X" in the current scope"` sobre una clase que
existe:** es el caché global de clases de Godot y no el código. Se arregla con
`pwsh tools/run_tests.ps1 -Import`. Falla feo — la clase entera deja de existir,
la escena que la usa se instancia como su tipo base, y los errores salen en
sesenta tests que no tienen nada que ver.
