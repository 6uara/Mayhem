---
tags: [mayhem, estado, backlog]
estado: vivo
actualizado: 2026-11-03
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
el banco), cuatro armas, dos modos de juego, 24 mejoras comunes y 16 raras, tienda
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

### Lo que entró el 2026-10-23

| Qué | Dónde |
|---|---|
| Retroceder disparando deja de ser gratis: el `CombatDirector` mide la retirada sostenida y la horda la contesta (dos cortan el camino, tiros y saltos adelantan sólo la retirada, frascos más adelante, cuerpo a cuerpo hasta +12 %, puertas hacia donde va); caminar hacia atrás va al 85 %. Escala por oleada y se apaga sola. Números sin playtest: ajustar con `retreat_avg`/`retreat_peak` del log | `RetreatPressure`, `data/combat/retreat_pressure.tres`, `MovementComponent.backpedal_speed_multiplier`, [02 Autoloads](Mayhem/02%20Autoloads.md#combatdirector) |
| Dos arenas más para elegir al darle a Play: *The Ziggurat* (vertical, rey de la colina, zip lines desde la cima) y *The Foundry* (cuartos y pasillos, pasarela con plataformas que se caen, charcos y campos lentos). La default va primera en la lista. Sin playtest todavía | `data/arenas/`, `tools/make_ziggurat_arena.gd`, `tools/make_foundry_arena.gd`, [13 Arena](Mayhem/13%20Arena,%20Venue%20and%20Crowd.md) |

### Lo que entró el 2026-10-28

| Qué | Dónde |
|---|---|
| Armas con modelos de Meshy (pistola, subfusil, rifle, escopeta). Los placeholder `.fbx` se borraron | `tools/blender/build_weapons.py`, `data/weapons/` |
| Recarga animada por arma: sale el cargador (rifle, subfusil), la corredera va atrás (pistola), entra un cartucho y se bombea (escopeta), y el arma se inclina. Reemplaza el giro de 360° | clip `reload` de cada `.glb`, `WeaponData.reload_tilt_degrees`, `WeaponComponent._pose_parts()` |
| Rusher, Bomber, Healer, Ranger y Flyer con modelos de Meshy. Rusher y Ranger traen `idle`, `run` y `attack`. Los modelos viejos se borraron, y `LeggedGait` con ellos | `tools/blender/build_enemy_models.py`, `data/enemies/` |
| Brazos de primera persona de Meshy sobre el mismo esqueleto, clips e IK; manos y armas a escala entre sí | `tools/blender/build_fp_arms.py`, `viewmodel_scale` |
| Props de Meshy: pisos, plataformas, pasarela, rampas y pilar con arte (la colisión sigue siendo la greybox, salvo las rampas, que chocan con su modelo); caja de munición, bounce pad, puerta de spawn y la pantalla gigante del coliseo | `tools/blender/build_props.py`, `PieceDefinition` grupo Art, `ArenaColiseum.jumbotron_scene` |
| Environmental y Summoner con modelos de Meshy (tanque de ácido con patas y brazo lanzador, hechicero de túnica), con sus clips; ancla de grapple y plataforma móvil con modelo, con el telegrafo como brillo encima de la textura | `build_enemy_models.py`, `build_props.py`, `TelegraphComponent.overlay` |
| Contorno de cada enemigo en el color de su arquetipo, para que se recorten contra el piso oscuro | `enemy_outline.gdshader`, `Tokens.ENEMY_OUTLINE_PX`, 2 px |
| Piso con variedad: tres variantes de baldosa (rota, circuitos, rejilla) en un 30 % de las celdas, fijas por celda | `PieceDefinition.art_variants`, `build_props.py` |
| Visor de armas (dev): ajustar en vivo cómo queda cada arma y las manos, y guardarlo. Las manos tienen corrección por arma (la pistola agarra más arriba) | `scenes/main/weapon_viewer.tscn`, `WeaponData.viewmodel_grip_offset` |
| Ancla de grapple con color propio (violeta, 5° significado de la ley de color) y luz propia, que se enciende más en rango | `Tokens.WORLD_GRAPPLE`, `TelegraphComponent.Meaning.GRAPPLE`, `GrappleAnchor.light` |
| Más luz en la arena (luna, ambiente y exposición), y armas más chicas y más bajas en pantalla, con brazos a escala | `coliseum.tres`, `coliseum_env.tres`, `viewmodel_scale`, `ViewmodelArms.ARM_SCALE` |
| Paredes (1x1, 2x1, esquina) y cobertura baja con modelo. La esquina choca con su L | `build_props.py`, `PieceDefinition.art_bounds` / `art_collision` |
| Gadgets legibles: al levantarlos la HUD dice qué son, qué hacen y con qué tecla; la ranura muestra nombre y cooldown; en modo equipar se ve el arco y el área donde cae; al detonar se abre el aro del área; los enemigos aturdidos llevan chispas y los ralentizados el contorno índigo; barrera y campo lento parpadean antes de terminar. Colores propios y modelos de Meshy para los cuatro | `UtilityData.summary`, `UtilityAimPreview`, `GadgetAreaRing`, `EnemyStatusMarks`, `Tokens.GADGET_*` |
| Limpieza: fuera el resto del pack de armas viejo, `spiderbot.res`, `ual1_standard.res`, `ammobox_low.res`, `UAL1_Standard_RM.glb` y los `.blend` y scripts viejos del Environmental y el Summoner, que ya no usaba nada | — |

### Lo que entró el 2026-10-30 (pase visual, rama `feat/visual-pass`)

| Qué | Dónde |
|---|---|
| Cada ranura de gadget dice tecla y palabra (`Q · STUN`, `X · WALL`, `C · SLOW`) | `UtilityData.tag`, `HUD._utility_keybind_text()` |
| Muerte de enemigos: esquirlas en el color del arquetipo, humo (flipbook) y un destello de luz. Del pool | `EnemyDeathBurst`, `Tokens.DEATH_*` |
| Marcas de impacto en concreto y metal (scorch y scratch del pack de partículas), giradas al azar y con fundido | `data/surfaces/`, `ImpactEffect.DECAL_FADE` |
| Humo que queda después de la explosión del Bomber | `explosion.tscn`, `Explosion.smoke_time` |
| SSAO en el coliseo, con opción para apagarla (apagada por defecto en GPU integrada); contraste y saturación un poco más altos | `coliseum_env.tres`, `video/ambient_occlusion`, `SettingsManager.register_world_environment()` |
| Contorno de enemigos más fino (1.25 px, era 2) y con opción de ancho (0.5 a 3 px) | `video/enemy_outline_px`, global de shader `enemy_outline_px` |
| Piso más mate: un 30 % del metálico y el especular del modelo | `PieceDefinition.art_shine` |
| Luz de acento: puertas de spawn con luz tenue en reposo, y un cono de luz desde la pantalla gigante | `SpawnDoor.LIGHT_IDLE_ENERGY`, `ArenaColiseum.jumbotron_light_*` |
| Menos brillo decorativo: ventanas de la ciudad y retícula de la pared de energía | `city_block.gdshader`, `energy_wall.gdshader` |
| Fotos del juego para comparar un cambio visual | `tools/capture_arena.gd`, `profile_elite_wave.gd shot=` |
| Viewmodels nuevos: brazos y arma en una sola malla de Meshy por arma, con el lanzador del gancho modelado en la muñeca. Reemplazan al rig de brazos con IK y a las armas sueltas, que se borraron (`ViewmodelArms`, `ViewmodelArmIK`, `fp_arms.glb`, `assets/models/weapons/`, `build_fp_arms.py`, `build_weapons.py`, el clip `reload` por pieza y las correcciones de mano de `WeaponData`) | `tools/blender/build_viewmodels.py`, `assets/models/viewmodels/` |
| Animación del viewmodel, todo el bloque: sacar el arma (sube desde abajo), respiración, recarga (baja, se inclina y golpea al entrar el cargador), kick y giro al tirar el gancho | `WeaponComponent._tick_viewmodel()` |

Se probó AgX en lugar de ACES y quedó ACES, con más contraste en los neones.

### Lo que entró el 2026-10-30 (playtest, rama `fix/playtest-tuning`)

| Qué | Dónde |
|---|---|
| Todos los enemigos un 20 % más rápidos (Rusher 8.6, Bomber 6.5, Flyer 6.7, Healer 6.0, Ranger 5.3, Summoner 4.8, Environmental 4.6, Elite 4.3) | `data/enemies/*.tres` |
| Environmental de 2.0 m (era 2.5) y un poco más ancho: no pasaba bajo una plataforma de nivel 1, que deja 2.25 m. Un test lo fija para todos los arquetipos | `environmental.tres`, `Tokens.ENEMY_HEIGHT`, `test_every_walker_fits_under_a_first_level_platform` |
| HUD: las ranuras de gadget quedaban corridas (el nombre invisible ensanchaba su columna); el cartel de oleada limpia pisaba el timer | `HUD._make_slot()`, `Tokens.SLOT_COLUMN_W`, `match_overlay.tscn` |

### Lo que entró el 2026-10-30 (codex, rama `feat/codex`)

| Qué | Dónde |
|---|---|
| Codex desde el menú y la pausa: una ficha por arma, mejora, rara, gadget, enemigo, attachment, regla, contrato, pedido del público y bono de estilo, con lo que hace y sus números. Todo visible desde el principio. Lee los mismos pozos que el juego: un `.tres` nuevo aparece solo | `CodexPanel`, `CodexCatalog`, [07 UI and HUD](Mayhem/07%20UI%20and%20HUD.md#codex) |
| Texto para el jugador donde no había: descripción de cada arma, descripción y "cómo se le gana" de cada enemigo, cómo se cobra cada bono de estilo | `WeaponData.codex_blurb`, `EnemyData.codex_blurb`/`codex_tip`, `KillBonusTracker.BONUS_DESCRIPTION` |

### Lo que entró el 2026-11-02 (revisión de bugs, rama `fix/review-bugs`)

| Qué | Dónde |
|---|---|
| Tienda: la columna YOUR BUILD crecía una fila por mejora y con ~15 empujaba el panel fuera de los 1080 de alto; el botón de avanzar quedaba fuera de pantalla y sólo se salía por el reloj (reporte de un jugador en la ola 5). Ahora scrollea | `shop_screen.tscn` (`Build/VBox/Scroll`), `test_a_long_build_does_not_push_the_shop_off_screen` |
| Tienda: la R del reroll cobraba con el menú de pausa abierto; una mejora atada a un arma no se ofrece con otra en la mano | `ShopScreen._on_reroll_pressed()`, `Shop._build_pool()` |
| Mejoras más caras: comunes ×1.4, raras ×1.25. Seis comunes nuevas, con contrapartida: Hair Trigger, Hollow Points, Speed Loader, Tension Spool, Featherweight y Riot Padding (iconos geométricos provisorios). Sin playtest | `data/upgrades/`, `shop_catalog.tres` |
| Fuera las zip lines: script, escena, pieza del editor, la acción `interact` (F) y su retícula. Una arena guardada con una zip line carga igual: una pieza que no está en el catálogo es aviso, no error | `Player`, `HUD`, `Validator` |
| La última kill de una oleada se cobra antes de cerrarla: entra al desglose, lleva el multiplicador de la regla y cuenta para el pedido del público | `Enemy._on_died()` |
| La caja de munición y los regalos del público se levantan estando encima en cuanto hay lugar, sin salir y volver a entrar | `AmmoPickup`, `CrowdDropPickup` |
| La granada aturdidora reciclada del pool vuelve a mostrar el destello; el gancho desde un slide ya no deja la cámara baja | `StunGrenade._flash()`, `MovementComponent._handle_action_input()` |
| Sin hitstop: ni impactos, ni headshots, ni kills frenan el tiempo (`Engine.time_scale`). El peso del tiro pasa a un sacudón de cámara leve (roll de décimas de grado) y un oscurecimiento leve de los bordes, más fuerte en una kill. Sin playtest. El fogonazo del arma es uno por arma y se reinicia en cada tiro, en vez de crear un nodo y un material por disparo | `HitstopController` (borrado), `CameraRecoilComponent` grupo Shake, `ShotPulseOverlay`, `Tokens.SHOT_PULSE_*`, `MuzzleFlash` |

### Lo que entró el 2026-11-03 (preparar el playtest, rama `feat/playtest-prep`)

| Qué | Dónde |
|---|---|
| Protocolo de playtest escrito: quién juega, qué se observa, entrevista, qué contesta cada campo del log | [PLAYTEST.md](PLAYTEST.md) |
| Capas del show que se apagan para una tanda de prueba: rating, reglas, contratos, pedidos del público. Por línea de comandos en un build exportado (`-- --layers=-rating`), por consola (`layers`) o por `.tres`. Todo encendido por defecto | `PlaytestLayers`, `data/playtest/playtest_layers.tres`, `MatchDirector.apply_layers()` |
| Log formato 4: capas apagadas, uso de la movilidad por oleada (slide, aire, gancho, parado, velocidad media, ganchos, picadas), gadgets tirados, tiempo en la tienda | `RunLogger` |
| Resumen de una tanda: muertes por ola, qué mata, contratos, pedidos, movilidad por ola, separado por capas | `tools/summarize_runs.py` |
| El reporte de feedback guarda las capas y el log de la última run adentro | `FeedbackManager.save_report()` |
| Aviso de ataque fuera de cuadro: chevron hueco en el borde que se llena con la preparación del enemigo. Opción en HUD, encendida. Sin playtest | `ThreatIndicators`, `Tokens.THREAT_*`, `hud/threat_indicators` |

### Lo que entró el 2026-11-03 (sinergias, rama `feat/upgrade-synergies`)

| Qué | Dónde |
|---|---|
| Familias de mejoras: cada una de las 40 lleva una o dos etiquetas (aire, momentum, gancho, precisión, armadura, munición, potencia, estilo) | `UpgradeData.tags`, `data/upgrades/` |
| Cuatro raras que escalan con una familia: Aerialist (aire), Deadeye (precisión, de arma), Streamliner (momentum, cobra vida por armadura) y Bulwark (armadura, cobra velocidad por momentum). Iconos geométricos provisorios. Sin playtest | `StatModifier.per_tag`, `UpgradeManager.count_tag()`, `HEADSHOT_DAMAGE_MULTIPLIER` |
| La tarjeta de la tienda dice la familia, qué rara del build alimenta o le cobra, y cuánto de su familia hay; el Codex muestra FAMILY y SCALES WITH | `Shop.synergy_fields()`, `ShopScreen._add_synergy_lines()`, `CodexCatalog` |

### Lo que entró el 2026-11-03 (mejores momentos, rama `feat/run-highlights`)

| Qué | Dónde |
|---|---|
| Pantalla de fin con los tres mejores momentos de la run (rafaga, racha sin daño, velocidad, kill con más bonos, tiro más largo, headshots, oleadas limpias, oleada más rápida contra su par), pesados contra lo que hace una run buena | `RunHighlights`, `RunSummary._build_moments()`, `RunRecord` |
| Tarjeta para compartir: PNG de 1200x630 con resultado, puntaje, momentos, trofeos y código de la run, en `user://share/`. Sirve para la página de itch y el trailer | `ShareCard`, botón *Save run card* en `MatchOverlay` |
| El texto que se copia suma el mejor momento | `MatchOverlay._on_run_finished()` |

### Lo que entró el 2026-11-03 (CPU y shaders, rama `chore/enemy-cpu-and-shader-warmup`)

| Qué | Dónde |
|---|---|
| Un enemigo no le pide camino nuevo al navmesh si el destino se movió menos de 0.75 m y el camino viejo sigue vigente. Era el primer paso de [PLAN_MEJORAS §4.0](planes/PLAN_MEJORAS.md) | `Enemy.set_move_target()`, `REPATH_DISTANCE` |
| Un enemigo de a pie quieto en el piso saltea `move_and_slide()` hasta 3 frames seguidos (uno de cada cuatro corre igual, para enterarse si el piso desaparece) | `Enemy._can_skip_slide()`, `IDLE_SLIDE_SKIP` |
| Precalentado de shaders: con la pantalla todavía tapada, se dibuja dos frames una copia sin scripts ni colisión de cada efecto de pelea y de cada modelo de enemigo | `ShaderWarmup`, `data/render/shader_warmup.tres`, `GameManager._warm_shaders()` |

**Sin medir todavía**: falta correr `tools/profile_elite_wave.gd` en la 680M antes y
después (§5). Los dos cambios de CPU apuntan a los ~2.8 ms de navegación y ~2.5 ms
de mover cuerpos de la ola 10.

### Lo que entró el 2026-11-03 (changelog, rama `chore/changelog-semver`)

| Qué | Dónde |
|---|---|
| `CHANGELOG.md` generado desde los Conventional Commits, con la versión que toca según semver (en 0.x un cambio que rompe sube la minor). Tag `v0.3.0` (local, retroactivo, sobre `7290bf7`, el commit que puso esa versión) como punto de partida. El paso va primero en el checklist del build | `tools/changelog.py`, [EXPORT.md](EXPORT.md#checklist-before-tagging-a-build) |

## 2. Bloquea el release

| # | Qué | Tipo |
|---|---|---|
| R1 | **Modelos** de piezas de arena, interactuables y un enemigo (Elite). Ya resuelto: brazos y Summoner con modelo y clips (2026-10-19; los brazos de Meshy, 2026-10-28, llegaron sin textura y usan un material liso hasta que haya una), Environmental con modelo y clips (2026-10-22), armas escaladas a las manos, y (2026-10-20) lanzador de gancho en la muñeca con cable y una silueta por gadget del público (`tools/build_gadget_meshes.gd`). Falta un pase en juego mirando el cable del gancho contra el ancla. Pedido de arte en [HANDOFF_ARTE.md](handoffs/HANDOFF_ARTE.md) | Arte |
| R2 | **Audio de armas, enemigos e impactos.** Armas (2026-10-31): SMG, rifle y escopeta tienen disparo, recarga y vacío nuevos, armados de packs CC0 (Kenney Sci-fi Sounds y "gun reload sounds" de OpenGameArt; no piden créditos); la pistola se quedó con los suyos a propósito. Los disparos son capas de estallido, metal y grave: suenan a arma sci-fi, no a pólvora; para algo realista quedan el pack de f8studios (licencia sin confirmar) o Sonniss GDC. Enemigos (2026-10-31): Ranger, Bomber, Healer, Summoner, Environmental y Flyer con sonidos nuevos de los mismos packs más "monster sound effects 2" y "80 CC0 creature SFX #2" (CC0), varias voces con modulación en anillo para que suenen a robot; el Rusher entero, el ataque y la mecha del Bomber y la muerte del Healer se quedaron con los suyos a propósito. El Elite (en el banco) y los impactos siguen con los de `tools/generate_placeholder_sfx.py`. Falta la mezcla real en juego | Audio |
| R3 | **Playtest de los sistemas nuevos.** Rating, reglas, raras y tutorial tienen tests pero ningún número jugado: `data/economy/rating_config.tres`, los costos de las raras y la duración de los pasos del tutorial son de escritorio. También las oleadas nuevas del 2026-10-21 (conteos y `par_time`): la 9 y la 10 pueden pasar el techo de CPU de §5. Desde el 2026-10-16 también: pagos de contratos, `peak_bonus` y `walkout_after`, metas y tiempos de los pedidos, costos de las raras por arma, umbrales de maestría (`attachment_catalog.tres`) y los números de cada attachment. Desde el 2026-11-03: los números y costos de las cuatro raras de sinergia. Desde el 2026-10-21: los números de la caída rápida, `weapon_offer_chance`, el tope de brillo del Summoner y `PlayerPerks.RAM_MIN_SPEED` | Balance |

## 3. Abierto — necesita una decisión

- **Estilo visual** (rama `feat/visual-style`, prototipo): opción en Video con
  Estándar, Claridad (default de la rama) y Toon. Claridad: borde sólo en lo
  que se juega, en el color de su significado, y el fondo (cuenco, público,
  ciudad, pared de energía) retrocede. Antes se probaron el toon (la tinta no se
  leía de noche y en brazos y arma era demasiado; queda como opción) y un neón
  con filo en todo el mapa (excesivo; descartado). Falta jugarlo con alguien que
  no conozca el juego, ajustar `SEMANTIC_OUTLINE_PX` (2 px) y `BACKGROUND_DIM`, y
  medirlo en la 680M (en una RX 7700 XT: +41 draw calls y +0.07 ms de GPU).
  Las 32 texturas `_toon.png` (14 MB) sólo sirven al toon: si el toon no queda,
  se borran. Detalle en [08 VFX and Shaders](Mayhem/08%20VFX%20and%20Shaders.md).

- **Legibilidad de gadgets, lo que falta del plan:** un paso del tutorial que
  enseñe a levantar y usar un gadget; vista previa del arco también en quick cast (hoy sólo en modo
  equipar, porque en quick cast el gadget sale al apretar); y un sonido y una
  frase del Host propios por gadget. Los colores nuevos y la marca de aturdido
  están sin playtest.
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
- **Arte de VFX.** Picada y slide siguen grey-box. Los impactos tienen marca
  (scorch y scratch del pack) pero las chispas son las de siempre. De los
  flipbooks se usan dos humos; el resto sigue fuera del build (ver EXPORT).
- **Pase visual en juego** (2026-10-30): mirar jugando la muerte de enemigos, el
  piso mate, la SSAO, la luz de la pantalla gigante y el contorno en 1.25 px; y
  medir la SSAO en la 680M (este pase solo se midió con la SSAO apagada, que es
  el default de una integrada).
- **Viewmodels nuevos, a mano:** tamaño y lugar en pantalla de los cuatro (hoy
  los mismos números para todos, ajustar con el visor de armas), que el cable
  del gancho salga de la muñeca de cada uno, y si la recarga sin manos que se
  muevan alcanza. Los modelos llegan bastante metálicos; si brillan de más, se
  baja en `build_viewmodels.py`.
- **`profile_elite_wave.gd` no mide la ola 10.** Al forzarla la run termina
  (sale "RUN RECORDED" con la ola viva) y el muestreo corre con el juego en la
  pantalla de fin: da ~240 FPS que no dicen nada. Visto el 2026-10-30.
- **`EXPORT.md` excluye `assets/models/props/*`**, pero los pisos, paredes,
  rampas, puertas y la pantalla gigante salen de ahí desde que tienen modelo.
  Con ese filtro el build se queda sin arte de arena. Revisar antes del release.
- **Mezcla de audio real** (oídos, auriculares y parlantes).
- **URL del formulario de feedback** vacía en `data/feedback/feedback_config.tres`.
- **Iconos de las raras por arma (8), de las raras de sinergia (4) y del bono RECOMPENSA**: geométricos
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
  dash, grapple, enemigos saliendo de las puertas, trazadoras, haces
  del Healer y numeros de daño. Ningun test ve un frame dibujado.
  Tambien el **movimiento de la UI** (rama `feat/ui-juice`): reparto de cartas,
  brillo y sonido de la rara, golpe de los numeros de la HUD, cartel de oleada;
  y si los sonidos nuevos de `assets/audio/sfx/ui/` (placeholders) quedan bien
  en la mezcla.
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

- Partir `enemy.gd`: la presentación ya salió a `EnemyPresentation` (rama `chore/split-enemy`, 2026-11-03; ~2480 líneas). Falta el bloque de locomoción (~900 líneas), que comparte estado con el volador y el detector de atasco y que ~40 líneas de tests leen directo: ver [12 Known Issues](Mayhem/12%20Known%20Issues%20and%20Gaps.md#fragile).
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
