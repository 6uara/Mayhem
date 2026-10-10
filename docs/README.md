---
tags: [mayhem, indice]
estado: vivo
actualizado: 2026-10-09
---

# Documentación de MAYHEM

Dónde está cada cosa, y cuál manda cuando dos dicen distinto.

## Fuente de verdad, por pregunta

| Pregunta | Documento |
|---|---|
| ¿Qué es el juego y qué reglas de diseño no se rompen? | [DISENO.md](DISENO.md) |
| ¿Qué falta? ¿Qué bloquea el release? | [ESTADO.md](ESTADO.md) |
| ¿Cómo funciona el código hoy? | [Vault técnico](Mayhem/00%20Home.md) |
| ¿Qué conviene hacer después? | [planes/PLAN_MEJORAS.md](planes/PLAN_MEJORAS.md) |
| ¿Por qué se hizo así? | [historial/](#historial) y git |

Si el vault y el código no coinciden, manda el código y el vault se corrige. Si
ESTADO y un plan no coinciden, manda ESTADO.

## Estructura

```
docs/
├─ README.md          este índice
├─ DISENO.md          brief de diseño (las citas "CLAUDE.md §N" del código)
├─ ESTADO.md          estado vivo y backlog
├─ ADDONS.md          guías de uso (vigentes)
├─ DEV_TOOLS.md
├─ EXPORT.md
├─ ITCH_PAGE.md
├─ TESTING.md
├─ Mayhem/            vault técnico (Obsidian): el código tal como está
├─ planes/            planes abiertos
├─ handoffs/          pedidos a terceros (arte, iconos)
├─ decisiones/        decisiones de arquitectura con su criterio de reversión
├─ historial/         fases y planes cerrados — no describen el presente
└─ host_script/       generado por tools/export_host_script.gd, no editar a mano
```

`docs/` lleva un `.gdignore`: Godot no lo escanea ni importa nada de acá (antes
importaba el CSV del guion como traducción). Tampoco viaja en los builds (ver el
`exclude_filter` en [EXPORT.md](EXPORT.md)).

## Guías

- [ADDONS.md](ADDONS.md) — addons instalados, parches locales, política para sumar uno.
- [DEV_TOOLS.md](DEV_TOOLS.md) — consola de dev, panel de bonos, editor de arenas in-game, visor de enemigos.
- [EXPORT.md](EXPORT.md) — presets, filtros, checklist antes de taggear un build.
- [ITCH_PAGE.md](ITCH_PAGE.md) — textos de la página de itch.io.
- [TESTING.md](TESTING.md) — cómo correr la suite, convenciones, estado.
- [`addons/mayhem_tools/README.md`](../addons/mayhem_tools/README.md) — el plugin de editor (arenas y balance).

## Planes y handoffs abiertos

- [planes/PLAN_MEJORAS.md](planes/PLAN_MEJORAS.md) — huecos de diseño, profundización de gameplay, performance.
- [planes/PLAN_NEW_ENEMY_TYPES.md](planes/PLAN_NEW_ENEMY_TYPES.md) — sólo queda §5, los Gladiadores.
- [handoffs/HANDOFF_ARTE.md](handoffs/HANDOFF_ARTE.md) — boards de concepto para brazos, arena, interactuables y venue.
- [handoffs/HANDOFF_ICONOGRAPHY.md](handoffs/HANDOFF_ICONOGRAPHY.md) — iconos; pendientes §3.6 y §3.7.
- [decisiones/DECISION_navegacion_arenas.md](decisiones/DECISION_navegacion_arenas.md) — grilla + A* en el editor, navmesh en runtime.

## Historial

Se conservan como registro: el porqué de cada decisión está ahí. Ninguno describe
el estado actual.

| Documento | Qué registra |
|---|---|
| [PHASE_0](historial/PHASE_0.md) … [PHASE_5](historial/PHASE_5.md) | Las seis fases de construcción |
| [PLAN_BACKLOG_RESTANTE](historial/PLAN_BACKLOG_RESTANTE.md) | El backlog de agosto, tandas A-G, con instrucciones por tarea (las de G3-G9 siguen valiendo) |
| [BACKLOG_ESTADO](historial/BACKLOG_ESTADO.md) | Auditoría de ese backlog al 2026-08-25 |
| [HANDOFF_FEEL_AND_FIXES](historial/HANDOFF_FEEL_AND_FIXES.md) | Revisión de feel: balas que atravesaban, hitboxes, dash |
| [PLAN_PERFORMANCE](historial/PLAN_PERFORMANCE.md) | Primer pase de performance y números de daño |
| [PLAN_ENEMY_BEHAVIOR](historial/PLAN_ENEMY_BEHAVIOR.md) | Qué pregunta hace cada enemigo |
| [PLAN_COMBAT_DIRECTOR](historial/PLAN_COMBAT_DIRECTOR.md) | Coordinación de la horda; por qué el Elite salió del pool |
| [PLAN_CROWD_DROPS](historial/PLAN_CROWD_DROPS.md) | El público tira los gadgets |
| [PLAN_COLISEO](historial/PLAN_COLISEO.md) | El venue generado |
| [PLAN_QOL_SHIP](historial/PLAN_QOL_SHIP.md) | Gancho, visibilidad nocturna, arena fija, leaderboard, créditos, feedback |
| [PLAN_PULIDO](historial/PLAN_PULIDO.md) | Pulido de septiembre |

## Convenciones

- **Front matter** en todo `.md`: `tags`, `estado` (`vivo`, `guia`, `referencia`,
  `activo`, `decision`, `historico`) y `actualizado` (fecha del último cambio de
  contenido).
- **Idioma**: lo nuevo en español. El vault está en inglés con pasajes en español
  y no se traduce. Los prompts para herramientas externas van en inglés.
- **Un estado, un lugar**: lo que falta va a [ESTADO.md](ESTADO.md). Un plan se
  escribe para *ejecutar* algo; cuando se cierra, se mueve a `historial/` con su
  banner, y lo que quedó abierto pasa a ESTADO.
- **Lo resuelto se borra**, no se tacha: git guarda la historia.
- **Indentación con espacios** en markdown. Un editor que convierte a tabs (la
  convención de GDScript) rompe las listas anidadas; ya pasó una vez.
- **Medido vs. propuesta**: lo verificado en el código se marca *(medido)*; lo
  que es opinión de diseño, *(propuesta)*.
