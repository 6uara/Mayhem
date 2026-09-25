---
tags: [mayhem, handoff, iconography, ui, design]
---

# Handoff — Iconografía de UI

Para quien dibuje el set de iconos de MAYHEM. Este documento es el pedido
completo: qué iconos hacen falta, con qué reglas se dibujan, cómo se nombran y
cómo entran al juego sin tocar una sola línea de código de pantalla.

Baseline: `develop`, después del bloque de trofeos y bonos de kill.

> **Estado: entregado e integrado.** Los 57 iconos de §3.1 a §3.5 están en
> `ui/icons/` y cableados. Lo que sigue pendiente es §3.6 (menús) y §3.7 (editor).
> Ver §7 para qué se integró dónde.

---

## 0. Leer esto primero

**El set ya existe y funciona.** Hay 25 iconos dibujados por código en
[`scripts/ui/mayhem_icon.gd`](../scripts/ui/mayhem_icon.gd): rectángulos,
círculos, triángulos y un *skew*, sobre grilla 64×64 con trazo de 4px. No son un
placeholder roto — son legibles, escalan sin perder nitidez y ya están cableados
en la HUD.

Lo que este handoff pide es **dos cosas distintas**, y conviene no mezclarlas:

1. **Iconos que faltan** (§3). Son ~45 y hoy se muestran como texto, o
   directamente no se muestran. Esto es trabajo nuevo y es lo urgente.
2. **Reemplazar los 25 que existen** (§2). Es opcional y no bloquea nada. Si el
   set dibujado a mano queda mejor, entra; si no, los procedurales se quedan.

**La vía de entrada ya está construida.** `MayhemIcon` tiene una propiedad
`texture`: asignarla hace que el icono dibuje ese PNG en vez de la geometría, sin
cambiar nada en ningún punto de uso. Migrar el set entero es dejar los archivos y
setear `texture`.

---

## 1. Las reglas del set

No son negociables porque el resto del juego ya está construido sobre ellas.

### Grilla y trazo

| Regla | Valor | De dónde sale |
| --- | --- | --- |
| Grilla de autoría | 64×64 | `MayhemIcon.GRID`, `Tokens.ICON_GRID` |
| Trazo | 4px a 64 | `MayhemIcon.STROKE`, `Tokens.ICON_STROKE` |
| Margen seguro | 4px por lado | `MayhemIcon.content_rect()` |
| Tamaño en ranura de HUD | 28px | `Tokens.SLOT_ICON` |

Todo se dibuja en unidades de grilla y se escala: una definición sirve para 24px
y para 256px. **El trazo escala con el icono** — a 28px el trazo efectivo es
1.75px, así que nada puede depender de un detalle más fino que eso.

### Vocabulario de formas

El juego ya enseña un idioma de formas y los iconos tienen que hablarlo. Está en
`Tokens.SHAPE_FOR` y en la ley de color de la arena:

| Forma | Significa | Color |
| --- | --- | --- |
| Cuadrado / corchete | **Tuyo**: vida, munición, dash, gancho, traversal | `PLAYER` `#35E0D4` |
| Diamante / chevron | **Amenaza**: enemigos, daño recibido, hitmarkers | `ENEMY` `#FF3B54` |
| Círculo | **Recompensa**: moneda, pickups, voz del Host | `REWARD` `#FFB020` |
| Triángulo | **Peligro**: trampas, oleadas de élite, power-ups | `HAZARD` `#FC3A00` |

El color nunca es la única señal. Un icono que solo se distingue de otro por ser
rojo en vez de ámbar está mal dibujado.

### Color

Los iconos se dibujan **monocromos**, en un solo color plano, y quien los usa
decide cuál (`MayhemIcon.color`, que también tiñe la textura). No metas color
dentro del archivo: un icono con dos colores propios no puede reusarse en un
estado deshabilitado, en un tooltip ni en una ficha de trofeo.

Trabajá sobre `#E6E8EF` (`Tokens.TEXT`) como neutro y verificá legibilidad
también en `#8A90A3` (`MUTED`) y `#454C60` (`DIM`).

### Movimiento

Los iconos no se animan. Lo que se mueve es la ranura que los contiene (pulso de
vida baja, parpadeo de munición baja), y eso ya está resuelto en código. Un icono
que necesita animarse para entenderse no está terminado.

---

## 2. Lo que ya existe (25)

Definidos en `MayhemIcon.Kind`. Reemplazarlos es opcional.

**Armas** — `RIFLE`, `SHOTGUN`, `SMG`, `PISTOL`. Las proporciones espejan los
viewmodels a propósito: el icono enseña la silueta del arma que vas a ver en las
manos. El rifle es el más ancho y bajo; la escopeta el de cuerpo más alto; el SMG
compacto y vertical; la pistola la más chica.

**Utilidades** — `STUN_GRENADE`, `TEMP_WALL`, `SLOW_FIELD`. `TEMP_WALL` es una
caja abierta abajo: una barrera detrás de la que te parás, no un contenedor.

**Estado** — `DASH`, `GRAPPLE`, `LOW_HEALTH`, `POWER_UP`, `HAZARD`.

**Marcos de categoría** — `FRAME_MOBILITY` (cuadrado), `FRAME_WEAPON` (diamante),
`FRAME_SURVIVABILITY` (círculo). El marco dice la categoría, el glifo de adentro
dice el sujeto.

**Glifos de modificador** — `GLYPH_SPEED`, `GLYPH_DASH`, `GLYPH_GRAPPLE`,
`GLYPH_DAMAGE`, `GLYPH_ACCURACY`, `GLYPH_FIRE_RATE`, `GLYPH_MAX_HP`,
`GLYPH_ARMOUR`, `GLYPH_REGEN`.

**Economía** — `CURRENCY`.

> **Ojo:** de los 25, solo se muestran hoy 10 — `GRAPPLE`, `STUN_GRENADE`,
> `TEMP_WALL`, `SLOW_FIELD`, `POWER_UP`, `HAZARD`, `CURRENCY` y los tres
> `FRAME_*`. Los otros 15 (las cuatro armas, `DASH`, `LOW_HEALTH` y los nueve
> `GLYPH_*`) están dibujados y no aparecen en ninguna pantalla — ver §5.2.

---

## 3. Lo que falta

Esto es el pedido. Agrupado por para qué sirve, con el lugar exacto donde entra.

### 3.1 Trofeos — 12 iconos · **prioridad alta**

Se ganan al terminar una run y se guardan con ella. Hoy se muestran como fichas
de texto en la tabla de mejores runs
([`leaderboard_panel.gd`](../scripts/ui/leaderboard_panel.gd), columna
`TROPHIES`), y con hasta 4 fichas por fila el texto ya está apretado. **Son los
que más ganan con un icono.**

Definidos en [`run_record.gd`](../scripts/autoload/run_record.gd).

| Id | Nombre en pantalla | Qué premia | Nota de dibujo |
| --- | --- | --- | --- |
| `champion` | CAMPEÓN | Las diez oleadas | El único que significa "terminaste". Debería ser el más rotundo del set. |
| `flawless` | INTOCABLE | Toda la run sin un golpe | Cuadrado (`PLAYER`): habla de tu integridad. |
| `untouchable` | IMPECABLE | Cinco oleadas limpias | Pariente visual del anterior, un escalón abajo. |
| `marksman` | TIRADOR | 40% de headshots | No repetir `GLYPH_ACCURACY`: eso es una estadística, esto es un logro. |
| `acrobat` | ACRÓBATA | 10 kills sin tocar el piso | |
| `spinner` | TROMPO | 3 kills girando 360° | |
| `executioner` | VERDUGO | 4 kills en 1.5s | |
| `surgeon` | CIRUJANO | 5 Healers cortados mientras curaban | Puede citar el mint de `HEAL` como forma, nunca como color. |
| `sniper` | FRANCOTIRADOR | 10 kills a +30m | |
| `tycoon` | MAGNATE | 3000 monedas en una run | Círculo (`REWARD`), pariente de `CURRENCY`. |
| `ascetic` | ASCETA | Ganar sin comprar nada | Lo contrario del anterior. El par se tiene que leer como par. |
| `blitz` | RELÁMPAGO | Ganar en menos de 8 min | |

**Restricción dura:** se dibujan a ~15–20px de alto en una fila de tabla, junto a
otros tres. A ese tamaño el trazo efectivo es ~1px. Cada trofeo tiene que
distinguirse de los otros once **por silueta**, sin leer un solo detalle
interior.

### 3.2 Bonos de kill — 12 iconos · **prioridad alta**

Aparecen durante el combate, en el feed bajo el contador de plata
([`payout_feed.gd`](../scripts/ui/payout_feed.gd)), con el texto del bono y lo
que pagó. Vida de la ficha: ~1.3s.

Definidos en [`kill_bonus_tracker.gd`](../scripts/autoload/kill_bonus_tracker.gd).

| Id | En pantalla | Condición |
| --- | --- | --- |
| `headshot` | HEADSHOT | Último golpe a la cabeza |
| `airborne` | EN EL AIRE | Sin pisar piso |
| `spin` | 360 | ≥330° girados sin frenar |
| `grapple` | EN EL GANCHO | Colgado del gancho |
| `dash` | EN EL DASH | Dentro de 0.55s del dash |
| `long_shot` | A DISTANCIA | ≥32m |
| `point_blank` | A QUEMARROPA | ≤4.5m |
| `last_round` | ÚLTIMA BALA | Cargador en cero |
| `double` | DOBLE | 2ª kill en 1.5s |
| `triple` | TRIPLE | 3ª kill en 1.5s |
| `mayhem` | MAYHEM | 4ª+ kill en 1.5s |
| `priority` | PRIORIDAD | Healer cortado curando |

**Reusar donde corresponda.** `grapple` y `dash` ya tienen glifo (`GLYPH_GRAPPLE`,
`GLYPH_DASH`) y deberían usarlo: el jugador ya aprendió esas marcas en la HUD, y
darles una segunda forma para lo mismo es enseñar dos veces.

`double` / `triple` / `mayhem` son **una escala**, no tres iconos sueltos. Tienen
que leerse como el mismo signo creciendo.

**Restricción dura:** se leen de reojo, en movimiento, mientras el jugador está
disparando. El texto ya dice qué es; el icono existe para que no haya que leerlo.

### 3.3 Mejoras de la tienda — 19 iconos · **prioridad media**

`UpgradeData` ya tiene un campo `icon: Texture2D` — **está vacío en las 19**. Las
tarjetas de la tienda hoy son texto puro.

Las 19 mejoras en [`data/upgrades/`](../data/upgrades/):

- **Movilidad** — `move_speed`, `jump_height`, `air_control`, `dash_charge`,
  `dash_cooldown`, `grapple_cooldown`, `grapple_range`, `grapple_aim_assist`
- **Arma** — `damage`, `fire_rate`, `magazine`, `reserve_ammo`, `reload_speed`,
  `recoil_control`, `stability`, `ads_speed`
- **Supervivencia** — `max_health`, `damage_reduction`, `adrenaline`

**Cómo se construyen:** marco de categoría + glifo de sujeto. El marco ya existe
(`FRAME_MOBILITY` / `FRAME_WEAPON` / `FRAME_SURVIVABILITY`) y varios glifos
también. Lo que falta son los glifos que no tienen: `air_control`,
`grapple_aim_assist`, `magazine`, `reserve_ammo`, `reload_speed`,
`recoil_control`, `stability`, `ads_speed`, `adrenaline`.

Las mejoras que apilan (hasta `Tokens.STACK_MAX` = 5) muestran el conteo aparte;
el icono no cambia con los stacks.

### 3.4 Arquetipos de enemigo — 8 iconos · **prioridad media**

No existen y hacen falta para la tabla de oleada, el feed de kills y cualquier
pantalla que resuma qué te mató. Cada uno tiene ya color y altura fijados en
`Tokens.ENEMY_*` / `Tokens.ENEMY_HEIGHT` — **la silueta del icono tiene que
coincidir con la del cuerpo en la arena**, porque eso es lo que el jugador
aprendió.

| Arquetipo | Color | Altura | Marca de silueta |
| --- | --- | --- | --- |
| `rusher` | `#FF3B54` | 1.2 | El más bajo y compacto |
| `ranger` | `#FF7A1F` | 1.9 | |
| `elite` | `#FC3A00` | 2.8 | El más alto |
| `healer` | `#B45CFF` | 2.0 | **Lleva halo** — es su marca de silueta |
| `summoner` | `#FF3BC1` | 2.2 | |
| `bomber` | `#F5E000` | 1.0 | Esfera. El único amarillo del elenco |
| `environmental` | `#5FD93A` | 2.5 | Deja charcos |
| `flyer` | `#9966F2` | 0.8 | Esfera también — **comparte forma con el Bomber**, así que la diferencia tiene que estar en otra parte |

### 3.5 Economía y estado — 6 iconos · **prioridad media**

| Necesidad | Dónde | Nota |
| --- | --- | --- |
| Moneda perdida | Feed de payout, fila `DAÑO -12` | Pariente de `CURRENCY` pero legible como pérdida. No basta con pintarlo rojo. |
| Vida ganada | Pickups, cura | `HEAL` `#8AF0C4` es solo VFX de mundo — este icono va en `PLAYER` o `REWARD`. |
| Munición | Pickups, reserva | |
| Tiempo / par | Cluster de timer | |
| Oleada | Cluster de oleada | |
| Enemigos restantes | Cluster de oleada | |

### 3.6 Navegación de menús — 11 iconos · **prioridad baja**

Los menús funcionan sin iconos y no están rotos. Esto es pulido.

**Menú principal** — Play, Create arena, Best runs, Options, Send feedback,
Credits, Quit.

**Secciones de opciones** — INPUT, VIDEO, AUDIO, ACCESSIBILITY, HUD.

### 3.7 Editor de arenas — 21 iconos · **prioridad baja**

La paleta de [`data/arena_pieces/`](../data/arena_pieces/) es hoy una lista de
nombres. Con 21 piezas, una grilla de iconos sería bastante más rápida de usar,
pero el editor es una herramienta y no parte de la run.

Piezas: `floor_1x1`, `floor_2x2`, `floor_3x3`, `wall_1x1`, `wall_2x1`,
`wall_corner`, `pillar_1x1`, `platform_2x2`, `catwalk_1x3`, `ramp_1x1`,
`ramp_2x1`, `cover_low`, `moving_platform`, `disappearing_platform`,
`bounce_pad`, `jump_link`, `zip_line`, `grapple_anchor`, `hazard_zone`,
`snare_zone`, `ammo_pickup`.

La ley de color de la arena ya los separa en tres familias y **los iconos tienen
que respetarla**: `WORLD_TRAVERSAL` (cian, corchete) para lo que se usa,
`WORLD_HAZARD` (naranja, rayas a 45°) para lo que lastima, `WORLD_PICKUP` (ámbar,
círculo) para lo que se levanta.

---

## 4. Entrega

### Lo que se recibió

57 iconos: 12 trofeos, 12 bonos, 19 mejoras, 8 arquetipos, 6 de economía. SVG
64×64 más PNG a 64, 128 y 256.

### Lo que se integró — *decisión*

**Solo los SVG.** Godot 4 los rasteriza al importar (ThorVG), así que el SVG es a
la vez fuente y textura de juego: un archivo por icono en vez de cuatro.

Verificado: importan a 256×256 con `svg/scale=4.0` y cobertura correcta — 43% de
píxeles opacos en `trophy_champion`, 11% en `bonus_spin`, 21% en
`upgrade_adrenaline`.

Los PNG quedaron afuera a propósito. Eran 1.4 MB para 171 archivos que dicen lo
mismo que los 57 SVG, y cada PNG carga además un bloque de metadatos C2PA de
~6 KB — más pesado que la imagen. Si alguna vez hace falta un PNG (una tienda,
una captura, una herramienta externa), se exporta del SVG.

### Cómo se buscan — *convención, no tabla*

[`IconSet`](../scripts/ui/icon_set.gd) resuelve por nombre:

```
res://ui/icons/<grupo>/<grupo>_<id>.svg
```

donde `<id>` es el mismo que ya usa el código — `RunRecord.CHAMPION`,
`KillBonusTracker.BONUS_SPIN`, el `id` del `.tres` de la mejora. **No hay tabla
`id → ruta`**: sería una tercera copia de esos nombres y la que se olvidaría de
actualizar.

```gdscript
IconSet.trophy(RunRecord.CHAMPION)          # Texture2D, o null
IconSet.make(IconSet.BONUS, &"spin", Tokens.REWARD, 18.0)   # MayhemIcon listo
```

**Devolver `null` es parte del contrato, no una falla.** Un id sin archivo cae en
el texto que la pantalla ya mostraba. Eso es lo que permite agregar un bono nuevo
sin esperar a que exista su icono — y lo que hace que §3.6 y §3.7 no bloqueen
nada.

### Agregar un icono nuevo

Dejar el SVG en `ui/icons/<grupo>/` con el nombre de la convención. Nada más.
Los tests de [`test_icon_set.gd`](../tests/unit/test_icon_set.gd) recorren los
`.tres` de disco, así que una mejora o un enemigo nuevo **sin** icono hace
fallar la suite.

## 5. Dos cosas del lado del código

Ninguna es de dibujo, pero las dos afectan al pedido.

### 5.1 Los colores de categoría — *resuelto*

Había dos tablas y no coincidían. `Tokens.CATEGORY_COLOR` decía
`mobility → PLAYER · weapon → ENEMY · survivability → REWARD`, y
[`bonus_list.gd`](../scripts/ui/bonus_list.gd) tenía su propia copia con
`weapon → REWARD · survivability → HEAL` — y `HEAL` está documentado en
`theme_tokens.gd` como **"healing VFX only, never UI"**, o sea que el panel de
bonos estaba pintando una categoría con un color que la propia ley prohíbe en
UI.

Resuelto a favor de `Tokens`, que es la fuente declarada: `bonus_list.gd` ahora
lee de ahí en vez de tener su propia lista. **Los 19 iconos de mejora se pintan
con estos tres:**

| Categoría | Color | Marco |
| --- | --- | --- |
| Movilidad | `PLAYER` `#35E0D4` | Cuadrado |
| Arma | `ENEMY` `#FF3B54` | Diamante |
| Supervivencia | `REWARD` `#FFB020` | Círculo |

### 5.2 Iconos procedurales que nadie muestra — *parcialmente resuelto*

Eran quince: las cuatro armas, `DASH`, `LOW_HEALTH` y los nueve `GLYPH_*`.

Las **cuatro armas ya se muestran**: la tarjeta de tienda de un arma las usa, y
como espejan el viewmodel, el icono enseña la silueta del arma antes de
comprarla.

Quedan once sin consumidor. Los nueve `GLYPH_*` fueron reemplazados de hecho por
los 19 iconos de mejora, que son más específicos — un glifo genérico de "daño"
dice menos que el icono de `damage` — así que **probablemente haya que borrarlos**
en vez de cablearlos. `DASH` y `LOW_HEALTH` tienen lugar obvio en el cluster de
vitales y entran en el pase de layout.

---

## 6. Lo que falta

Entregado: §3.1 a §3.5 (57 iconos).

Pendiente, y sin bloquear nada porque ambos caen en texto:

- **§3.6 Menús** (11) — los menús funcionan sin iconos. Pulido.
- **§3.7 Editor de arenas** (21) — con 21 piezas una grilla de iconos sería más
  rápida de usar, pero el editor es una herramienta, no parte de la run.

---

## 7. Dónde quedó cableado cada grupo

| Grupo | Dónde se ve | Tamaño | Color |
| --- | --- | --- | --- |
| **Trofeos** | Columna `TROPHIES` de la tabla de mejores runs | 22px | `REWARD` |
| **Bonos** | Feed de payout, durante el combate | 18px | `REWARD` |
| **Mejoras** | Cabecera de la tarjeta de tienda, y filas del panel de bonos | 28px / 14px | El de su categoría |
| **`currency_lost`** | Fila `DAÑO` del feed de payout | 18px | `ENEMY` |
| **Arquetipos** | *Sin consumidor todavía* | — | — |
| **Resto de economía** | *Sin consumidor todavía* | — | — |

Los iconos de arquetipo y los cinco de economía que quedan (`health_gain`,
`ammo`, `time`, `wave`, `enemies_left`) están importados y disponibles por
`IconSet`, pero no hay pantalla que los pida: los clusters de la HUD que les
corresponden se tocan en el pase de layout, y meterlos antes sería decidir la
distribución dos veces.

Las armas de la tarjeta de tienda usan la geometría procedural de `MayhemIcon`
(`RIFLE` / `SHOTGUN` / `SMG` / `PISTOL`), que espeja el viewmodel — así el icono
enseña la silueta del arma antes de comprarla. Eso saca 4 de los 15 iconos
dibujados que nadie mostraba (§5.2).
