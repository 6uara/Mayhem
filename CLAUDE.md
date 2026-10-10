# MAYHEM — guía para trabajar en el repo

Shooter de arena en primera persona, un jugador. Godot 4.7, GDScript tipado, Jolt,
Forward+. Índice de toda la documentación: [docs/README.md](docs/README.md).

## Las citas `CLAUDE.md §N` del código

El código y los tests citan un brief original por número de sección
(`CLAUDE.md 5.3`, `CLAUDE.md 5.5`…). Ese brief nunca se versionó; está
reconstruido con la misma numeración en **[docs/DISENO.md](docs/DISENO.md)**.
Leé la sección citada antes de cambiar código que la cita.

## Antes de tocar algo

- Qué falta y qué bloquea: [docs/ESTADO.md](docs/ESTADO.md).
- Cómo funciona hoy: [docs/Mayhem/](docs/Mayhem/00%20Home.md) (vault técnico).
- Lo que hay en `docs/historial/` describe el pasado, no el presente.

## Reglas

- **Tipado estricto.** `untyped_declaration` es warning: toda variable, parámetro,
  retorno y elemento de array lleva tipo.
- **Datos fuera del código.** Clases en `scripts/resources/`, instancias `.tres` en
  `data/`. Un número de balance nuevo va en un `.tres`.
- **`EventBus` es sólo señales**, agrupadas por dominio, con comentario de una línea.
- **Audio por `AudioPool`**, objetos de alta rotación por `ObjectPool`.
- **Colores, medidas y tiempos desde `Tokens`** (`scripts/autoload/theme_tokens.gd`).
  La ley de color tiene tests: [09 Design Tokens and Color Law](docs/Mayhem/09%20Design%20Tokens%20and%20Color%20Law.md).
- **Comentarios que explican el porqué**, en el idioma del archivo que tocás.

## Tests

```powershell
pwsh tools/run_tests.ps1                     # suite completa (busca Godot o usa $env:GODOT)
pwsh tools/run_tests.ps1 -Script res://tests/unit/test_x.gd
```

Nombres en prosa (`test_dashing_bursts_the_dash_trail`). Un test que lee
`SettingsManager` setea y restaura cada clave que lee (`tests/settings_guard.gd`).
Detalle en [docs/TESTING.md](docs/TESTING.md).

## Git

- Ramas `feat/*`, `fix/*`, `chore/*`, `docs/*` desde `develop`; Conventional
  Commits con scope (`feat(shop): …`).
- **Godot re-guarda escenas solo** al cargar el proyecto, incluso headless.
  `git diff` sobre todo `.tscn`/`.tres` antes de commitear si corrió Godot.

## Docs

Convenciones (front matter, idioma, dónde va cada cosa) en
[docs/README.md](docs/README.md#convenciones). Lo que falta se anota en
`docs/ESTADO.md`, no en un plan suelto.
