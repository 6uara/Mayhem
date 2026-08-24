---
tags: [mayhem, plan, enemies, design, nice-to-have]
---

# MAYHEM — Comportamiento de los enemigos nuevos: recomendaciones

Los tres arquetipos simples (Bomber, Ranged Flyer, Environmental con sus dos
frascos) **ya están construidos y verdes**. Lo que sigue no es trabajo pendiente
de implementación sino de **diseño**: qué hacen los números que hoy están
tuneados de escritorio, dónde el comportamiento actual no hace la pregunta que el
arquetipo prometía, y en qué orden convendría probarlo.

Todo lo marcado **(medido)** se verificó leyendo el código y los `.tres` de esta
rama, no se asumió. Todo lo marcado **(recomendación)** es una decisión de diseño
abierta, con su motivo y con la perilla concreta que la aplica.

> **Estado: aplicado.** Las recomendaciones de §8 están construidas y verdes
> (568 tests). Lo que sigue se deja como estaba escrito —el diagnóstico y el
> porqué— con una marca **(aplicado)** en cada una y lo que cambió al hacerlo en
> §9. Lo único que no se hizo es §1.2, el arquetipo que cobra munición, que el
> propio documento pone fuera de alcance.
>
> Los números siguen sin jugarse. Aplicar no es tunear: lo que se cerró son los
> comportamientos que faltaban y los agujeros medidos, no el balance.

---

## 0. Alcance: los Gladiadores no entran acá

**Los Gladiadores se trabajan en una rama aparte, `feat/gladiators`, que sale de
`feat/new-enemy-types`.** Este documento cubre **sólo** los tres arquetipos
simples. Ninguna recomendación de acá depende de que exista una tercera facción,
y ninguna debería empujar trabajo hacia ella.

El motivo es el mismo que ya está anotado en
[PLAN_NEW_ENEMY_TYPES.md](PLAN_NEW_ENEMY_TYPES.md): la infraestructura compartida
—atribución de muertes, prioridad de voces, abstracción de objetivo y facciones—
**ya está terminada y mergeada acá**, así que la rama del Gladiador puede
contener sólo diseño de arquetipo (los tres habitantes, el net worth, el botín
disputado y la marca del líder) sin chocar con los arquetipos simples, que tocan
los mismos archivos de `enemy.gd`.

Consecuencia práctica para lo que sigue: cuando una recomendación de acá toque
algo que los Gladiadores van a usar (la matriz de daño, la separación, el mix de
audio), se dice explícitamente, pero **se decide para dos bandos**. Diseñar hoy
para tres es diseñar para algo que no se puede jugar todavía.

---

## 1. El marco: cada enemigo hace una pregunta

La forma más útil de mirar un elenco de enemigos no es "cuánto daño hace cada
uno" sino **qué recurso del jugador cobra**, y si dos arquetipos cobran el mismo,
uno de los dos sobra.

Es el marco con el que id Software describe el elenco de *Doom (2016)* y *Doom
Eternal*: cada demonio existe para exigir una respuesta específica, y el combate
es empujar hacia adelante resolviendo esas exigencias en cadena, no elegir
cobertura. Es también la lectura clásica del sandbox de *Halo* —el Grunt es
carne, el Jackal obliga a apuntar al hueco del escudo, el Elite obliga a
comprometerse— y el principio detrás de los Special Infected de *Left 4 Dead*,
donde cada especial existe para forzar una respuesta que el jugador solo no
tiene. Y es, al final, la formulación de Sid Meier: un juego es una serie de
decisiones interesantes. Un enemigo que no cambia ninguna decisión es decorado
con barra de vida.

### 1.1 Qué cobra cada uno hoy (medido)

| Arquetipo | Recurso que cobra | Pregunta que hace | Respuesta del jugador |
|---|---|---|---|
| Rusher | Espacio cercano | ¿aguanto o retrocedo? | matar o esquivar |
| Ranger | Atención | ¿lo dejo tirando? | romper línea de visión |
| Elite | Compromiso | ¿me quedo a pelear? | recursos y tiempo |
| Healer | Tiempo | ¿a quién mato primero? | prioridad de objetivos |
| Summoner | Tempo | ¿corto la fuente? | agresión hacia adelante |
| **Bomber** | **Posición ajena** | **¿dónde lo hago explotar?** | elegir el momento del disparo |
| **Flyer** | **Eje vertical** | **¿levanto la mirada?** | reapuntar arriba |
| **Environmental (ácido)** | **El piso donde estás** | **¿sigo por acá o me desvío?** | moverse |
| **Environmental (atrapado)** | **Cargas de dash** | **¿gasto una carga?** | dash o gancho |

Los tres nuevos cubren tres ejes que antes no tenía nadie, y **ninguno de los
tres duplica a un existente**. Eso es lo que salió bien y conviene no romperlo
tuneando.

### 1.2 El hueco que queda (recomendación)

Nadie en el elenco cobra **munición**. Con nueve arquetipos, todas las presiones
se resuelven moviéndose o apuntando, y la economía de balas nunca es la pregunta.
No es urgente y no es este plan, pero si algún día hay un décimo arquetipo, ése
es el hueco: un enemigo que sólo se resuelve gastando, no esquivando.

---

## 2. Bomber

Números de hoy (medido, `data/enemies/bomber.tres`): vida 55, velocidad 5.4,
espoleta 2.2s, radio 4.5m, daño 55, se arma a 6.0m, rumbo 180° con peso 0.85.

### 2.1 No está en ninguna oleada (medido) — **aplicado**

Buscar `bomber` en `data/waves/` no devuelve **nada**. El arquetipo está
construido, probado y documentado, y **el juego no lo spawnea nunca**. Es el
hallazgo más importante del documento y no es de balance: es un enemigo que no
existe.

**Recomendación:** debut aislado y temprano, siguiendo la práctica que *Left 4
Dead* y *Halo* usan para presentar unidades nuevas — la primera vez que ves algo,
lo ves solo, en una situación donde equivocarte no te mata.

- **Oleada 6, `count = 1`, `delay ≈ 12s`**: llega solo, con el resto de la ola ya
  resuelta o resolviéndose. El jugador ve un anillo en el piso, oye una espoleta
  y aprende qué son sin tres Rushers encima.
- **Oleada 7-8, `count = 2`, `interval ≈ 6s`**: ya no llegan juntos, pero pueden
  coincidir. Acá aparece la jugada de la cadena.
- **Oleada 9-10, `count = 2-3`, `interval ≈ 4s`**, mezclados.

### 2.2 Se arma mientras todavía viene por la espalda (medido) — **aplicado (opción A)**

La cuenta: el rumbo de aproximación se desvanece a partir de
`_approach_commit_distance()`, que para el Bomber vale `max(1.6 × 1.8, 2.5) =
2.88m`, con una rampa de `APPROACH_FADE = 4.0`. O sea que a 6.0m —que es
exactamente `fuse_arm_range`— el peso del rumbo todavía está en **0.78 de 0.85**.

Traducido: **el Bomber arma la espoleta mientras sigue comprometido a llegar por
detrás del jugador**, y su telegrafía visual (el `FuseRing`) está en el piso, o
sea fuera de pantalla cuando viene de atrás. El único aviso que queda es el
sonido de la espoleta.

Eso no es necesariamente injusto —*Serious Sam* construyó un arquetipo entero, el
kamikaze, sobre la idea de que el grito **es** la telegrafía, y funciona porque el
sonido es inconfundible y llega antes—, pero es una decisión que hoy está tomada
por accidente aritmético y no a propósito.

**Recomendación (elegir una, no las dos):**

- **A — el flanqueo termina antes de armar.** Que un arquetipo con espoleta
  comprometa su rumbo antes de `fuse_arm_range`: `_approach_commit_distance()`
  devuelve `max(fuse_arm_range, …)` cuando `has_fuse` está prendido. El Bomber
  entonces se pone de frente y **después** arma, y el anillo del piso hace su
  trabajo. Es la opción conservadora y la que respeta la telegrafía obligatoria.
- **B — el sonido es la telegrafía, y se asume.** Se deja el rumbo como está y se
  trata el `fuse_sound` como el grito del kamikaze: fuerte, inconfundible, con
  prioridad de voz alta (ya existe desde el paso 4), y sin nada más que compita
  con él en el mix. Es la opción con más carácter y la que más depende del audio.

Mi recomendación es **A**, por una razón que no es de justicia sino de fantasía:
la promesa del arquetipo es *"¿dónde lo hago explotar?"*, y esa pregunta necesita
que veas dónde está. Un Bomber que se arma detrás tuyo no hace esa pregunta, hace
"¿te acordaste de mirar atrás?", que es otra y peor.

### 2.3 El daño es plano dentro del radio (medido) — **aplicado**

`Explosion.detonate()` aplica `damage` completo a todo lo que esté dentro de
`radius` y tenga línea de visión. No hay caída con la distancia: 55 de daño a
0.5m y 55 a 4.4m.

Con 100 de vida base, **una explosión es media barra, y dos simultáneas son la
muerte**, sin importar cuánto te hayas alejado.

**Recomendación:** caída lineal desde el 100% en el centro hasta ~35% en el borde.
Es la convención de todos los shooters con explosivos, y no es cosmética:
convierte "esquivé" y "casi esquivé" en dos resultados distintos, que es
exactamente lo que enseña dónde está el borde. Hoy el jugador que sale rozando el
anillo cobra lo mismo que el que se quedó parado adentro, y de ahí no se aprende
nada. El anillo sigue siendo la promesa —el radio que lastima es el que se
dibujó—, sólo que ahora el borde también significa algo.

### 2.4 Lo que ya está bien y no hay que tocar

- **La espoleta no se desarma huyendo, y morir la adelanta.** Es lo que convierte
  al Bomber en un recurso del jugador en vez de un accidente, y es la mitad que
  conecta con la economía de §5.4 del plan de enemigos.
- **El parpadeo acelerando** (`TELL_BOMBER_FUSE_SLOW` → `_FAST`) reusa el idioma
  de la plataforma que se desvanece. El jugador ya sabe leerlo: no hace falta
  vocabulario nuevo.
- **Fuego amigo sólo por explosión.** La cadena (matar un Bomber junto a un grupo)
  es la jugada emergente que justifica el arquetipo entero.

**Recomendación de composición:** spawnear Bombers **de a dos con 4-6s entre
ellos** en vez de uno solo. La cadena necesita que haya algo cerca para volar, y
un Bomber solo en un arena vacío es un Rusher lento.

---

## 3. Ranged Flyer

Números de hoy (medido, `data/enemies/flyer.tres`): vida 45, velocidad 5.6,
altura 5.0m, distancia preferida 13m, alcance 20m, cadencia 2.6s, proyectil
24 m/s, daño 12, rumbo ±90° con peso 0.75.

### 3.1 El riesgo real no es la altura, es que nunca se compromete (medido) — **aplicado**

El árbol del Flyer (`tree_flyer.tscn`) es: disparar si está en rango → si no,
mantener distancia → si no, acercarse. **No hay ninguna hoja que lo baje, lo
acerque ni lo deje expuesto.** Con `preferred_distance = 13` y `attack_range =
20`, el Flyer se queda flotando a 13m y 5m de altura, tirando cada 2.6s, para
siempre.

Ése es el patrón que hizo que las unidades voladoras de *Halo* (los Yanme'e) sean
el arquetipo peor recordado de la saga: no eran difíciles, eran **tediosas**,
porque nunca ofrecían un momento en el que matarlas fuera satisfactorio. La
comparación útil es el Cacodemon de *Doom*, que flota igual pero **abre la boca
para tirar**, y ese instante es una promesa: si le pegás ahí, pasa algo. Los
enemigos de *Hades* funcionan igual, con ventanas de vulnerabilidad legibles
atadas a cada ataque.

Un enemigo que sólo se puede resolver por acumulación no hace una pregunta: cobra
un peaje.

**Recomendación (la más importante de este arquetipo): darle una ventana de
compromiso.** Concretamente, una hoja nueva en el árbol, después de N disparos:

- **Descenso de picada** — cada 3 disparos, baja a ~2.5m y se acerca a ~6m
  durante ~1.2s con telegrafía, y después vuelve a subir. Le da al jugador un
  momento en el que la escopeta es la respuesta correcta, y le da al Flyer un
  momento en el que da miedo. Es la opción con más carácter.
- **Recarga en el aire** — cada 3 disparos, se queda quieto y sin disparar 1.2s
  con el glow de telegrafía prendido. Más barato de construir, menos memorable.

Cualquiera de las dos convierte la pregunta de "¿le sigo tirando?" en "¿me guardo
el pico de daño para cuando baje?", que es una decisión y no una tarea.

### 3.2 Puede volar sobre lugares donde el jugador no puede pegarle — **aplicado**

`_fly()` mantiene altura por raycast contra el terreno y **sube** cuando encuentra
algo adelante. No hay nada que le impida derivar sobre un pozo, sobre geometría
alta o fuera del navmesh: no lo usa. En un arena con huecos, un Flyer que se
posiciona sobre el vacío a 13m es inatacable con armas de corto alcance.

**Recomendación:** limitar la posición objetivo del Flyer a puntos con piso
navegable debajo (el mismo raycast que ya tira para mantener altura sabe si
encontró algo), y si deriva fuera, que su siguiente destino sea hacia adentro. No
es una restricción de dificultad: es la garantía de que la respuesta del jugador
existe.

### 3.3 No tiene color propio ni entra en las pruebas de conformidad (medido) — **aplicado**

Dos huecos chicos y concretos:

- `Tokens` tiene `ENEMY_BOMBER` y `ENEMY_ENVIRONMENTAL`, y **no tiene
  `ENEMY_FLYER`**. El violeta del Flyer (`#9966F2`) está escrito a mano en el
  `.tres`, que es exactamente lo que la regla de "colores desde `Tokens`"
  prohíbe.
- `Tokens.ENEMY_HEIGHT` lista siete arquetipos y **el Flyer no está**. Cuatro
  pruebas de `test_spec_conformance.gd` iteran ese diccionario, así que el Flyer
  es el único arquetipo **no cubierto** por las verificaciones de silueta, altura
  y color.

**Recomendación:** agregar `ENEMY_FLYER` y la entrada de altura. Es media hora y
cierra el único agujero de la red.

### 3.4 Dos cosas que conviene **no** hacer

- **No le pongas predicción de tiro.** El Environmental se adelanta a propósito
  (`lead_fraction = 0.65`) porque su trabajo es cortar el camino. El Flyer tira a
  donde estás, y por eso moverse funciona. Un volador que además predice es un
  impuesto al movimiento, y el movimiento es el pilar del juego.
- **No lo hagas más rápido para que "presione más".** Con 45 de vida es de cristal
  a propósito; la presión tiene que venir del ángulo, no de la velocidad.

### 3.5 La altura, que es el riesgo que el plan ya anotaba

5.0m a 13m de distancia son unos 21° sobre la horizontal: bastante para obligar a
levantar la mirada, poco para perderlo de vista. **Recomendación: no tocarla
hasta haber construido la ventana de compromiso de §3.1**, porque la queja de "es
un blanco cómodo allá arriba" que el plan anticipa es, casi seguro, un síntoma de
que nunca baja, no de a qué altura está.

---

## 4. Environmental — los dos frascos

Números de hoy (medido): cadencia 4.5s, arco 1.1s, adelanto 0.65, charco de ácido
3.2m por 5s, charco de atrapado 2.6m por 4s al 35% de velocidad con 0.9s de
gracia, alternando uno de cada dos.

### 4.1 La saturación es el riesgo real, y tiene número (medido) — **aplicado**

Con tres Environmentals vivos (que es lo que las oleadas 9 y 10 spawnean hoy) y
cadencia 4.5s, cae un frasco cada 1.5s. Los charcos de ácido duran 5s, así que en
régimen hay del orden de **tres a cuatro charcos vivos al mismo tiempo**, de 3.2m
de radio cada uno, más los de atrapado. En un arena de tamaño fijo eso empieza a
ser pavimento.

Es el problema que *Left 4 Dead* resuelve con el Director limitando cuántos
especiales pueden estar vivos, y el que los juegos de horda con negación de
terreno (*Risk of Rain 2*, *Vampire Survivors*) manejan capando el área
simultánea. La negación de terreno no escala linealmente: dos charcos son el doble
de trabajo, cuatro son un laberinto.

**Recomendación:** un tope global de charcos enemigos vivos (**4** es un buen
primer número), aplicado donde se tira y no donde se spawnea. Si ya hay cuatro, el
Environmental hace su telegrafía y **no tira** —lo cual además lo vuelve legible:
el jugador ve que la presión tiene techo.

### 4.2 Dos charcos superpuestos son una condena, no una jugada — **aplicado**

Nada impide hoy que un frasco de atrapado caiga sobre un charco de ácido. Esa
combinación es: 35% de velocidad **dentro** de un charco que hace daño por tick,
con una sola salida (el dash) que puede no estar disponible. Es la única
configuración del juego que puede matar sin que el jugador haya podido hacer
nada.

**Recomendación:** que el frasco de atrapado no se tire si el punto predicho cae
dentro de `snare_radius + pool_radius` de un charco vivo. Cada charco tiene que
poder hacer su propia pregunta; dos preguntas encimadas no son una pregunta más
difícil, son ninguna.

Es la misma familia de decisión que ya se tomó al construirlo (el charco de
atrapado no hace daño porque frenar y quemar es cobrar dos veces): acá se cierra
el caso que la implementación no cubría, que es dos charcos distintos haciéndolo
entre los dos.

### 4.3 El atrapado se adelanta demasiado — **aplicado**

`lead_fraction = 0.65` es del frasco de ácido y está bien razonado: el charco cae
*en el camino*, y la pregunta es "sigo o me desvío". Pero el de atrapado usa el
mismo número, y adelantarse con un efecto que **te retiene** no es lo mismo que
adelantarse con uno que te empuja: un charco de ácido en tu camino te desvía, uno
de atrapado en tu camino te agarra.

**Recomendación:** adelanto propio para el atrapado, del orden de **0.35-0.4**.
Sigue cortando el camino, pero cae delante tuyo y no encima, y la respuesta pasa a
ser frenar o rodear en vez de gastar el dash sí o sí.

### 4.4 Estar atrapado no se ve ni se oye (medido) — **aplicado**

`MovementComponent.apply_snare()` baja la velocidad y **nada más**: no hay señal,
no hay VFX, no hay sonido. El jugador se entera de que está atrapado porque camina
raro.

Esto es un problema de *feedback*, no de balance, y es de los que arruinan un
sistema entero: si el jugador no sabe **por qué** está lento, la respuesta ("dash
o gancho") no se le ocurre nunca, y el charco se lee como que el juego se trabó.

**Recomendación:** que `apply_snare()` / `break_snare()` emitan señal, y colgar de
ahí tres cosas baratas y ya existentes en el proyecto: un tinte o viñeta con el
color del charco, el bamboleo de cámara de `CameraFeel`, y un sonido de romperlo
al dashear. **La de romperlo es la más importante de las tres**: es la que enseña
que había una salida.

### 4.5 Lo que ya está bien

- **Errar es el modo normal de funcionar.** Es lo que lo distingue del Ranger, y
  es la decisión más fina que se tomó en todo el arquetipo.
- **Alternar cargas y no abrir nunca con la de atrapado.** El arco de 1.1s es la
  telegrafía; que el orden sea predecible es lo que la hace utilizable.
- **La salida del atrapado cuesta un recurso.** Dash y gancho son cosas que el
  jugador ya tiene en los dedos, y gastarlas es la decisión. *Left 4 Dead* ata su
  control (Smoker, Hunter, Jockey) a que **otro jugador** te libere; en un juego
  solo, el recurso propio es el equivalente correcto.

---

## 5. Composición de oleadas: dónde ponerlos

Tres reglas, en orden de importancia, y las tres son de pacing antes que de
dificultad.

### 5.1 Presentación aislada, después mezcla — **aplicado**

Ningún arquetipo nuevo debería debutar dentro de una ola llena. El debut aislado
es lo que permite aprender la telegrafía sin pagarla, y es práctica estándar
—*Left 4 Dead* presenta cada especial en un momento controlado, *Halo* introduce
cada unidad en un encuentro que la aísla—.

Estado hoy (medido): el Environmental debuta en la 7 (`count = 2`, delay 14s), el
Flyer en la 9 (`count = 2`, delay 18s), y **el Bomber no debuta nunca**.

**Recomendación:** debut del Bomber en la 6 con `count = 1`, y bajar el debut del
Flyer a `count = 1` (hoy entra de a dos, en la ola más cargada del juego hasta ese
punto, junto con tres Environmentals).

### 5.2 Un solo eje de presión a la vez — **aplicado**

En la oleada 10 (medido), los `delay` son: Flyer 16s, Environmental 18s, Summoner
20s. Los tres picos caen en una ventana de cuatro segundos, encima de tres Elites
que arrancaron a los 5s. Eso no es dificultad, es ruido: el jugador no puede
atribuir lo que le pasó a ninguna decisión suya.

**Recomendación:** separar los picos 8-10s entre sí, de manera que la ola tenga
fases legibles (presión de piso → presión aérea → negación de terreno) en vez de
una sola crecida. La curva de tensión con picos y valles es más difícil de
sostener y más fácil de recordar que una rampa; es lo que el Director de *Left 4
Dead* construye deliberadamente al alternar picos con calma.

### 5.3 Techos por rol, no por cantidad — **aplicado**

**Recomendación:** máximo **3 Environmentals** vivos (ya se cumple), máximo **2
Bombers armados** al mismo tiempo, máximo **3 Flyers** (por lectura de pantalla, no
por dificultad: cuatro puntos violetas a 5m de altura son indistinguibles entre
sí). Los topes por rol son más robustos que los topes por cantidad total, porque
lo que satura no es el número de enemigos sino cuántos piden lo mismo a la vez.

---

## 6. Legibilidad y audio

- **Silueta antes que color.** El Bomber es una esfera baja, el Flyer una esfera
  chica en el aire, el Environmental un cilindro alto: los tres se distinguen en
  negro sobre el fondo, que es la prueba que importa.
- **El Flyer necesita su token de color** (§3.3).
- **Un sonido por arquetipo, y el del Bomber por encima de todo.** La prioridad de
  voces ya está construida (paso 4 del plan), así que el riesgo que queda es de
  mezcla y no de código. Si al jugarlo el mix se empasta, la respuesta es **menos
  sonidos**, no más prioridad.
- **El sonido de romper el atrapado es el que más enseña** (§4.4), y hoy no
  existe.

---

## 7. Qué mirar al jugarlo

Criterios falsables, uno o dos por arquetipo. Si la respuesta es "no", el problema
es de diseño y no de números.

- **Bomber:** ¿el jugador alguna vez **elige** dónde revienta —le dispara estando
  al lado de otros— o siempre se limita a alejarse? Si nunca elige, la ventana
  entre armar y explotar es corta o el arquetipo llega demasiado tarde a la ola.
- **Flyer:** ¿hay algún momento en el que matarlo se sienta bien? Si la respuesta
  es "le tiro cuando me sobra tiempo", falta la ventana de compromiso (§3.1).
- **Environmental (ácido):** ¿el jugador se mueve **hacia** algún lado por el
  charco, o sólo huye de él? Negar terreno tiene que empujar, no sólo expulsar.
- **Environmental (atrapado):** ¿el jugador rompe el atrapado a propósito, o se
  queda caminando lento sin entender? Es la pregunta de §4.4, y se contesta
  mirando si dashea dentro del primer segundo.
- **Todos:** ¿el jugador puede decir, después de morir, qué lo mató? Si no puede,
  ninguna otra métrica importa.

---

## 8. Prioridad sugerida

1. **Meter el Bomber en las oleadas** (§2.1) — hoy es un arquetipo que no existe.
2. **Feedback del atrapado** (§4.4) — sin esto el sistema se lee como un bug.
3. **Ventana de compromiso del Flyer** (§3.1) — es lo que lo saca de ser un peaje.
4. **Caída de daño de la explosión** (§2.3) y **el flanqueo que termina antes de
   armar** (§2.2).
5. **Tope de charcos vivos** (§4.1) y **no superponer atrapado con ácido** (§4.2).
6. **Adelanto propio del atrapado** (§4.3), **token y altura del Flyer** (§3.3),
   **separación de picos en las olas** (§5.2).

Nada de esto bloquea la rama de los Gladiadores. Los números de arriba son
hipótesis con motivo, no correcciones: siguen sin jugarse.

---

## 9. Lo que cambió al aplicarlo

Los seis puntos de §8 están construidos. Lo que no estaba en el plan y salió al
hacerlo:

- **La caída de daño rompió un test que medía otra cosa.** `test_it_only_ever_
  explodes_once` ponía un Rusher a 2m del Bomber y esperaba el daño entero; con
  la caída, el número esperado pasó a depender de la distancia — y ahí se vio que
  los dos cuerpos **estaban cayendo**, porque ese test nunca tuvo piso, y no caían
  igual porque no se spawnearon en el mismo frame. Con daño plano eso era
  invisible. La caída lo delató: el test medía la física, no la explosión.
- **El rumbo del Bomber se corrigió solo con una línea, y con la que ya existía.**
  `_approach_commit_distance()` era el lugar: un arquetipo con `has_fuse` devuelve
  su propio `fuse_arm_range`, así que se compromete antes de armar sin que nada
  más cambie. La red aguantó — `test_up_close_it_stops_circling_and_commits` y
  los dos de la espalda pasan sin tocarse.
- **La picada del Flyer necesitó dos nodos y no uno.** Una secuencia reactiva
  vuelve a preguntar sus condiciones en cada frame mientras la acción corre, así
  que un reloj que viviera adentro de la picada la cortaría en el frame siguiente
  al que empieza. El reloj quedó en `ConditionDiveReady`, el descenso en
  `ActionFlyerDive`, y el estado compartido en el blackboard: uno publica el
  número y el otro lo rearma, sin que ninguno conozca al otro.
- **La silueta del Flyer tuvo que bajar de 1.0m a 0.8m.** Al entrar en
  `ENEMY_HEIGHT` quedó cubierto por las cuatro pruebas de conformidad, y una de
  ellas —la de los 40m— lo pescó compartiendo rectángulo con el Rusher. Es
  exactamente el agujero que el documento decía que había, y se notó en el primer
  segundo de estar tapado.
- **El tope de charcos consume la cadencia igual.** Si el Environmental no tira
  por el techo, igual telegrafía y arranca su cooldown; si no, se quedaría
  intentándolo en cada frame contra el tope y se convertiría en un enemigo que
  nunca hace nada.
- **El atrapado que iba a caer sobre un charco vivo no se cancela: cambia de
  carga.** Devuelve el frasco al pool y saca uno de ácido. Cancelar el tiro le
  regalaba al jugador un turno gratis por pararse cerca de un charco.
- **Del feedback del atrapado se hicieron dos tercios a propósito.** La viñeta y
  los dos sonidos, sí. La sacudida de cámara, no: el bob de `CameraFeel` avanza
  con la distancia recorrida y no con el tiempo, así que **ya** reporta el
  atrapado — se hace lento solo. Agregarle una sacudida encima era decir dos
  veces lo mismo.
- **Faltaba una prueba de composición y ahora existe.** `test_wave_composition.gd`
  falla si un arquetipo no aparece en ninguna ola, si uno debuta más grande de lo
  que va a aparecer después, o si dos picos tardíos se pisan. El Bomber invisible
  no era un olvido puntual: era una categoría de error que nada miraba.
