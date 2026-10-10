---
tags: [mayhem, handoff, arte, modelos, concept]
estado: activo
actualizado: 2026-10-09
---

# Handoff — Dirección de arte: brazos, arena, interactuables y venue

Pedido para una IA de imagen (Claude Design u otra) que arme los **boards de
concepto** a seguir para modelar todo lo que hoy es primitiva. **Armas y
enemigos quedan afuera**: ese diseño ya existe.

Hoy, fuera de armas y cinco enemigos, el juego es greybox: cajas, cilindros y
esferas con un filete emisivo. Funciona y se lee; no tiene cara. Estos boards
son la referencia para darle una, sin romper lo que hace que el juego se lea.

---

## 0. Cómo usar este documento

1. **Pegá siempre el §1 (brief global) primero**, en la misma conversación, y
   después **un board a la vez** (§2 a §8). Cada board es una imagen o una
   lámina; pedir todo junto da una sola imagen genérica.
2. **Adjuntá referencias del juego**: capturas de dos o tres enemigos ya
   modelados (Rusher, Bomber, Healer) y de un arma en primera persona, y una
   captura del coliseo de noche (`tools/capture_menu.tscn` da una del fondo del
   menú). Sin eso, la IA inventa un estilo y los boards no van a combinar con lo
   que ya está hecho.
3. Orden recomendado: **§2 (style frame) → §3 (brazos) → §4 (kit modular) → §5
   (interactuables)**. El resto puede esperar: el venue ya está generado por
   código y se ve.
4. Lo que vuelve de cada board se revisa contra la **tabla de control** de ese
   board antes de modelar. Si un board viola la ley de color, no se modela así:
   se pide de nuevo.

---

## 1. Brief global — pegar tal cual

```text
You are the concept artist for MAYHEM, a single-player first-person arena
shooter. I need concept boards (orthographic turnarounds + 3/4 views + one
in-context shot) for 3D models that will be built in Blender and used in
Godot 4 in real time. Read this whole brief before drawing anything.

THE FANTASY
A televised bloodsport at night. The player is a contestant thrown into a
cyberpunk coliseum for ten escalating waves of robots, live on air. A dry,
sardonic game-show host ("the house") narrates; a packed crowd in the stands
cheers and throws gadgets down to the arena floor. It is a SPORT and a SHOW,
not a war: think stadium infrastructure, broadcast equipment, sponsor-free
corporate hardware, floodlit concrete and steel - never ruins, never gore,
never military camo.

STYLE
- Stylized low-to-mid poly hard-surface, clean bevels, readable silhouettes.
  Match the attached reference images of the existing robots and weapons.
- Big shapes first, small detail second. Everything is seen at speed: the
  player slides, dashes, bunnyhops and grapples at 7-20 m/s.
- Mostly dark neutral materials (charcoal concrete, gunmetal, black rubber)
  so that the few accent colors pop. Rough/matte surfaces, a little wear on
  edges, no grime layers.
- Night scene: cool moonlit ambient, the arena lit by its own emissive lines
  and by the city skyline glow. Emissive light is a signal, not decoration.

THE COLOR LAW - NON-NEGOTIABLE
Interactive things use exactly one of four meanings, each with a color AND a
shape (the game must read correctly for colorblind players):
- CYAN  #35E0D4, SQUARE / bracket shapes = "you can use this" (traversal:
  jump pads, grapple anchors, zip lines, moving platforms, the player's own
  gear).
- ORANGE #FC3A00, TRIANGLE / 45-degree hazard stripes = "this will hurt you"
  (traps, warnings). Acid pools are acid green #C6FF3D as a SUBSTANCE, framed
  by orange hazard markings.
- AMBER  #FFB020, CIRCLE shapes = "take this" (pickups, ammo, crowd gifts,
  money). Amber also belongs to the host's broadcast branding - nothing else
  may be amber.
- MAGENTA #FF3BC1 = "enemies come from here" (spawn doors only).
Also reserved: crimson #FF3B54 = enemy threat; mint #8AF0C4 = healing VFX only.
Never use any of these colors on a surface that does not carry that meaning.
Non-interactive surfaces stay in the neutral ramp:
#07080B #14161C #1E212B #2C3140 #454C60 #8A90A3 #E6E8EF.
Glow covers a small share of any object (target under 10% of its surface).

SCALE
- The arena is a grid of 4 m x 4 m cells, 3 m per height level, 32 x 32 cells.
- The player is 1.8 m tall. Enemies range from 0.8 m (drone) to 2.8 m.
- Every walkable surface must show its edge from 30 m away at night (a thin
  emissive edge line along its top border is the established solution).

DO NOT
- No text, logos, numbers or real brands on any surface.
- No human faces or realistic human bodies (the crowd is silhouettes).
- No blood, no gore, no skulls.
- No accent color without its meaning (see the color law).
- No organic clutter (vegetation, trash piles, debris) on walkable surfaces:
  geometry snags that stop momentum are bugs in this game.
```

---

## 2. Board 1 — Style frame (la referencia de todo lo demás)

**Para qué:** fijar el look antes de diseñar piezas sueltas. Es la imagen
contra la que se comparan todos los otros boards.

```text
BOARD 1 - STYLE FRAME. One wide key-art image, first-person view from inside
the arena floor at night, 16:9. Foreground: the player's gloved forearms
holding a rifle (use the attached weapon reference), cyan accents on the
gloves. Midground: modular concrete-and-steel platforms at two heights with
thin cyan emissive edges, a cyan jump pad, an amber ammo crate glowing
softly, an acid-green pool framed by orange hazard stripes. Background: an
oval coliseum with tiered stands full of grey silhouette spectators (some
holding up phone lights), a vertical translucent energy wall around the
arena floor rippling where it was touched, a stadium roof ring with an open
oculus to the night sky, and a cyberpunk city skyline beyond the stands.
Two or three of the attached robot enemies rushing in. Mood: live sports
broadcast at night, tense, clean, readable.
```

**Tabla de control**

| Chequeo | Debe |
|---|---|
| Colores | Ningún acento fuera de su significado |
| Lectura | Los bordes de las plataformas se ven; el piso no compite con los enemigos |
| Público | Siluetas grises, nada ámbar |

---

## 3. Board 2 — Brazos del jugador (viewmodel)

**Hoy:** dos cilindros y una caja por brazo
(`scripts/components/viewmodel_arms.gd`): manga `#262B36`, guante `#121214`.

**Qué tiene que resolver:**

- **Quién es el jugador**: un concursante. Equipo de deporte extremo con
  protecciones, no un soldado. Tiene que leerse "propio" → acentos cian.
- **Sólo se ve del antebrazo para adelante.** Los hombros nacen fuera de cuadro,
  abajo y atrás. Todo el diseño interesante va del codo a la punta de los dedos.
- **Agarre de cuatro armas**: pistola (las dos manos juntas: el arma mide menos
  de 32 cm), rifle, SMG y escopeta (mano derecha en la empuñadura, izquierda
  bajo el guardamanos). Las manos se posicionan midiendo cada arma, así que el
  modelo necesita huesos de mano estándar.
- **La recarga es un giro completo del arma**: las manos la sueltan y la
  esperan. Hace falta una pose de "manos abiertas esperando".
- **El gancho sale de algún lado.** Hoy no tiene origen visible. Propuesta: un
  **lanzador de gancho en la muñeca izquierda** — el único objeto diegético que
  el jugador mira toda la run.
- **Opcional, a evaluar:** un indicador en la muñeca con las cargas de dash
  (hasta 3 pips cian, forma cuadrada). La HUD ya las muestra; sólo vale si suma
  sin competir.

```text
BOARD 2 - PLAYER ARMS (first-person viewmodel). The contestant's forearms
and hands, extreme-sport protective gear rather than military: segmented
armored sleeves over a dark technical fabric, padded gloves with hard
knuckle plates, cyan #35E0D4 accents in small square/bracket shapes only.
Left wrist carries a compact grapple launcher (a cable spool and a hook
nose pointing forward along the forearm). Show:
(a) orthographic front/side/top of one forearm + glove, elbow to fingertips;
(b) four first-person framings: holding a pistol with both hands close
together; holding a rifle (right hand on the grip, left hand under the
handguard); holding an SMG; holding a pump shotgun;
(c) a "hands open, waiting" pose used while the weapon spins during reload;
(d) a close-up of the wrist grapple launcher firing, cable in cyan.
Only forearms are ever visible - nothing above the elbow matters.
Neutral palette #14161C / #2C3140 / #454C60, cyan glow under 10% of surface.
```

**Tabla de control**

| Chequeo | Debe |
|---|---|
| Encuadre | Funciona sólo con el antebrazo visible |
| Color | Cian únicamente en acentos cuadrados; nada ámbar ni rojo |
| Pistola | Las dos manos caben juntas en un arma corta |
| Gancho | El lanzador apunta en la dirección de la mirada |

**Para modelar después:** un solo mesh con rig de brazo + mano estándar,
~5-8k triángulos los dos brazos, PBR, emisión en textura aparte.

---

## 4. Board 3 — Kit modular de la arena

**Hoy:** 21 piezas en `data/arena_pieces/`, todas cajas generadas desde la
huella. Cada `.tres` ya tiene un campo `scene` esperando el modelo.

| Pieza | Medida (m) | Notas |
|---|---|---|
| `floor_1x1` / `2x2` / `3x3` | 4×4 / 8×8 / 12×12, losa de 0,75 | El piso de toda la arena; tiene que tilear sin costuras |
| `platform_2x2` | 8×8, losa de 0,75 | Elevada (nivel 1+). Más clara y menos rugosa que el piso |
| `catwalk_1x3` | 2,4 de ancho × 12, 0,6 de espesor | Pasarela elevada |
| `ramp_1x1` / `ramp_2x1` | 4 u 8 de largo | Conecta dos niveles (3 m de desnivel) |
| `wall_1x1` / `wall_2x1` | 4 u 8 de ancho × 3 de alto × 1 | Bloquea paso y visión |
| `wall_corner` | 4×4 en L, 3 de alto | |
| `pillar_1x1` | 1,6×1,6×3 | |
| `cover_low` | 4×4, 1,2 de alto | Cobertura baja: se dispara por encima agachado |

**Reglas que el modelo no puede romper:**

- **Borde emisivo en todo lo caminable.** Hoy es un filete cian-celeste
  (`edge_color` ≈ `#40D9FF`) que el glow del entorno recoge; es lo que hizo
  legibles las plataformas de noche. El modelo lo integra (una línea en el
  canto superior), no lo saca.
- **Elevado se distingue del piso**: más claro y algo más brillante.
- **Nada que enganche**: sin bordes salientes ni tornillería en relieve a la
  altura del pecho o de los pies sobre superficies transitables (el mantle y el
  slide dependen de geometría limpia).
- **Dos materiales de superficie existen**: `concrete` y `metal`
  (`data/surfaces/`), con impacto y sonido propios. El kit debería usar los dos
  para que la superficie diga algo.
- **Encastre en grilla**: cada pieza ocupa celdas exactas; el pivot va en el
  **piso de la celda de origen, centrado en planta** (la convención de
  `addons/mayhem_tools/README.md` §Convención de celdas).

```text
BOARD 3 - MODULAR ARENA KIT. A modular kit for a floodlit night arena,
stadium infrastructure in charcoal concrete and gunmetal steel. Grid: 4 m
cells, 3 m per level. Show each piece in 3/4 view with its dimensions
written beside it (dimension labels are the ONLY text allowed), plus one
in-context shot of several pieces assembled at two heights with a 1.8 m
figure for scale:
floor tiles 4x4 / 8x8 / 12x12 m (0.75 m slab, must tile seamlessly);
raised platform 8x8 m (lighter, slightly glossier than the floor);
catwalk 2.4 m wide x 12 m long; ramps climbing one 3 m level over 4 m and
over 8 m; walls 4 m and 8 m wide x 3 m tall x 1 m thick; an L corner wall;
a 1.6 m square pillar; a low cover block 4x4 m x 1.2 m tall.
Every walkable top edge carries a thin cyan emissive line (#40D9FF).
Mix two surface materials across the kit: poured concrete panels and steel
deck plating. No protruding bolts or ledges on walkable surfaces. No text.
```

**Tabla de control**

| Chequeo | Debe |
|---|---|
| Borde | Todo lo caminable tiene su línea emisiva |
| Piso vs elevado | Se distinguen sin mirar dos veces |
| Snags | Ninguna saliente en superficies transitables |
| Color | Sólo neutros + la línea cian |

---

## 5. Board 4 — Interactuables (la ley de color en objetos)

**Hoy:** escenas en `scenes/arena/`, primitivas con shader. Los estados ya los
maneja `TelegraphComponent` (reposo → aviso → activo); el modelo tiene que
**dejar dónde mostrarlos** (una superficie o línea que cambie de color/intensidad).

| Objeto | Significado | Comportamiento que el diseño tiene que contar |
|---|---|---|
| **Bounce pad** | Cian / cuadrado | Lanza ~8 m hacia arriba. Tope 6 por arena. ⚠ Hoy su cuerpo es **verde**: el modelo nuevo lo corrige a cian |
| **Grapple anchor** | Cian / cuadrado | Siempre a 6 m o más de altura. Se apunta desde 28 m: silueta clara contra el cielo y las gradas |
| **Zip line** | Cian | Dos postes y un cable; se recorre a 16 m/s |
| **Jump link** | Cian | Marca un salto entre dos puntos que los enemigos también usan |
| **Moving platform** | Cian + recorrido | Plataforma de 3,8×3,8 m que va y viene; tiene que mostrar hacia dónde va |
| **Blinking platform** | Cian → aviso | Al pisarla avisa 1,5 s parpadeando, desaparece y deja un contorno gris punteado |
| **Hazard pool** | Ácido `#C6FF3D` + marco naranja / triángulo | Charco de ácido; daña sólo a quien está parado en su piso |
| **Snare field** | Naranja / triángulo | Campo que ralentiza; no inmoviliza |
| **Ammo crate** | Ámbar / círculo | Recarga munición; se escucha a 26 m. Tope 16 |
| **Spawn door** | Magenta | Portal en el borde de la arena; se enciende 1,2 s antes de que salga algo. Pasa un enemigo de 2,8 m. ⚠ Hoy su luz es naranja: el modelo nuevo la pone en magenta |

```text
BOARD 4 - INTERACTIVE ARENA ELEMENTS. Ten objects for the night arena, each
shown in 3/4 view in three states side by side: IDLE, WARNING, ACTIVE.
Strictly apply the color law (color + shape):
CYAN #35E0D4 + square shapes: a jump pad (launches the player 8 m up), a
grapple anchor (mounted high, readable silhouette against the sky), a zip
line (two posts + cable), a jump-link marker pair, a 3.8 m moving platform
that shows its travel direction, a blinking platform (warning = fast blink,
then gone, leaving a dashed grey outline).
ORANGE #FC3A00 + triangles / 45-degree stripes: the frame and warning
markings of an acid pool whose liquid is acid green #C6FF3D; a snare field
emitter that slows (does not trap).
AMBER #FFB020 + circles: an ammo crate with a soft glow.
MAGENTA #FF3BC1: a spawn door - a portal frame at the arena edge, large
enough for a 2.8 m robot, that lights up before enemies come through.
Neutral stadium hardware everywhere else. No text.
```

**Tabla de control**

| Chequeo | Debe |
|---|---|
| Significado | Cada objeto usa un solo color de la ley, con su forma |
| Estados | Los tres estados se distinguen también sin color (forma, ritmo, intensidad) |
| Ámbar | Sólo la caja de munición |
| Puerta | Magenta, nunca naranja |

---

## 6. Board 5 — Gadgets del público y utilidades

**Hoy:** el público tira tres gadgets a la arena (`CrowdDropPickup`), en arco,
desde las primeras filas; se agarran corriendo. Es la única fuente de
utilidades. Al lanzarse, cada una es lo suyo (`scenes/utilities/`).

| Gadget | En el piso (pickup) | Desplegado |
|---|---|---|
| **Granada aturdidora** | Se tiene que distinguir de lejos de los otros dos | Aturde todo en 6 m |
| **Muro temporal** | Ídem | Barrera del jugador (cian: es "suyo") |
| **Campo lento** | Ídem | Domo que ralentiza enemigos |
| **Botiquín** (`data/utilities/medkit.tres`) | Ídem | Cura al levantarlo. VFX en mint `#8AF0C4` |

```text
BOARD 5 - CROWD GIFTS AND DEPLOYED UTILITIES. Spectators throw gadgets down
into the arena in a high arc; on landing each sits on the floor glowing
AMBER #FFB020 (circle motif) until the player runs over it. Design a shared
"gift canister" language (sturdy, throwable, stadium-merch feel, no text)
with FOUR clearly different silhouettes readable from 25 m: a stun grenade,
a deployable wall, a slow-field emitter, a medical injector. Show each:
(a) in flight with a short light trail, (b) landed on the floor,
(c) deployed: stun burst; a player-made barrier wall in CYAN #35E0D4
(square motif); a translucent slow-field dome; a healing burst in mint
#8AF0C4 (healing VFX color only).
```

---

## 7. Board 6 — Venue (material y detalle, no forma)

La forma del coliseo **ya está hecha y no se modela**: es geometría generada
(`ArenaColiseum`, `ArenaRoof`, `CitySkyline`, `EnergyWall`). Lo que este board
aporta es **material, trims y props** para vestirla.

- **Coliseo**: planta ovalada (superelipse), foso de 8 m, muro podio de 6 m, tres
  anillos de 8 filas. Material actual: un shader de paneles.
- **Pared de energía**: vertical, translúcida, ondas desde donde se la toca.
- **Techo**: anillo estructural con vigas y óculo abierto al cielo.
- **Ciudad**: torres de cajas con ventanas por shader, a 90 m o más.
- **Público**: siluetas grises en impostores; celulares encendidos cuando se
  entusiasma. **Nunca ámbar.**
- **Pendientes del brief visual original**: jumbotrons y la marca del Host
  (anillo cruzado ámbar) como señalética del estadio.

```text
BOARD 6 - VENUE DRESSING. The coliseum's shape already exists (oval
superellipse stands, 6 m podium wall, three tiers of eight rows, roof ring
with an open oculus, vertical energy wall around the arena floor, city
skyline 90 m beyond). Design the DRESSING, not the shape: (a) a trim sheet
of stadium materials - concrete step edges, seat rows, steel railings,
podium wall panels with service hatches, roof truss beams; (b) the energy
wall's look at rest and when rippling from a touch; (c) two jumbotron
screens hanging under the roof ring; (d) the host's broadcast mark - a
crossed ring in amber #FFB020 - used as stadium signage and a floor decal at
the center of the arena; (e) broadcast camera rigs on cables. Crowd stays
grey silhouettes with phone lights. No text, no real brands.
```

---

## 8. Board 7 — Efectos (opcional)

Para después de los modelos. Impactos por superficie (concreto, metal, robot),
trazadora, fogonazo, estelas de dash y slide, explosión del Bomber con humo
residual, muerte de enemigo por disolución y aparición en la puerta. Todo en la
ley de color: cian lo del jugador, carmesí `#FF3B54` lo que pega al jugador.

```text
BOARD 7 - VFX SHEET. Stylized real-time effects for the same night arena:
bullet impacts on concrete, steel and robot armor (sparks, dust, decal);
player tracer and muzzle flash; cyan dash streak and slide sparks; a
robot's self-destruct explosion as a sphere of fire with lingering smoke;
an enemy dissolving on death in its own body color; an enemy materializing
inside a magenta spawn portal. Show each as a 4-6 frame flipbook strip.
```

---

## 9. Lo que vuelve y cómo entra al juego

| Board | Entra por | Dónde |
|---|---|---|
| Brazos | Reemplaza la geometría de `ViewmodelArms` | `scripts/components/viewmodel_arms.gd`, `scenes/player/viewmodel_rig.tscn` |
| Kit modular | Campo `scene` de cada `PieceDefinition` | `data/arena_pieces/*.tres` — ver [PLAN_MEJORAS §4.2](../planes/PLAN_MEJORAS.md) antes de integrar: el camino de carga actual crea un nodo por celda |
| Interactuables | La malla de cada escena; el `TelegraphComponent` se queda | `scenes/arena/*.tscn` |
| Gadgets | `CrowdDropPickup` y las tres escenas de utilidad | `scenes/arena/crowd_drop_pickup.tscn`, `scenes/utilities/` |
| Venue | Materiales de los shells generados | `scripts/systems/arena_coliseum.gd`, `arena_roof.gd`, `energy_wall.gd` |

Reglas de import ya establecidas en
[11 Asset Pipeline](../Mayhem/11%20Asset%20Pipeline.md): pivot en el centro de
la forma para enemigos, en el piso de la celda (centrado en planta) para piezas;
escala real en metros; `.blend1` no se versiona.
