---
tags: [mayhem, diseño, brief]
estado: guia
actualizado: 2026-10-16
---

# MAYHEM — Documento de diseño

El brief original del proyecto vivía en un `CLAUDE.md` que **nunca se versionó**.
El código lo sigue citando por número de sección (`CLAUDE.md 5.3`, `CLAUDE.md 5.5`…)
en más de cuarenta comentarios y tests. Este documento lo reconstruye con **la misma
numeración**, para que cada una de esas citas vuelva a apuntar a algo.

Cómo se reconstruyó: cada regla de abajo sale de una cita textual en el código, en
los tests o en los documentos de fase ([historial/](historial/)). Donde una sección
no tiene ninguna cita, se dice, y su contenido se escribió desde el estado actual
del juego en vez de inventar lo que decía el original.

> Si aparece el `CLAUDE.md` original, este archivo se compara contra él y se
> corrige; no al revés.

---

## 1. Visión

**Diez oleadas. Una run. Sin saves.** Shooter de arena en primera persona, de un
jugador. Una run atraviesa diez oleadas que escalan; entre oleada y oleada se
gasta lo ganado; un presentador de transmisión (el Host) narra la actuación del
jugador quiera o no. Nada se arrastra entre runs: no hay meta-progresión, ni
perfil (ver `RunRecord`, que guarda trofeos *con la run* y no en un perfil por
esta misma razón).

**Excepción, decidida el 2026-10-16:** la maestría de cada arma. Jugar con un arma
le da experiencia, y cada nivel desbloquea un attachment que se puede llevar a las
runs siguientes (`Armory`). Para no convertirse en "más fuerte cuanto más jugaste",
los attachments son de costado: cada uno da algo y cobra algo. Es lo único que se
guarda entre runs además de la tabla, los perfiles y los hints vistos.

### 1.1 Modos de juego (2026-10-09, sin cita: decisión posterior al brief)

- **ARSENAL**: se arranca con la pistola y la tienda vende las otras armas, todas
  con precio. Cambiar de arma deja atrás las mejoras de la anterior, por diseño.
- **ONE GUN**: se elige un arma antes de la run y es la de las diez oleadas; la
  tienda solo vende mejoras.

### 1.2 Todo lo que se tunea es dato

Cada arma, arquetipo, oleada, mejora, utilidad, hint y texto del Host es un
`Resource` (`.tres`) en `data/`. Rebalancear o escribir contenido nuevo no toca
una escena ni una línea de código. (Citado en `shop_catalog.gd`,
`tutorial_hint.gd`.)

## 2. Sistemas propios tempranos

Sin cita directa salvo una: la fase 0 lo menciona para justificar `ObjectPool`
como autoload. Lo que el juego construyó propio en vez de tomar de un addon:
pool de objetos, pool de audio, recoil determinista, máquina de estados de
movimiento, sistema de telegrafía.

## 3. Stack y repositorio

Una sola cita: `.gitattributes` dice que **Git LFS se configura antes del primer
commit de arte** (todos los formatos de arte y audio van por LFS). El resto, desde
el estado actual: Godot **4.7**, GDScript con tipado
estricto (`untyped_declaration` como warning), física **Jolt**, renderer
**Forward+** (D3D12 en Windows), resolución base 1920×1080 con stretch
`canvas_items`.

## 4. Arquitectura

### 4.1 Carpetas

`scripts/resources/` define clases; `data/` guarda instancias. **Nunca se
mezclan.** Componentes en `scripts/components/`, objetos del mundo en
`scripts/systems/`, actores finos en `scripts/actors/`, IA en `scripts/ai/`.
Desvío anotado en la fase 3: los enemigos son **una** escena, no una por
arquetipo.

### 4.2 Autoloads y EventBus

`EventBus` es sólo señales: cero lógica, cero estado. Ningún sistema toca las
tripas de otro a través de un límite; se habla por señal. El brief original
listaba nueve autoloads; hoy son veinte (ver
[02 Autoloads](Mayhem/02%20Autoloads.md)).

### 4.4 Separación padre/hijo

El actor raíz decide *qué* quiere hacer; el componente decide *cómo*. Ejemplo
citado: `MovementComponent` es dueño de toda la física del jugador, salto
incluido, y `player.gd` queda en mirada y armas.

### 4.5 Mapa de input

Todas las acciones se declaran antes de que exista código que las lea. Hoy: 21
acciones (la fase 0 arrancó con 22; ver `[input]` en `project.godot`), con
bindings de teclado y de gamepad; 15 se re-bindean desde opciones.

## 5. Pilares de diseño

**El color nunca es la única señal** (regla 5 del brief visual): cada color de
acento tiene una forma compañera. Ver
[09 Design Tokens and Color Law](Mayhem/09%20Design%20Tokens%20and%20Color%20Law.md).

### 5.1 Gunplay y recursos

- La **pistola es el arma inicial**: de respaldo, con reserva generosa.
- La reserva limitada es **presión de diseño**: obliga a ir a buscar munición, y
  la munición está donde cuesta ir.
- Las utilidades se llevan en cantidad limitada, cada una con su cooldown, y se
  tiran en un arco predecible para poder apuntarlas.

### 5.2 La movilidad es el pilar

- **El momentum es un recurso que el jugador construye y conserva.** Nada lo
  recorta "por justicia": los enemigos saben siempre dónde está el jugador, así
  que la velocidad no rompe nada.
- Slide que conserva y encadena, bhop intencional, dash con cargas, gancho.
- **Un enganche de geometría que mata el momentum es un bug por decreto**
  (de ahí el mantle automático).
- Nada que congele al jugador: el frasco de atrapado cobra movilidad sin
  inmovilizar.

### 5.3 Enemigos

- **Siempre saben dónde está el jugador.** Los árboles de comportamiento
  describen el enfrentamiento, no la búsqueda.
- **Telegrafiar es obligatorio** y escala con el daño. Daño sin aviso es la
  única regla que no se rompe.
- **Cada impacto tiene reacción visible** (flash, knockback, stagger): es un
  requisito de sensación de disparo, no de IA.
- **La silueta se lee de un vistazo**; el color confirma, no identifica.
- **Las puertas de spawn avisan antes** de que salga algo, para que el jugador
  se pueda reposicionar.

### 5.4 Arena

Sin cita en el código. Estado actual: arena modular sobre grilla de celdas de
4×4×3 m, tamaño fijo 32×8×32 celdas, armada con el editor de arenas; venue de
coliseo nocturno con público, pared de energía y techo. Ver
[13 Arena, Venue and Crowd](Mayhem/13%20Arena%2C%20Venue%20and%20Crowd.md).

### 5.5 Oleadas, economía y tienda

- **10 oleadas, una elite cada 5** (la 5 y la 10).
- **La tienda entre oleadas dura ~20-30 s y se puede saltear**: cobrar el bono
  de velocidad saliendo rápido es una decisión real.
- **Se premia la velocidad, no sólo completar.**
- **El desglose de ganancias se muestra explícito** (kills / completar /
  velocidad / sin daño): esa legibilidad es lo que enseña la economía.
- **Nada se arrastra entre runs** (salvo la maestría de armas, ver §1): morir
  recarga la escena, no deshace estado.
- Los power-ups temporales muestran su cuenta regresiva.

Agregado el 2026-10-09 (sin cita, decisiones posteriores al brief):

- **El puntaje es kills + estilo + oleadas.** Nunca tiempo total ni plata en mano:
  morir solo corta lo que se iba a seguir sumando, y comprar no baja el puntaje.
  La velocidad se sigue premiando, por la plata (bono de velocidad de cada ola).
- **La tabla es por arena.** Cada fila guarda su modo.
- **Curación**: solo por la mejora de regeneración (fuera de combate) y por el
  botiquín que tira el público. Ninguna fuente gratis.
- **Mejoras raras**: agregan una regla (deslizar recarga, el dash atropella...),
  siguen siendo solo StatModifiers sobre stats de base neutra. Como mucho una
  por visita, desde la ola 2.
- **Rating de la transmisión**: sube con kills con estilo, amplificado por la
  velocidad del jugador y el ritmo de kills; baja con el tiempo y con cada kill
  plana. Multiplica el estilo (plata y puntaje) y acelera los regalos del público.
- **Reglas de transmisión**: desde la ola 3 el Host sortea una regla por oleada;
  las olas elite van sin regla.
- **Tutorial de arranque**: la primera oleada espera a que termine; se saltea con
  una tecla o desde la pausa, y no vuelve a aparecer salvo que se resetee.

Agregado el 2026-10-16 (sin cita, decisiones posteriores al brief):

- **Las reglas se eligen.** En la tienda el Host ofrece dos reglas para la oleada
  que viene y el jugador elige una. Una regla ahora puede tocar también a los
  enemigos (vida, velocidad, daño, marcados con recompensa) y a la arena (cada
  kill deja un charco).
- **Contratos**: a veces el Host ofrece además una restricción opcional (sin dash,
  sin gancho, cargadores cortos...) que paga plata si se limpia la oleada con
  ella. Firmarla es una apuesta que el jugador elige; las olas elite también
  pueden traer contrato, porque no cambian la oleada.
- **El rating tiene consecuencias**: llegar arriba paga (una vez por oleada) y
  hace que el público regale; quedarse en el piso demasiado tiempo, desde la ola 3,
  hace que el patrocinador se vaya y el público deje de regalar hasta que el
  rating suba.
- **Pedidos del público**: desde la ola 2 la tribuna pide algo concreto ("un 360",
  "tres en el aire") con tiempo límite; cumplirlo paga rating, plata y un regalo.
- **Mejoras raras por arma**: dos por arma, que agregan una regla al tiro
  (atraviesa, salpica, empuja, slug). Solo se ofrecen con esa arma en la mano.
- **Una run tiene semilla**: la tienda, las reglas, los contratos, los pedidos,
  los regalos y la dispersión salen de ella. Un código compartido vuelve a jugar
  la misma run (no la misma pelea: la IA y la física no son deterministas).

## 6. Audio

El audio lleva "más o menos la mitad" de la información. **Cada arquetipo se
identifica sólo por el sonido.** Todo pasa por `AudioPool`, con el árbol de buses
`Master > SFX > {Weapons, Impacts, Enemies, World}, Music, VO, UI`.

## 7. Fases y criterios de salida

| Fase | Criterio de salida |
|---|---|
| 0 | Todo lo que una feature necesita para existir, sin gameplay |
| 1 | Disparar a una pared y a un muñeco se siente bien, con cero enemigos |
| 2 | Recorrer la arena es divertido sin combate |
| 3 | 10 oleadas jugables de punta a punta, victoria y derrota funcionan |
| 4 | Una run completa tiene decisiones de compra con peso; primer pase de balance |
| 5 | Identidad visual (brief de diseño + specs) |

Detalle de cada fase en [historial/](historial/).

## 8. (sin cita)

No hay ninguna referencia a la sección 8 en el repo.

## 9. Prioridades de testing

Lógica pura, no render. En orden: agregación de `StatModifier` → economía →
daño → recoil → oleadas (incluidos los bordes: enemigo que muere por un hazard,
invocados que sobreviven a su invocador) → munición. La economía va segunda
porque si se rompe, la tienda deja de importar en silencio. Ver
[TESTING.md](TESTING.md).

## 10. Performance

**Sostener 60 FPS con una oleada elite completa en pantalla.** Medido con
`tools/profile_elite_wave.gd`, con render real (nunca `--headless`).

## 11. Addons

No se agrega un addon sin proponerlo antes con una justificación. Ver
[ADDONS.md](ADDONS.md).
