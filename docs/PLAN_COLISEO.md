---
tags: [mayhem, plan, arena, venue, crowd]
---

# MAYHEM — El coliseo

Rama: `feat/crowd-drops`. Continúa lo construido en
[PLAN_CROWD_DROPS.md](PLAN_CROWD_DROPS.md).

El público ya existe, ya tira gadgets y ya reacciona. Lo que falta es el lugar:
hoy es un anillo de bloques greybox y un cielo gris, y por eso nada de lo que
está construido se ve. Este plan es el venue — la forma, el límite, el techo y
el cielo — y las cuatro decisiones ya están tomadas:

| Pregunta | Decisión |
|---|---|
| Geometría | **Generada por código.** Sin assets, a la medida de cada arena. |
| Planta | **Gradas ovaladas, arena rectangular adentro.** |
| El límite | **Pared de energía vertical + techo de estadio real.** |
| El cielo | **Noche, con skyline cyberpunk en el horizonte.** |

---

## 0. Por qué no se ve el público (medido)

`tools/measure_stands.gd`, corrido contra los modelos que usa el shell hoy:

```
SingleStand.blend   20 × 4 × 4 m    28 triángulos
  perfil de altura:  2.00 ... 4.00 ... 4.00
CornerStand.blend    6 × 2 × 6 m    24 triángulos
  perfil de altura:  2.00 ... 2.00
```

**No son gradas.** Son bloques greybox de dos escalones: un reborde a 2m y un
paredón a 4m. El sistema de filas que se construyó las reparte en diagonal sobre
la rampa de la sección — pero esa rampa no existe, así que la mitad del público
quedó flotando delante del bloque y la otra mitad enterrada adentro. Desde la
arena se ve la cara del bloque y nada más.

Esto **no se arregla afinando números**. Fitear el público a la grada era el
enfoque correcto sólo si había una grada; lo que hay es un placeholder que nunca
pretendió serlo. De ahí sale la primera decisión: si la geometría se genera, el
mismo código que hace el escalón sabe dónde está su superficie, y los asientos
salen exactos por construcción en vez de por ajuste.

## 1. `ArenaColiseum` — el venue generado

`scripts/systems/arena_coliseum.gd` + `scenes/arena/shells/coliseum_shell.tscn`,
un shell nuevo con la misma firma `setup(bounds, theme)` que los otros dos. El
tema `default` pasa a apuntarle. `ArenaTiledShell` queda donde está: sirve para
un venue chico y no cuesta nada dejarlo.

### 1.1 La planta ovalada

La arena es rectangular y las gradas van en óvalo, así que el óvalo se calcula
para **circunscribir** el rectángulo con holgura:

```
a = half.x + pit_margin        (semieje sobre X)
b = half.z + pit_margin        (semieje sobre Z)
```

y cada punto del anillo sale de `(a·cos θ, b·sin θ)`, corregido para que el
óvalo nunca se meta dentro del rectángulo de juego. **El foso queda más ancho en
las esquinas que en los lados**, y eso está bien: es lo que pasa en un coliseo de
verdad y es lo que hace que la forma se lea como óvalo y no como rectángulo
redondeado.

> Una **superelipse** (`|x/a|^n + |z/b|^n = 1`) con `n` expuesto entre 2 y 4 deja
> ir de la elipse pura al rectángulo con las esquinas comidas, en un solo número.
> Es la perilla con la que se afina la planta sin tocar código.

### 1.2 Los escalones

Cada tier (*maenianum*) es una banda de filas. Cada fila es un escalón: una
huella horizontal donde se sienta la gente, y una contrahuella vertical. Se
generan con `SurfaceTool` como un solo `ArrayMesh`:

- `segments` puntos alrededor del óvalo, `rows_per_tier` filas por tier,
  `tiers` tiers. Un anillo de quads por fila.
- Entre tier y tier, una **praecinctio**: pasillo horizontal más ancho y un
  parapeto. Es lo que quiebra la pendiente y hace que se lea como un coliseo y
  no como un cono.
- **Vomitoria**: huecos a intervalos regulares en las filas, con la boca del
  túnel oscura detrás. Cuestan un `continue` en el bucle y son la cosa que más
  dice "coliseo" por unidad de trabajo.

El acabado cyberpunk no es geometría: es material. Una línea emisiva en el borde
de cada praecinctio y en los marcos de los vomitorios, en cian de jugador y
ámbar de la casa, resuelve el look con dos materiales y sin un triángulo extra.

### 1.3 Sin colisión

Los escalones **no llevan colisionador**. El jugador no puede estar ahí — para
eso está la pared de energía — y un venue con colisión por escalón sería miles
de formas que nadie va a tocar nunca. Lo único con colisión en todo el venue es
el límite.

### 1.4 Los asientos, gratis

`_seat_rows()` deja de estimar y devuelve **la huella real de cada fila**, porque
es la misma función que la generó. `CrowdStands.populate_rows()` ya acepta
exactamente eso, así que este paso no toca al público: sólo le pasa datos que
ahora son ciertos.

La única corrección que sí necesita el público es que `populate_rows()` recorre
un **rectángulo** (`_walk_rectangle`), y las filas pasan a ser óvalos. El
recorrido tiene que salir del generador junto con la fila, en vez de que la
tribuna lo reconstruya.

## 2. El límite que se entiende

Hoy el borde es una caja invisible de 14m. Funciona y no comunica nada: chocás
con aire.

### 2.1 La pared

- **Colisión**: sigue siendo cuatro `StaticBody3D` sobre el rectángulo de la
  arena. Es exacto, es barato, y es lo que el jugador ya siente hoy. **No se
  toca la forma de la colisión** — cambia lo que se ve, no lo que se choca.
- **Lo visible**: cuatro quads con un shader de campo de fuerza.
  - Casi invisible de frente y encendida en ángulo rasante (fresnel), para que
    marque el límite sin taparte la pelea.
  - Retícula hexagonal apenas insinuada, con barrido lento.
  - **Reacciona al contacto**: una onda que se expande desde el punto donde
    golpeaste. Esto es lo que hace que el límite tenga sentido — el muro te
    contesta, y aprendés dónde está chocándolo una vez en vez de descubriéndolo
    de nuevo cada vez.
  - El impacto lo avisa el jugador (una señal, no un chequeo del shader), y el
    shader guarda los últimos N impactos en un array de uniforms.

### 2.2 La altura, y por qué cierra arriba

El gancho llega a **28m** y sube con upgrades; hay dash, bounce pads y zip
lines. Una pared abierta arriba obliga a decidir qué pasa cuando alguien la
supera, y esa decisión siempre termina siendo un teletransporte o una muerte
que el jugador no entiende.

Así que **cierra**: la pared llega hasta el techo y el techo es sólido. Nunca se
sale, y no hay ningún caso raro que explicar.

## 3. El techo

Estructura de verdad, no energía: un anillo perimetral, vigas cruzadas, y
reflectores. En el centro un **óculo** abierto, que es de donde bajan los haces
de luz sobre la arena y por donde se ve el cielo.

- Se genera con el mismo `SurfaceTool`, como cajas y cilindros: son unas pocas
  decenas de piezas.
- Colisión: **un solo plano** a la altura del techo. Igual que la pared, la
  colisión es simple aunque lo que se ve no lo sea.
- **Los haces de luz se construyeron y se sacaron.** En las referencias de
  estadio funcionan porque ahí la cámara está quieta y mirando desde afuera;
  desde adentro y en movimiento eran seis columnas claras cruzando el área de
  juego, compitiendo con lo único que el jugador tiene que estar mirando. Es la
  clase de cosa que sólo se decide jugándola.

## 4. El cielo

Dos capas, las dos baratas:

1. **Noche.** El tema arma hoy un `Environment` con `BG_COLOR` gris-azul
   (`#1E3C65`). Pasa a `BG_SKY` con un `ProceduralSkyMaterial` nocturno: horizonte
   apenas teñido por la ciudad, cenit casi negro. El `glow` ya está encendido en
   el tema, así que todo lo emisivo del venue va a florecer solo.
2. **Skyline.** Un anillo de siluetas de torres con ventanas emisivas, dibujado
   más allá de las gradas y por debajo del techo. Un MultiMesh de quads con el
   mismo truco que el público — una draw call — o directamente pintado en el
   shader del cielo si conviene que no tenga paralaje.

## 5. El orden de ataque

Cada paso es visible por sí solo, y cada uno se puede mirar antes de seguir. Ese
es el criterio del orden: después de la última entrega, tres pasos seguidos
resultaron invisibles porque el venue los tapaba.

1. **El generador del coliseo**: planta ovalada, tiers, escalones, praecinctio,
   vomitoria. Sin material fino y sin público. Es el paso grande.
2. **El público sobre las huellas reales**, con el recorrido del óvalo saliendo
   del generador. Acá se ve por primera vez si la escala del espectador funciona.
3. **El cielo de noche y el skyline.** Cambia el clima de todo lo anterior, y es
   barato.
4. **La pared de energía** con su onda al contacto.
5. **El techo, el óculo y los haces.**
6. **Los materiales cyberpunk**: bordes emisivos, marcos de vomitorio, pantallas.

> **El panel del cuenco va congelado y tenue.** El shader del proyecto sabe
> parpadear y barrer, y en una pieza de arena eso está bien porque se la mira de
> reojo. Una tribuna de treinta y cinco metros ocupa medio campo de visión todo
> el tiempo: cualquier cosa que se mueva ahí le roba la atención a la pelea. Las
> pantallas sí se mueven — están lejos, arriba, y son la única cosa del venue
> que tiene que llamar la atención.

## 6. Lo que hay que medir antes de creerlo

- **El público a distancia.** Las gradas de arriba van a estar a 60-80m del
  jugador. Una silueta de 1.75m a esa distancia es un puñado de píxeles, y puede
  que haya que agrandar al espectador por encima de lo realista para que la
  tribuna se lea llena. Es un número que sólo sale mirando.
- **Cuántos espectadores entran.** Con óvalo, tiers y filas, el total sube
  bastante respecto del anillo actual. Es una draw call igual, pero el buffer de
  instancias y el vertex shader no son gratis: hay que medirlo con el profiler
  que ya existe (`tools/profile_elite_wave.gd` es el molde).
- **Que la pared no tape.** Un campo de fuerza que se ve demasiado convierte cada
  pelea contra el borde en pelear contra un vidrio sucio.

## 7. Lo que este plan NO hace

- No cambia la forma del área de juego: sigue siendo el rectángulo del editor de
  arenas. El óvalo es de las gradas.
- No toca el navmesh, el spawn de enemigos ni el editor.
- No cambia dónde caen los gadgets ni cómo se levantan.
- No reemplaza `ArenaTiledShell`: queda disponible.
- No modela nada en Blender. Si mañana hay modelos de grada de verdad, entran
  reemplazando la generación del §1.2 y el resto del venue no se entera.
