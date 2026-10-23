---
tags: [mayhem, estado, backlog]
estado: vivo
actualizado: 2026-10-21
---

# MAYHEM — Estado del proyecto

**Única fuente de "qué falta".** Reemplaza como estado a
[BACKLOG_ESTADO](historial/BACKLOG_ESTADO.md) (agosto) y a la sección de
abiertos de [PLAN_PULIDO](historial/PLAN_PULIDO.md) (septiembre), que quedan en
el historial. Cuando algo se cierra se borra de acá y se anota en el commit; cuando
aparece algo nuevo, se agrega acá y no en un plan suelto.

Base: rama `feat/systems-expansion` sobre `develop` @ `5bc7109`. Suite: ver
[TESTING.md](TESTING.md#estado-actual-de-la-suite).

---

## 1. Dónde está el juego

**Todo el trabajo de sistemas está hecho.** El loop completo existe y está
cubierto por tests: diez oleadas, ocho arquetipos (siete en rotación, el Elite en
el banco), cuatro armas, dos modos de juego, 20 mejoras comunes y 8 raras, tienda
con reroll, bonos de estilo, rating de la transmisión, reglas de transmisión por
oleada, curación (mejora y botiquín del público), trofeos, tabla por arena, Host
con guion completo en subtítulos, tutorial de arranque, coliseo generado con
público que reacciona y tira gadgets, editor de arenas, gamepad, rebind,
opciones gráficas, log de runs para playtest.

**Lo que falta es contenido de arte y audio, y el ciclo de playtest.**

### Lo que entró el 2026-10-09

| Qué | Dónde |
|---|---|
| Puntaje = kills + estilo + oleadas; morir solo corta lo que se iba a sumar | `RunRecord.get_score()`, `EconomyConfig` grupo Score |
| Modos: ARSENAL (pistola, la tienda vende armas, todas con precio) y ONE GUN (un arma elegida, la tienda no vende armas) | `GameManager.Mode`, `ModeSelect`, `Shop` |
| Tabla de puntajes por arena, con el modo en cada fila | `SaveManager.get_entries_for()`, `LeaderboardPanel` |
| Balance Editor: la curva lee la plata real de cada arquetipo | `curve_evaluator.gd` |
| Curación: mejora *Nanoweave* (regeneración fuera de combate) y botiquín que tira el público | `PlayerPerks`, `data/utilities/medkit.tres` |
| 8 mejoras raras que agregan una regla (una por visita como máximo, desde la ola 2) | `ShopCatalog.rare_upgrades`, `PlayerPerks` |
| Rating de la transmisión: sube con estilo, velocidad y ritmo, baja con kills planas y con el tiempo; multiplica el estilo y acelera los regalos | `BroadcastRating`, `RatingMeter` |
| Reglas de transmisión: desde la ola 3 (no en las elite), una regla por oleada | `BroadcastRules`, `data/broadcast_rules/` |
| Tutorial de arranque: la ola 1 espera; se saltea con T / R3 o desde la pausa | `TutorialDirector`, `data/tutorial/tutorial_steps.tres` |
| Sin menciones de licencias: LICENSE, THIRD_PARTY, OFL y créditos de música fuera | — |
| Performance (ver §5) | — |

### Lo que entró el 2026-10-16

Revisión de sistemas con el dueño del proyecto: de las propuestas se hicieron la
telemetría, las reglas elegibles con contratos, las armas, los pedidos del
público y la semilla. Las variantes de enemigo quedaron documentadas para cuando
estén los modelos ([PLAN_MEJORAS §5](planes/PLAN_MEJORAS.md)).

| Qué | Dónde |
|---|---|
| Telemetría: daño por origen, quién mató, resumen en la pantalla de muerte; el log guarda semilla, ofertas de la tienda, reglas ofrecidas y elegidas, contratos, rating por ola y pedidos | `DamageCause`, `EventBus.player_hit`, `RunRecord.get_death_recap()`, `RunLogger` (formato 2) |
| Reglas elegibles: el Host ofrece dos en la tienda; las reglas pueden tocar enemigos (vida, velocidad, daño, Cacería) y la arena (charcos por kill). 4 reglas nuevas | `BroadcastRules.prepare_offer()`, `EnemyRuleModifier`, `data/broadcast_rules/` |
| Contratos: restricción opcional que paga al limpiar la ola. 5 contratos | `data/broadcast_rules/contracts/`, fila "Contract" del desglose |
| Consecuencias del rating: pico (paga y regala, una vez por ola) y retiro del patrocinador (sin regalos) | `BroadcastRating`, `rating_config.tres` grupo Consecuencias |
| Pedidos del público: 8, desde la ola 2 | `CrowdRequests`, `data/crowd_requests/` |
| Comportamiento de tiro como dato (perforar, área, empuje) y 2 raras por arma | `WeaponData` grupo Behavior, `WeaponComponent._pierce()/_splash()` |
| Maestría de armas y attachments (12), que se llevan entre runs; Armería en la pantalla de modo | `Armory`, `ArmoryPanel`, `data/attachments/` |
| Semilla por run, corrientes por sistema, código para compartir (copiar al final, pegar en el menú) | `RunSeed`, `ModeSelect`, `MatchOverlay` |

### Lo que entró el 2026-10-21

Feedback de los profesores. Rama `feat/teacher-feedback`.

| Qué | Dónde |
|---|---|
| Hitstop suave: un impacto común frena al 30 % durante 30 ms, no se re-dispara a mitad de otro, espera 0.15 s y se saltea por debajo de 45 FPS; headshots y kills mantienen el frenazo completo. Era la causa del freeze al disparar con FPS bajos | `HitstopController` |
| El gancho arranca con la asistencia de un stack de Magnet Hook (6.4°) | `GrappleComponent.aim_assist_degrees` |
| La tienda reserva un lugar para un arma en el 60 % de las visitas | `ShopCatalog.weapon_offer_chance` |
| El brillo del Summoner, con tope de 2.0 (su `.glb` trae 10) | `EnemyData.model_emission_max` |
| Mantle automático, sin mantener saltar | `MovementComponent._tick_airborne()` |
| Caída rápida: agacharse en el aire pica a 28 m/s; aterrizar agachado sale deslizando con 3 m/s por metro caído (tope +10 sobre la carrera) | `MovementComponent` grupo Fast fall |
| Sin dash. El bono pasa a DESLIZANDO, el pedido a SLIDE THROUGH THEM!, Ram Dash a Ram Slide, Pad Charger recarga el gancho; el paso del tutorial, el golpe de cámara, la estela y el sonido pasan a la caída rápida. Salen Extra Dash, Dash Cooldown, el contrato GROUNDED y los pips del HUD | ver [03 Player and Movement](Mayhem/03%20Player%20and%20Movement.md#no-dash) |
| Más enemigos y más variedad por ola: de 6 a 10 en la 1 y de 42 a 49 en la 10 (total de la run 200 → 272). Los arquetipos debutan antes (ranger 1, bomber 2, healer 3, summoner 4, environmental 6, flyer 7) y cada ola mezcla más. `par_time` estirado en proporción; pool de enemigos a 56 | `data/waves/`, `game.tscn` |
| Ningún enemigo puede quedar donde no se lo pueda matar: un spawn afuera de la pared se corrige al aparecer, el que termina afuera vuelve solo en medio segundo, y una ola sin progreso por 40 s devuelve a los vivos por una puerta y corrige un conteo de vivos colgado. Era el reporte de runs que no se podían terminar | `ArenaBounds`, `Enemy._tick_arena_guard()`, `WaveManager._rescue_stalled_wave()` |

## 2. Bloquea el release

| # | Qué | Tipo |
|---|---|---|
| R1 | **Modelos** de piezas de arena, interactuables y un enemigo (Elite). Ya resuelto: brazos y Summoner con modelo y clips (2026-10-19), Environmental con modelo y clips (2026-10-22), armas escaladas a las manos, y (2026-10-20) lanzador de gancho en la muñeca con cable y una silueta por gadget del público (`tools/build_gadget_meshes.gd`). Falta un pase en juego mirando el cable del gancho contra el ancla. Pedido de arte en [HANDOFF_ARTE.md](handoffs/HANDOFF_ARTE.md) | Arte |
| R2 | **Audio de armas e impactos** sigue siendo el sintetizado por `tools/generate_placeholder_sfx.py` | Audio |
| R3 | **Playtest de los sistemas nuevos.** Rating, reglas, raras y tutorial tienen tests pero ningún número jugado: `data/economy/rating_config.tres`, los costos de las raras y la duración de los pasos del tutorial son de escritorio. También las oleadas nuevas del 2026-10-21 (conteos y `par_time`): la 9 y la 10 pueden pasar el techo de CPU de §5. Desde el 2026-10-16 también: pagos de contratos, `peak_bonus` y `walkout_after`, metas y tiempos de los pedidos, costos de las raras por arma, umbrales de maestría (`attachment_catalog.tres`) y los números de cada attachment. Desde el 2026-10-21: los números de la caída rápida, del hitstop suave, `weapon_offer_chance`, el tope de brillo del Summoner y `PlayerPerks.RAM_MIN_SPEED` | Balance |

## 3. Abierto — necesita una decisión

- **El charco de atrapado en una ola con el contrato NO HOOK** no tiene salida:
  desde que salió el dash (2026-10-21) el gancho es la única forma de romperlo, por
  decisión del dueño. O el contrato se excluye cuando hay Environmental en la ola,
  o se acepta como parte del precio del contrato.
- **Curva de oleadas.** La 5 tiene `par_time` 115 y bonus 150; la 6 baja a 100 y
  110 (números del 2026-10-21, ver abajo). Si la 5 es un pico a propósito, documentarlo. Mejor con logs de
  `RunLogger` en la mano.
- **Las olas elite** quedan como olas de masa (decisión del 2026-10-09). El
  Campeón de [PLAN_MEJORAS §2.1](planes/PLAN_MEJORAS.md) queda en el banco.
- **Dificultad.** Toca la identidad ("una run") y la tabla.
- **Aim assist para gamepad** y **carteles de tecla con glifos de botón** (hoy
  HUD, hints y tutorial muestran la tecla del teclado).
- **Tamaño de la arena por defecto:** 128 m de lado. La perilla es `FLOOR` en
  `tools/make_default_arena.gd`.
- **`Fast Winch` en 2 stacks**, pendiente de playtest.
- **Phantom Camera**: habilitarlo para algo concreto o borrarlo ([ADDONS.md](ADDONS.md)).
- **¿La tabla separa por modo?** Hoy es por arena y cada fila dice su modo; una
  run de ONE GUN con escopeta compite con una de ARSENAL.
- **Attachments y la tabla.** Una run con attachments compite con una sin. Son de
  costado, pero un jugador con todo desbloqueado elige su mejor combinación. La
  fila no guarda los attachments (el log sí). Opciones: anotarlos en la fila,
  separar la tabla, o dejarlo así.
- **Semilla y tabla.** Una run jugada con un código pegado compite igual que una
  con semilla nueva; con la misma semilla se puede practicar la tienda. ¿Se marca
  la fila?
- **El área del SMG no tiene VFX** a propósito (15 por segundo); si el playtest
  dice que no se lee, un anillo chico y barato.

## 4. Abierto — necesita un asset o una persona

- **Voz del Host.** `assets/audio/voice/` vacío; el guion está en
  [host_script/](host_script/host_script.md). Las líneas de reglas, rating, tutorial,
  Second Wind, contratos, pedidos del público, pico y retiro del patrocinador ya
  están en el guion exportado (2026-10-16).
- **Arte de VFX.** Impactos, picada y slide siguen grey-box; decals por superficie
  en `null`; los flipbooks del pack sin usar (y fuera del build, ver EXPORT).
- **Mezcla de audio real** (oídos, auriculares y parlantes).
- **URL del formulario de feedback** vacía en `data/feedback/feedback_config.tres`.
- **Iconos de las raras por arma (8) y del bono RECOMPENSA**: geométricos
  provisorios, en el mismo lenguaje que los de las raras globales.
- **Variantes de enemigo y oleadas con alternativas**: esperan los modelos de
  todos los enemigos (R1). Diseño en [PLAN_MEJORAS §5](planes/PLAN_MEJORAS.md).
- **Iconos** de menús (11) y del editor de arenas (21):
  [HANDOFF_ICONOGRAPHY §3.6-3.7](handoffs/HANDOFF_ICONOGRAPHY.md). Los 9 de las
  mejoras nuevas son geométricos provisorios en el mismo lenguaje.
- **Probar a mano:** punch de la picada, FSR a 50-67 %, MSAA/TAA, sombras en Bajo, una
  oleada con joystick, el tutorial completo, el giro de los enemigos con la IA a
  ritmo espaciado, y la **interpolacion de fisica** (rama
  `feat/physics-interpolation`) en un monitor de mas de 60 Hz: correr, slide,
  dash, grapple, zip line, enemigos saliendo de las puertas, trazadoras, haces
  del Healer y numeros de daño. Ningun test ve un frame dibujado.
- **`export_presets.cfg` local** no sigue [EXPORT.md](EXPORT.md): tiene presets
  "Windows Desktop" y "Web" (este último duplicado) y ningún `exclude_filter`.

## 5. Performance

Medido en la máquina de desarrollo actual — **Radeon 680M integrada** (Ryzen 5
7535HS), pantalla completa nativa, `tools/profile_elite_wave.gd`:

| | Ola 10 (42 enemigos) | Arena vacía |
|---|---|---|
| Antes | 30 FPS | ~40 FPS, 3182 draw calls |
| Después | ~40 FPS (43 con los defaults de iGPU) | ~46 FPS, 211 draw calls |

Lo que se hizo: arena en MultiMesh con mallas y materiales compartidos; cuenco,
público y ciudad sin sombra; shader del cuenco sin animación; sol con 2 cascadas
a 60 m; IA de Beehave a ritmo espaciado por distancia; overlay de destello solo
mientras brilla; SubViewport del arma recortado; defaults más livianos en GPU
integrada; packs de arte sin usar fuera del export.

**Sigue sin llegar a 60 en esta máquina con la ola 10**, y el techo ahora es la
CPU: el paso de física cuesta ~13 ms con 42 enemigos (Beehave ~3 ms, mover los
cuerpos ~2.5 ms, navegación ~2.8 ms, Jolt ~1.7 ms). Lo que queda está en
[PLAN_MEJORAS §4](planes/PLAN_MEJORAS.md).

## 6. Abierto — técnico

- Partir `enemy.gd` (~2450 líneas) — después del playtest, en su rama.
- Deudas y puntos frágiles: [12 Known Issues and Gaps](Mayhem/12%20Known%20Issues%20and%20Gaps.md).

## 7. Ciclo de release

Sin arrancar. **R1-R3 → playtest 1 (G3) → balance desde los logs (G4) →
playtest 2 (G5) → pase de bugs (G6) → build final (G7) → trailer (G8) / case
study (G9).** Instrucciones en
[PLAN_BACKLOG_RESTANTE §8](historial/PLAN_BACKLOG_RESTANTE.md); export en
[EXPORT.md](EXPORT.md).

## 8. Ramas fuera de `develop`

| Rama | Estado |
|---|---|
| `feat/enemy-attack-variation-and-leap`, `feat/mayhem-tools`, `nice-to-have/new-enemy-types` | Mergeadas en `develop`, sin nada propio. Se pueden borrar |
| `feat/fps-counter-and-audio-default` | 1 commit sin mergear (2026-08-21) |
| `feat/web-export` | 2 commits sin mergear (2026-09-11) |
| `fix/arena-invisible-wall` | 2 commits sin mergear (2026-08-21); la pared de energía posterior probablemente lo vuelve obsoleto |

Los Gladiadores ([PLAN_NEW_ENEMY_TYPES §5](planes/PLAN_NEW_ENEMY_TYPES.md)) no
tienen rama: no se empezaron.
