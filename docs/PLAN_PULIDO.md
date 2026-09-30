---
tags: [mayhem, plan, pulido]
---

# MAYHEM — Plan de pulido y optimizacion (2026-09-30)

Revision general del proyecto de cara al release en itch.io, y lo que se hizo de
ella en la misma sesion. Reemplaza como "estado actual" a
[BACKLOG_ESTADO.md](BACKLOG_ESTADO.md), que quedo del 2026-08-25 y no conoce el
coliseo, el publico ni los modelos nuevos.

Suite al cerrar: **1028 tests**, todos en verde salvo lo que dice §4.

---

## 1. Hecho

| # | Que | Commit |
|---|---|---|
| P0-1/2 | Hitbox de Ranger (0.45) y Summoner (0.8), y un test que mide la silueta dibujada de cada arquetipo contra su hitbox (75% de los vertices adentro) | `9955e7f` |
| P0-3 | Reaccion de camara al dash: punch de FOV + kick opuesto, curva criticamente amortiguada, respeta screen shake y ADS | `79901a7` |
| P0-4 | El leaderboard valida las filas al cargar; los tests restauran el archivo byte a byte (antes le borraban trofeos y fechas a las runs reales) | `5cc38f9` |
| P0-5 | `award_wave_bonuses` sobrevive a una ola null | `cdba8e8` |
| P0-6 | Perder el foco en PLAYING pausa | `6cffad4` |
| P0-7 | Textos OFL junto a las fuentes + `include_filter` en los presets | `5e5ea81` |
| P2-1 | Render scale (FSR 1), anti-aliasing (FXAA/MSAA/TAA), calidad de sombras | `e4c981a` |
| P2-2 | Tope de FPS por defecto = frecuencia del monitor (fallback 60) | `e4c981a` |
| — | Rebind de teclas: seccion CONTROLS, 15 acciones, swap al pisar otra, respeta bindings de joystick | `e4c981a` |
| P2-3 | Gamepad: bindings Xbox en todas las acciones de juego, look con stick (curva cuadratica) y su sensibilidad. Sin aim assist | `1692ab1` |
| P3-1 | Los casquillos que aterrizaban no se liberaban nunca: un nodo por disparo, toda la run | `eac8628` |
| P3-2 | `PoolPrewarmer`: proyectil, impacto, proyectil enemigo y explosion se prewarmean en la carga | `eac8628` |
| — | Salir al menu desde la pausa dejaba a los enemigos pooleados vivos bajo el menu; ahora el pool se vacia en todo cambio de escena | `6cffad4` |
| P3-4 | El Healer busca pacientes en la lista de vivos y no en el grupo | `13249a9` |
| P3-6 | `tests/settings_guard.gd`: los tests de settings restauran valores, bindings y el `settings.cfg` | `e4c981a` |
| P4 | `RunLogger`: un JSON por run en `user://runs/` (por ola: duracion vs par, daño, kills por tipo, headshots; compras, disparos, ola de muerte). La pantalla de feedback nombra la carpeta | `ddc48b0`, `2348408` |
| — | Dos tests rotos: el de muerte en `test_match_flow` (corria sin spawner) y una carrera de frames en `test_scene_transition` | `b2bb4e8`, `6122e61` |

## 2. Resuelto sin tocar nada

- **P1-1, velocidad de proyectil.** El handoff de feel lo medía sobre balas
  fisicas, pero las armas del jugador ya son hitscan (`WeaponData.is_hitscan`,
  true por defecto); `projectile_speed` solo mueve la trazadora. No hay adelanto
  que decidir.

## 3. Abierto — necesita una decision o un asset

- **Licencias de la musica.** Los seis tracks de `assets/audio/music/` no tienen
  origen registrado ([CREDITS.md](../assets/audio/music/CREDITS.md)). Bloquea el
  release.
- **Audio de armas e impactos (P1-2).** Siguen siendo los sintetizados por
  `tools/generate_placeholder_sfx.py`; impactos son 2 archivos. Hace falta audio
  real, con capas y variacion.
- **Voz del Host (P1-3).** `assets/audio/voice/` vacio; el guion ya esta en
  `docs/host_script/`.
- **Modelos (P1-4).** Elite, Environmental y Summoner siguen en primitiva, y
  **no hay fuente**: `assets/models/enemies/Elite/` esta vacia y no hay carpeta
  de Environmental ni Summoner. Cuando entren, el test de silueta dice si su
  hitbox alcanza.
- **Arte de VFX (P1-5).** Impactos y dash/slide siguen grey-box; los flipbooks de
  humo del pack siguen sin usar. Es trabajo de arte que hay que mirar en pantalla.
- **Curva de oleadas (P1-6).** La ola 5 tiene `par_time` 95 y bonus 150, la 6 baja
  a 85 y 110. Si la 5 es un pico a proposito, documentarlo; si no, corregirlo.
  Mejor con los logs de `RunLogger` del playtest en la mano.
- **Dificultad (P2-4).** No se hizo: toca la identidad ("una run, sin saves") y
  la justicia del leaderboard (¿una run en Casual compite con una en Normal?).
  Es una decision de diseño antes que codigo.
- **Aim assist para gamepad.** Sin el, el stick juega en desventaja contra el
  mouse. Necesita su propio pase de diseño.
- **Los carteles de tecla (HUD, hints) muestran siempre el binding de teclado.**
  Con gamepad dicen la tecla, no el boton.
- **URL del formulario de feedback** sigue vacia en `data/feedback/feedback_config.tres`.

## 4. Abierto — tecnico

- **Partir `enemy.gd` (P3-5).** 2400 lineas; el bloque de locomocion y
  navegacion (`_steer` a `_stop_horizontal`, ~900 lineas) es el candidato. No se
  hizo a proposito: es un refactor grande sobre el archivo que mas se toca, justo
  antes del playtest. Mejor en su propia rama despues de G3, con la suite como red.
- **Flaky de navmesh** anotado en G6, sin cambios.
- **Pipeline de shaders.** Los prewarmeados quedan invisibles, asi que su shader
  sigue compilando la primera vez que se ve. Con los ubershaders de 4.4+ deberia
  ser invisible; medirlo con `profile_elite_wave.gd` en la maquina mas lenta que
  haya antes de hacer nada.
- **Para probar a mano** (no se puede desde headless): el punch del dash, FSR a
  50-67%, MSAA/TAA, las sombras en Bajo, y jugar una oleada con joystick.
