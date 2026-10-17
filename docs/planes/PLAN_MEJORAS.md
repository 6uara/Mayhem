---
tags: [mayhem, plan, gameplay, performance, diseño]
estado: activo
actualizado: 2026-10-16
---

# MAYHEM — Plan de mejoras: profundizar lo hecho

Revisión del proyecto entero sobre `develop` @ `1a37794`, con una pregunta:
**dónde el juego que ya existe puede ser más profundo**, no qué features nuevas
caben. Todo lo marcado **(medido)** se verificó leyendo código y datos; lo
marcado **(propuesta)** es una decisión de diseño abierta, con la perilla
concreta que la aplica.

El estado de qué falta para el release está en [ESTADO.md](../ESTADO.md). Este
documento es el banco de ideas ordenado; lo que se decida hacer se mueve a
ESTADO como tarea.

## Estado al 2026-10-09

Decidido con el dueño del proyecto y ejecutado en la misma sesión (detalle en
[ESTADO.md](../ESTADO.md)):

| § | Qué | Estado |
|---|---|---|
| 1.1 | Puntaje | **Hecho**: kills + estilo + oleadas (500 × número de oleada) + 5000 por ganar. Morir no suma nada extra |
| 1.2 | Curación | **Hecho, con otra forma**: la regeneración es una mejora de tienda (*Nanoweave*, solo fuera de combate) y el botiquín cae del público |
| 1.3 | Rifle gratis | **Hecho**: todas las armas tienen precio (pistola 150, SMG 380, rifle 400, escopeta 450) |
| 1.4 / 2.1 | Clímax / Campeón | **Descartado por ahora**: las olas elite quedan como están |
| 1.5 | Dos fuentes de plata por kill | **Hecho**: `kill_reward_*` borrado; la curva lee `EnemyData.reward_currency` |
| 1.6 | Tabla por arena | **Hecho** |
| 1.7 | Trade-in de mejoras | **Descartado**: perder la inversión al cambiar de arma es diseño. Se sumaron dos modos de juego en su lugar (ARSENAL / ONE GUN) |
| 2.2 | Mejoras raras | **Hecho**: 8 (Slide Loader, Ram Dash, Air Ace, Headhunter, Momentum Plating, Showman, Second Wind, Pad Charger). *Hook Shot* no: el gancho no engancha enemigos |
| 2.3 | Rating | **Hecho**, como lo pidió el diseño: sube con estilo amplificado por velocidad y ritmo, baja con el tiempo y con cada kill plana |
| 2.4 | Reglas de transmisión | **Hecho**: 7 reglas. "El piso arde" y "Cacería" quedaron afuera (piden sistemas que no existen: encender charcos, marcar un enemigo) |
| 2.5 | Enemigo que cobra munición | Abierto |
| 2.6 | Armas nuevas | **Descartado por ahora** |
| 2.7, 2.8, 3 | Arena, juice, ampliar | Abiertos |
| 4 | Performance | **Hecho casi todo** — ver §4.0 |

## Estado al 2026-10-16

Segunda revisión, sistema por sistema, con otra pregunta: **dónde un sistema
multiplica en vez de pedir una decisión**. Decidido con el dueño del proyecto:

| Propuesta | Estado |
|---|---|
| Telemetría para el playtest (daño por origen, quién mató, resumen de muerte, log ampliado) | **Hecho** |
| Reglas que se eligen en la tienda, que tocan enemigos y arena, y contratos opcionales | **Hecho**. "El piso arde" y "Cacería" (§2.4) entraron como Scorched Earth y Manhunt |
| Propiedades de arma como dato y raras por arma | **Hecho**, más lo que pidió el dueño: maestría por arma que desbloquea attachments que se llevan entre runs (la primera excepción a "sin meta-progresión", ver DISENO §1) |
| Pedidos del público y consecuencias del rating | **Hecho** |
| Semilla por run y código para compartir (base del desafío diario de §3) | **Hecho** |
| Variantes de enemigo y oleadas con alternativas | **Documentado en §5**, para cuando estén los modelos de todos los enemigos |
| Némesis y comentarios de estilo del Host | **Descartado por ahora** |

| Prioridad | Qué significa |
|---|---|
| **P0** | Huecos de diseño que distorsionan el playtest. Antes de G3 |
| **P1** | Profundizar sistemas existentes. Barato porque la infraestructura ya está |
| **P2** | Ampliar. Vale la pena si el playtest pide más variedad |

---

## 1. Huecos de diseño (P0)

### 1.1 El puntaje premia morir rápido (medido)

`MatchDirector._calculate_score()`:

```gdscript
var time_bonus: int = int(maxf(0.0, 1200.0 - total_time) * 10.0)
return EconomyManager.currency * 10 + time_bonus
```

Y el mismo cálculo corre al morir. Consecuencias:

- **Morir en la ola 1 a los 30 s da ~11.700 puntos.** Ganar las diez oleadas
  lleva ~1100 s (suma de `par_time` ≈ 870 s más nueve tiendas), o sea ~1.000 de
  bono de tiempo más la plata. `SaveManager` ordena sólo por `score`: **una
  muerte temprana le gana a una victoria.**
- **Gastar baja el puntaje**: cuenta la plata *en mano*. El jugador que compra
  mejoras —lo que el juego le pide— puntúa peor que el que no compra.
- El comentario dice "currency stands in for accuracy until Phase 4": era un
  provisorio que nunca se revisó.

**(propuesta)** El puntaje se construye por oleada limpiada, nunca por tiempo
total:

```
por cada oleada limpiada:
    base        = completion_bonus × 10
    velocidad   = speed_bonus × 10            (el tier ya calculado contra par)
    estilo      = suma de bonos de kill × 10  (KillBonusTracker)
    sin daño    = no_damage_bonus × 10
victoria       = +X fijo
```

Es decir, **lo que se ganó, no lo que se guardó**, y sólo por lo que se
completó. El orden de la tabla pasa a ser `(waves, score)`: diez oleadas siempre
arriba de nueve. Tests que lo fijan: *"una muerte en la ola 1 nunca supera a una
victoria"* y *"comprar en la tienda nunca baja el puntaje"*.

### 1.2 El jugador no se cura nunca (medido)

No hay una sola llamada a `heal()` sobre el jugador en todo el código. 100 de
vida para diez oleadas; `Plating` sube el máximo conservando la proporción, no
cura. Y recibir daño además cuesta plata (`currency_loss_per_damage`).

Puede ser desgaste a propósito, pero no está escrito en ningún lado, y tiene un
efecto que el playtest va a confundir con dificultad: **la ola en la que se
muere no es la que mató, es la acumulación de las anteriores.** Los logs de
`RunLogger` van a mostrar muertes en la 6-7 que en realidad son daño de la 3-4.

**(propuesta)**, de menor a mayor alcance — se pueden combinar:

1. **Curación parcial al cerrar la oleada**: recuperar un % del *faltante*
   (no del máximo), p. ej. 40 %. Un campo en `EconomyConfig`. Mantiene el
   desgaste pero corta la bola de nieve.
2. **Un cuarto gadget del público: el inyector.** Sale por `CrowdDropTable` como
   los otros tres, se agarra corriendo. Cura cuesta *posición*, igual que las
   utilidades — es exactamente el porqué de que los gadgets salieran del shop.
   Color `REWARD` (círculo) en el mundo; el verde `HEAL` sólo en el VFX de la
   curación, como pide la ley de color.
3. **Una mejora que cure por estilo** (ver §2.2, *Second Wind* / *Leech*).

Recomendado: 1 + 2. La 1 sola es un parche; la 2 sola deja la run a merced del
azar del público.

### 1.3 El rifle es gratis (medido)

`shop_catalog.tres`: `weapon_prices = (0, 450, 380, 0)` para rifle, shotgun,
SMG, pistola. El `0` del rifle viene de cuando el rifle era el arma inicial
(commit `830fedb`); después lo pasó a ser la pistola y el precio no se movió. El
arma más versátil del juego sale gratis en la primera tienda.

**(propuesta)** 400 (entre SMG y shotgun) y un test: *"toda arma que no es la
inicial cuesta más que cero"*.

### 1.4 No hay clímax (medido)

Las olas 5 y 10 se llaman elite y **no tienen Elite**: el arquetipo está en el
banco porque su pregunta se superponía con la del Rusher
([PLAN_COMBAT_DIRECTOR §6](../historial/PLAN_COMBAT_DIRECTOR.md)). Hoy son olas
de masa (19 y 42 enemigos). La run termina igual que empieza, sólo con más
gente. Ver §2.1.

### 1.5 Dos fuentes de verdad para la plata por kill (medido)

El juego paga `EnemyData.reward_currency`; la curva del Balance Editor lee
`EconomyConfig.kill_reward_*`, que no conoce a Bomber, Environmental ni Flyer y
devuelve 0. La herramienta hecha para balancear la economía sub-cuenta toda ola
desde la 6. **(propuesta)** borrar los `kill_reward_*` de `EconomyConfig` y que
`curve_evaluator.gd` lea `group.enemy_data.reward_currency`.

### 1.6 La tabla mezcla arenas (medido)

Las filas de `SaveManager` no guardan en qué arena se jugó. Con el editor de
arenas, una arena hecha a medida (sin enemigos que lleguen, con pads por todos
lados) compite en la misma tabla que la arena del juego. **(propuesta)** guardar
el `id` de la arena en la fila y mostrar la tabla filtrada por arena, con la
default como pestaña principal.

### 1.7 Cambiar de arma castiga (medido)

Las mejoras de categoría arma son por arma (`scope = weapon_id`, decisión B1).
Comprar un arma nueva tira toda la inversión en la anterior. En la práctica,
pasada la ola 3 nadie cambia: el loadout de un arma a la vez termina siendo "la
primera arma que compraste". **(propuesta)** *trade-in*: al comprar un arma, se
traslada la mitad de los stacks de arma (redondeando abajo) a la nueva. Una
regla en `Shop._buy_weapon()` y un número en `ShopCatalog`.

---

## 2. Profundizar lo que ya existe (P1)

### 2.1 El Elite vuelve como jefe

El arquetipo ya tiene datos, árbol, slam telegrafiado y tests; le falta una
pregunta propia. **(propuesta)** que deje de ser un melee grande y pase a ser
**el Campeón**: un solo enemigo por ola elite, que entra por su propia puerta
con anuncio del Host y del público.

- **Pregunta que hace:** *"¿podés mantener el momentum mientras una sola cosa te
  caza?"* — el resto de la horda cobra posición; él cobra quedarse quieto.
- **Fases por vida** (100 → 60 → 25 %): slam con onda en el piso (se esquiva
  saltando — premia el bhop), carga en línea recta que rompe `cover_low`, y en
  la última fase llama refuerzos por las puertas.
- **Punto débil** visible (la espalda o un núcleo) que paga como headshot:
  obliga a flanquear, que es para lo que existen el gancho y el dash.
- En la ola 5 una versión de dos fases; en la 10 la completa.
- Ficha del `CombatDirector` para sus ataques, para que la horda no ataque
  encima de su telegrafía.

Es el único cambio de esta lista que necesita modelo nuevo (ya está en el
pendiente de arte).

### 2.2 Mejoras que cambian cómo se juega, no sólo números

Las 19 mejoras son multiplicadores de stat. Eso da progresión pero no *builds*:
dos runs con mejoras distintas se juegan igual, sólo más rápido o más fuerte.
**(propuesta)** un segundo tipo de mejora, **rara** (una por visita como máximo,
más cara), que agrega una regla. Todas amarradas a un pilar:

| Mejora | Regla | Pilar que paga |
|---|---|---|
| **Slide Loader** | Deslizar recarga el 30 % del cargador por segundo | Movilidad |
| **Hook Shot** | El gancho a un enemigo lo tira hacia vos y lo aturde 0,5 s | Movilidad + gancho |
| **Ram Dash** | Dashear a través de un enemigo le hace daño y lo staggerea | Movilidad |
| **Air Ace** | +25 % de daño en el aire | Movilidad (y el bono `airborne`) |
| **Headhunter** | Una kill por headshot devuelve 2 balas al cargador | Gunplay |
| **Momentum Plating** | La reducción de daño escala con la velocidad horizontal | Movilidad |
| **Showman** | Bonos de estilo +50 %, daño recibido +15 % | Riesgo/recompensa |
| **Second Wind** | Una vez por run, un golpe letal te deja en 1 y dispara 2 s de invulnerabilidad | Supervivencia |
| **Pad Charger** | Un bounce pad recarga una carga de dash | Arena |

Arquitectura: `UpgradeData` gana un campo `effect: UpgradeEffect` (Resource con
hooks), y los efectos escuchan `EventBus` igual que `KillBonusTracker`. Los
números siguen en `.tres`. Iconos: el set de mejoras del handoff de iconografía
se extiende.

### 2.3 El público como eje de la economía

`CrowdMoodDirector` ya mide el entusiasmo (sube con el ritmo de kills, se enfría
solo) y el público ya tira gadgets. Hoy esas dos cosas no se tocan, y el
entusiasmo no tiene consecuencia de juego. **(propuesta)** hacerlo el **rating
de la transmisión**:

- Un medidor visible en el `BroadcastBug` (la capa del Host, no la HUD de
  combate).
- El rating **multiplica los bonos de estilo** (×1 a ×2) y **acorta el intervalo
  de drops** del público.
- El Host lo comenta cuando cruza umbrales ("el rating se está cayendo…").

Con eso el estilo paga dos veces —plata y recursos— y la fantasía de "show
transmitido" pasa de ambientación a sistema. Todo el estado ya existe; es
cablear.

### 2.4 Reglas de transmisión: variedad por run sin meta-progresión

Diez oleadas fijas en una arena fija hacen que la run 5 se juegue igual que la
run 1. **(propuesta)** desde la ola 3, el Host anuncia una **regla de la ola**
elegida al azar de un pool, como un game show:

- *"Doble pago por headshot"*, *"Sólo pagan las kills en el aire"*
- *"Baja gravedad"* (`fall_gravity_scale` y salto)
- *"El piso arde"*: dos `hazard_zone` se activan en el anillo central
- *"Patrocinador: munición sin límite 20 s"*
- *"Cacería"*: un enemigo marcado vale ×5 (el bono `priority` ya existe)

Un `WaveRule` Resource con hooks, un pool en datos, el anuncio por
`NarratorManager`. No rompe "una run, sin saves": no se arrastra nada.

### 2.5 El hueco del elenco: nadie cobra munición

[PLAN_ENEMY_BEHAVIOR §1.2](../historial/PLAN_ENEMY_BEHAVIOR.md) ya lo había
encontrado: cada arquetipo cobra un recurso (posición, tiempo, vida, movilidad)
y **ninguno cobra munición**, aunque la reserva limitada es pilar (5.1).
**(propuesta)** **el Escudado**: escudo frontal que absorbe balas (las gasta sin
daño). Se mata flanqueando o con el gancho (§2.2 *Hook Shot* lo da vuelta).
Cobra munición y premia movilidad a la vez.

Los Gladiadores ([PLAN_NEW_ENEMY_TYPES §5](PLAN_NEW_ENEMY_TYPES.md)) son más
caros (facción nueva, net worth, botín disputado) y su pregunta se superpone con
el rating del público. Recomendado: después del Campeón y del Escudado, o nunca.

### 2.6 Armas: dos más, no diez

Cuatro armas con una a la vez es poco para que la compra de arma sea una
decisión. Hay modelos ya en `assets/models/weapons/` sin usar (`awp`,
`rocketlaucher`, `quadrocket`, `pew`). **(propuesta)** sumar dos que tengan
pregunta propia:

- **Rail / sniper** — un tiro, atraviesa enemigos. Paga el bono `long_shot`,
  es la respuesta natural al Flyer.
- **Lanzacohetes** — daño de área y **rocket jump**: el arma que es además una
  herramienta de movilidad. Encaja con el pilar 5.2 como ninguna otra.

### 2.7 Arena

- **128 m de lado es mucho** para los rangos de pelea (Ranger a 14 m, drops a
  12-26 m). Probar `FLOOR = 24` en `make_default_arena.gd` en el primer
  playtest, con los logs midiendo tiempo por ola contra `par_time`.
- **Interactuables con estado por ola**: plataformas móviles y charcos que se
  encienden/apagan entre oleadas (la arena como tercer actor, no escenografía).
- **El campo de tiro**: `target_dummy` y el visualizador de recoil ya existen.
  Un botón PRÁCTICA en el menú que cargue una arena con muñecos es onboarding
  casi gratis.
- **Arenas de la comunidad**: el editor ya exporta JSON. Con la tabla por arena
  (§1.6), compartir arenas en itch es una feature de comunidad sin servidor.

### 2.8 Sensación (juice) con lo que ya está en el repo

- `dissolve.gdshader` está sin usar: **muerte de enemigo con disolución** en el
  color del arquetipo, en vez de desaparecer.
- `hologram.gdshader`: **el enemigo materializándose** en la puerta de spawn
  durante la telegrafía.
- Los flipbooks de humo del pack: humo residual de la explosión del Bomber y del
  slam del Campeón.

## 3. Ampliar (P2)

- **Desafío diario**: semilla del día para tienda, reglas de transmisión y drops;
  tabla local por semilla. Rejugabilidad sin servidor.
- **Modo práctica de oleada**: elegir una ola suelta para entrenarla, sin
  puntaje.
- **Aim assist de gamepad** con su propio pase de diseño, y glifos de botón en
  HUD y hints.
- **Dificultad**, sólo después de decidir cómo se separa en la tabla.

---

## 4. Performance

### 4.0 Lo que se hizo y lo que se midió (2026-10-09)

Máquina: Radeon 680M integrada (Ryzen 5 7535HS), pantalla completa nativa.
Herramientas: `tools/profile_elite_wave.gd` (ahora también reparte el frame en
process / physics / GPU) y `tools/profile_scene_cost.gd` (nuevo: costo de la
arena vacía, sacando partes).

| | Ola 10 | Arena vacía |
|---|---|---|
| Antes | 30 FPS | ~40 FPS, 3182 draw calls, 312 k primitivas |
| Después | ~40 FPS (~43 con los defaults de iGPU) | ~46 FPS, 211 draw calls, 120 k primitivas |

| Ítem | Estado |
|---|---|
| 4.1 Re-medir | **Hecho**, con tres herramientas y esta máquina como mínimo de referencia |
| 4.2 Arena en lotes | **Pasos 1 y 2 hechos** (mallas y materiales compartidos, MultiMesh por malla+material vía `ArenaGeometryBatcher`). Paso 3 (fusionar colisiones) no: Jolt con los colliders sueltos mide ~1.7 ms y el bake del navmesh depende de ellos |
| 4.3 Shader del cuenco | **Hecho**: `arena_panel_static.gdshader` |
| 4.4 Materiales por instancia | **Hecho de otra forma**: el overlay del destello se pone solo mientras brilla (antes cada parte de cada modelo se dibujaba dos veces) |
| 4.5 Sombras | **Hecho**: cuenco, foso, público y ciudad sin sombra; sol con 2 cascadas hasta 60 m |
| 4.6 IA | **Hecho el ritmo**: el árbol decide cada 2 frames de cerca, 3 a media distancia y 4 de lejos; el giro se reparte entre frames y los timers usan `get_ai_delta()`. Partir `enemy.gd` **no**: es un refactor sin ganancia medible por sí mismo |
| 4.7 Compilación de shaders | **No hecho**: Godot 4.7 compila con ubershaders en segundo plano; falta medir si queda algún tirón antes de escribir un warm-up |
| 4.8 Tamaño del build | **Hecho en parte**: `tools/find_unused_assets.py` encuentra 154 MB sin usar y las carpetas enteras van al `exclude_filter`. Audio a Ogg, no |
| Nuevo: arma en primera persona | Su SubViewport es un segundo pase 3D completo (~3.5 ms de GPU a resolución nativa). Se le sacaron el atlas de sombras y el AA y sigue la escala de render; el costo fijo queda |
| Nuevo: defaults por hardware | Con GPU integrada el primer arranque va a 75 % de escala y sombras medias |

**Lo que queda.** Con la ola 10 el techo es la CPU: el paso de física cuesta
~13 ms (Beehave ~3, mover cuerpos ~2.5, navegación ~2.8, Jolt ~1.7). Los
siguientes pasos, en orden de retorno esperado:

1. **Navegación**: medir cuántas consultas de camino hace la horda por segundo; si
   `set_move_target()` re-pide camino por cambios chicos de destino, poner un
   umbral de distancia antes de asignar `agent.target_position`.
2. **`move_and_slide()` de enemigos quietos**: saltearlo cuando la velocidad es
   cero y está apoyado (kiteando a distancia, telegrafiando).
3. **Beehave**: el costo restante es sobre todo la maquinaria del addon (escrituras
   al blackboard por nodo y por tick), no las hojas. Un parche local más, o un
   árbol propio para los arquetipos simples.
4. **SubViewport del arma**: renderizar el arma en el mundo principal con un shader
   de viewmodel (FOV propio en el vertex) elimina el segundo pase entero.

### 4.0.1 El plan original

El objetivo sigue siendo 60 FPS en la ola más cargada (DISENO §10), pero la
medición que lo respalda es del 2026-08-11 y **no incluye** el coliseo, el
público, el skyline, la pared de energía, cuatro modelos de enemigo ni la ola 10
de 42 enemigos. Y viene más costo: los modelos de todo lo que falta.

### 4.1 Re-medir primero, con tres perfiles (P0)

1. `profile_elite_wave.gd` tal cual, sobre el contenido actual.
2. **Un perfil de combate**: el mismo script con el jugador disparando y la
   cámara girando por script. El número que hoy no existe es "el peor frame de
   una pelea real".
3. **Una máquina mínima** definida por escrito (p. ej. iGPU tipo Iris Xe / Radeon
   680M a 1080p con FSR al 67 %). Sin un target mínimo, "60 FPS" no tiene contra
   qué medirse.

Nada de lo que sigue se toca sin un antes y un después.

### 4.2 La arena son ~1450 mallas y ~1450 colisiones sueltas (medido)

`piece_mesh_builder.gd` crea, **por cada celda de la huella** de cada pieza, un
`BoxMesh` nuevo, un `MeshInstance3D` y un `BoxShape3D`, con un
`StandardMaterial3D` nuevo por pieza. La arena por defecto tiene 137 `floor_3x3`
(9 celdas cada uno), 31 `floor_2x2`, 63 `cover_low`…: del orden de **1450 draw
calls sólo de geometría estática**, más el pase de sombras, más 1450 formas de
colisión.

Hoy no se nota a 700 FPS en una GPU fuerte; es exactamente lo primero que
aparece en una iGPU, y **se multiplica cuando lleguen los modelos reales** (un
modelo por celda en vez de una caja). En orden:

1. **Compartir recursos**: un mesh y un material por tipo de pieza (+variante
   elevada), no uno por instancia. Gratis.
2. **`MultiMeshInstance3D` por tipo de pieza** en runtime (el editor puede seguir
   con nodos sueltos).
3. **Colisión fusionada**: el piso como rectángulos contiguos, no una caja por
   celda.

Hacer 1 y 2 **antes** de integrar los modelos de arena, para que el import de
arte entre directo al camino barato.

### 4.3 `arena_glitch_panel.gdshader` cubre ahora todo el coliseo

El pendiente #4 de [PLAN_PERFORMANCE](../historial/PLAN_PERFORMANCE.md) era
este shader en las paredes del greybox. Hoy es el material de **todo el venue**
(`ArenaColiseum.PANEL_SHADER`): más cobertura de píxeles que antes, con la rama
animada evaluándose aunque esté congelada. La salida es una variante sin
animación. Es el primer sospechoso si el perfil 4.1 sale GPU-bound.

### 4.4 Materiales por instancia de enemigo

`Enemy` y `SpawnDoor` hacen `.duplicate()` del material en `_ready()` para poder
flashear uno sin flashear todos. Funciona, pero cada enemigo es un material
único y nada se agrupa. Con modelos reales (más superficies por enemigo) eso
escala mal. **(propuesta)** pasar el flash, el glow y la disolución a
`instance uniform` en el shader: un material compartido, estado por instancia.

### 4.5 Sombras de lo que nadie mira de cerca

Sólo el coliseo apaga `cast_shadow`. `CrowdStands` (miles de quads) y
`CitySkyline` no lo hacen y entran al mapa de sombras del sol. Verificar en el
perfil y apagarlo si cuesta: un público de impostores no necesita sombra
proyectada.

### 4.6 IA

- **Tick de Beehave por distancia/rol**: un Ranger a 30 m no necesita decidir
  cada frame. El `CombatDirector` ya tiene la noción de presupuesto por frame;
  extenderla a los árboles.
- **Partir `enemy.gd`** (P3-5 del plan de pulido) también es una mejora de
  performance: hoy el profiler muestra una sola función gigante.

### 4.7 Tirones de compilación de shaders

Los objetos prewarmeados quedan invisibles, así que su pipeline compila la
primera vez que se ven (un tirón en el primer disparo, la primera explosión, el
primer enemigo de cada tipo). **(propuesta)** renderizar un frame con un
ejemplar de cada uno delante de la cámara **detrás de la pantalla de carga**.
Medir con 4.1 en la máquina mínima.

### 4.8 Tamaño del build (210 MB)

`assets/` pesa ~230 MB: flipbooks 61 MB (casi todos sin usar), modelos 91 MB
(incluye fuentes `.blend`, `.fbx` de armas sin usar y el UAL1), audio 57 MB.
**(propuesta)** sacar del export lo que ninguna escena referencia (un script que
lo liste) y exportar el audio en Ogg Vorbis. Un juego de itch de 60-80 MB baja
más.

---

## 5. Variedad de enemigos sin arquetipos nuevos (cuando estén los modelos)

**Precondición:** los modelos de todos los enemigos (R1 en
[ESTADO](../ESTADO.md)). Una variante se tiene que leer en la silueta o en una
marca sobre el modelo final; diseñarla sobre cápsulas grey-box es diseñarla dos
veces. Todo lo de abajo es **(propuesta)**.

### 5.1 El problema (medido)

Las diez oleadas son fijas: cada `SpawnGroup` nombra un `EnemyData` y una
cantidad, sin azar. La ola 7 de la run 5 es la ola 7 de la run 1. Las reglas de
transmisión dan variedad por oleada, pero la composición —qué preguntas hace la
horda— es siempre la misma, y de la ola 6 en adelante la escalada es "más de lo
mismo" (la 10 son 42 enemigos de los mismos siete arquetipos).

### 5.2 Variantes por dato

Un recurso `EnemyVariant` que se aplica encima de un `EnemyData`, igual que
`EnemyRuleModifier` lo hace hoy para las reglas (el camino ya existe:
`Enemy.setup()` lee multiplicadores de vida, velocidad y daño). Lo que suma:

| Variante | Qué cambia | Pregunta que agrega | Lectura (forma, no solo color) |
|---|---|---|---|
| **Acorazado** | ×2 vida, −20 % velocidad, el cuerpo absorbe la mitad: solo la cabeza paga entero | "¿podés apuntar en movimiento?" | Placas sobre el torso del modelo |
| **Veloz** | +40 % velocidad, −30 % vida | "¿podés frenar algo que llega antes?" | Estela detrás, silueta inclinada |
| **Inestable** | Al morir revienta como un Bomber chico (radio 2.5 m) | Cobra posición al matar: no se lo mata encima | El anillo de espoleta del Bomber, en el piso, siempre |
| **Escoltado** | Spawnea con un Healer atado que lo sigue | Prioridad de objetivo | El haz de cura ya existente |

- Marca de variante con una **forma** encima del modelo (la ley de color: el
  color nunca solo). El HUD de enemigos restantes la muestra igual.
- Una variante nunca cambia el árbol de comportamiento: cambia números y suma un
  efecto al morir o al spawnear. El elenco de preguntas sigue siendo el de
  [PLAN_ENEMY_BEHAVIOR](../historial/PLAN_ENEMY_BEHAVIOR.md).
- `KillBonusTracker` puede pagar un bono por variante (el `marked` de Manhunt es
  el precedente).

### 5.3 Oleadas con alternativas

`SpawnGroup` gana `alternatives: Array[EnemyData]` y `variant_pool:
Array[EnemyVariant]` con probabilidades; la ola sortea con
`RunSeed.rng(&"waves")`, así un código compartido sigue jugando la misma
composición.

- **Lo que no se toca:** el total de enemigos por grupo, las puertas y los
  tiempos. El `par_time` sigue valiendo porque la cantidad y el ritmo de spawn son
  los mismos; cambia qué sale por cada puerta.
- Alternativas con el **mismo rol** del `CombatDirector` (un BRAWLER por otro
  BRAWLER), para que la composición de la horda no se desarme.
- Variantes desde la ola 4, a lo sumo una cada N spawns, más densas hacia la 10:
  esa es la escalada que hoy falta.
- El Balance Editor tiene que poder mostrar el valor esperado de plata de una ola
  con alternativas (hoy la curva lee un `EnemyData` fijo por grupo).

### 5.4 Qué medir antes

Con los logs del playtest 1 (`RunLogger` formato 2): qué arquetipo hace más daño
por ola (`damage_by_cause`), en qué ola se muere y de qué. Si una ola ya es un
pico, una variante ahí lo empeora; las variantes van donde el log muestre olas
planas.

## 6. Orden sugerido

1. **§1.1, §1.3, §1.5** — son de una tarde cada uno y cambian lo que el playtest
   mide.
2. **§4.1 y §4.2 (pasos 1-2)** — antes de integrar arte.
3. **Decidir §1.2 y §1.4/§2.1** — son las dos preguntas de diseño grandes.
4. Integrar modelos ([HANDOFF_ARTE](../handoffs/HANDOFF_ARTE.md)) y playtest 1.
5. Con los logs: §2.2, §2.3 y §2.4 en ese orden — los tres usan sistemas que ya
   existen.
6. P2 según lo que pida el playtest.
