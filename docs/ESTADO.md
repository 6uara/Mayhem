---
tags: [mayhem, estado, backlog]
estado: vivo
actualizado: 2026-10-09
---

# MAYHEM — Estado del proyecto

**Única fuente de "qué falta".** Reemplaza como estado a
[BACKLOG_ESTADO](historial/BACKLOG_ESTADO.md) (agosto) y a la sección de
abiertos de [PLAN_PULIDO](historial/PLAN_PULIDO.md) (septiembre), que quedan en
el historial. Cuando algo se cierra se borra de acá y se anota en el commit; cuando
aparece algo nuevo, se agrega acá y no en un plan suelto.

Base: rama `docs/regularizacion` sobre `develop` @ `1a37794`. Suite: **1117 tests,
1117 en verde** (2026-10-09, Godot 4.7.1, ver [TESTING.md](TESTING.md#estado-actual-de-la-suite)).

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

## 2. Bloquea el release

| # | Qué | Tipo |
|---|---|---|
| R1 | **Modelos** de todo lo que no es arma: brazos, piezas de arena, interactuables, gadgets, y tres enemigos (Elite, Environmental, Summoner). Pedido de arte en [HANDOFF_ARTE.md](handoffs/HANDOFF_ARTE.md) | Arte |
| R2 | **Audio de armas e impactos** sigue siendo el sintetizado por `tools/generate_placeholder_sfx.py` | Audio |
| R3 | **Playtest de los sistemas nuevos.** Rating, reglas, raras y tutorial tienen tests pero ningún número jugado: `data/economy/rating_config.tres`, los costos de las raras y la duración de los pasos del tutorial son de escritorio | Balance |

## 3. Abierto — necesita una decisión

- **Curva de oleadas.** La 5 tiene `par_time` 95 y bonus 150; la 6 baja a 85 y
  110. Si la 5 es un pico a propósito, documentarlo. Mejor con logs de
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

## 4. Abierto — necesita un asset o una persona

- **Voz del Host.** `assets/audio/voice/` vacío; el guion está en
  [host_script/](host_script/host_script.md). Las líneas nuevas (reglas, rating,
  tutorial, Second Wind) entran en el próximo `tools/export_host_script.gd`.
- **Arte de VFX.** Impactos, dash y slide siguen grey-box; decals por superficie
  en `null`; los flipbooks del pack sin usar (y fuera del build, ver EXPORT).
- **Mezcla de audio real** (oídos, auriculares y parlantes).
- **URL del formulario de feedback** vacía en `data/feedback/feedback_config.tres`.
- **Iconos** de menús (11) y del editor de arenas (21):
  [HANDOFF_ICONOGRAPHY §3.6-3.7](handoffs/HANDOFF_ICONOGRAPHY.md). Los 9 de las
  mejoras nuevas son geométricos provisorios en el mismo lenguaje.
- **Probar a mano:** punch del dash, FSR a 50-67 %, MSAA/TAA, sombras en Bajo, una
  oleada con joystick, el tutorial completo, el giro de los enemigos con la IA a
  ritmo espaciado.
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
