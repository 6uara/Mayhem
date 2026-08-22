---
tags: [mayhem, enemies, ai]
---

# Enemies and AI

## One scene, seven archetypes

`scenes/enemies/enemy.tscn` + `scripts/actors/enemy.gd` (~1275 lines, the largest
script in the codebase by a wide margin) is shared by every archetype. `EnemyData`
(`scripts/resources/enemy_data.gd`) supplies everything that makes a Rusher a
Rusher: silhouette, stats, behavior tree, audio. `Enemy` itself is architecture-
agnostic — it reads `data.*` and never branches on archetype by name.

`Archetype` enum: `RUSHER, RANGER, ELITE, HEALER, SUMMONER, BOMBER, ENVIRONMENTAL`.

`EnemyData` field groups: **Stats** (health/speed/damage/range/cooldown/mass,
`stagger_resistance` — 0 = staggered by every hit, 1 = immovable, elites sit
high), **Movement** (see below), **Attack** (`attack_windup` — telegraphing is
mandatory, `attack_cooldown_jitter` and the `Leap` and `Fuse` subgroups — see
[[#Attack timing is deliberately desynchronised]], [[#The leap]] and
[[#The fuse]], `projectile_scene` for ranged archetypes, `preferred_distance`),
**Approach** (`approach_bearing_degrees`/`_weight`/`_mirrors` — see
[[#Where each archetype comes from]]),
**Support** (Healer's `heal_amount`/`heal_radius`, Summoner's `summon_data`/
`summon_count`/`summon_interval`), **Presentation** (`mesh`, `body_color`,
`has_halo`/`has_tether` — Healer-only, since Ranger and Healer share body
proportions and the halo is what separates their silhouettes at range),
**Audio**, **Economy** (`reward_currency`).

Data instances: `data/enemies/{rusher,ranger,elite,healer,summoner,bomber,environmental}.tres`.
Behavior trees: `scenes/enemies/ai/tree_{archetype}.tscn`.

`EnemyData.mesh` is the grey-box silhouette and is drawn centred on the body
capsule (`collision_height * 0.5`), the same place `_resize_capsule` puts the
shapes and the same pivot `tools/bake_enemy_meshes.gd` bakes into a real model.
It used to be pinned at `y = 0.9` by the scene — half of the 1.8m capsule the
scene was authored with, and therefore right for no archetype that actually
exists. The Ranger got away with it, the Elite and the Summoner sat low, and
anything shorter than 1.8m floated. Archetypes with a `model_scene` never
noticed either way, since the primitive is hidden under a model.

## Movement fields — a contract, not taste

```gdscript
@export var max_auto_step: float = 0.6   # must be >= the navmesh bake's agent_max_climb
@export var can_jump: bool = true
@export var jump_velocity: float = 8.0
@export var max_step_height: float = 1.2  # must stay under jump_velocity^2 / (2*GRAVITY)
```

Both constraints are enforced by tests
(`tests/integration/test_enemy_obstacles.gd`), because both were real bugs once:
a navmesh promising a step the physics body couldn't climb, and a `max_step_height`
that exceeded the real ballistic apex under the archetype's own jump velocity.

## Obstruction handling (`_check_obstruction`)

Runs every physics frame while an enemy wants to move but isn't making progress.
In order:

1. **Step-up** (`_try_step_up()`) — tried every frame, since a ledge is far more
   common than a real obstacle and stepping is instant. Raycasts ahead at
   `max_auto_step` height for headroom, then down from above to find the ledge
   top, then validates the destination with `test_move()` before committing
   (an earlier version teleported blind and bounced back out via depenetration).
2. **Link traversal** (`_try_traverse_link()`) — see [[#Jump links]] below.
3. **Jump** (`_try_jump_obstacle()`) — only after `STUCK_TIME = 0.3s` of no
   progress, gated by `JUMP_COOLDOWN = 0.9s`. Probes at shin height (0.12m) for
   an obstacle and at `max_step_height` for clearance.

## Jump links

`scripts/systems/jump_link.gd` (`class_name JumpLink extends NavigationLink3D`),
placed in `scenes/arena/jump_link.tscn`. Bridges navmesh islands the ramps used
to connect — the arena's raised platforms are otherwise unreachable once a level
has no walkable path up to it.

`get_launch_velocity(from, to, gravity)` solves the ballistic arc from the link's
own endpoints and a configured `flight_time`, rather than a tuned constant — it
stays correct if the link's placement or length changes later. `Enemy._try_traverse_link()`
finds the nearest link ahead (`_find_link_ahead()` — a single scan answers both
"is a link the next step" and "which one," a redundant double-scan here was
removed as dead-weight cost, see repo history), sets `velocity` to the solved
launch vector, and `_tick_link_traversal()` just rides it out until landing —
the arc is solved once at launch, nothing steers mid-flight.

`Enemy.deal_melee_damage()` gates the actual hit landing with a line-of-sight
raycast (`_can_see()`) — added after enemies wedged under a platform could hit a
player standing on top through solid floor geometry. This does **not** change
the "enemies always know player position" perception rule; it only gates whether
a landed hit connects.

## Attack timing is deliberately desynchronised

Enemies of one archetype share a period, so a group that spawns together attacks
in lockstep. Three rangers firing on the same frame means the player eats three
projectiles or none — neither reads as combat, and neither can be played around.

Two things break the alignment:

- `EnemyData.attack_cooldown_jitter` (default `0.35`) — each cooldown lands
  somewhere in a band around the archetype's value, so phases drift apart and
  never re-converge.
- `Enemy.setup()` seeds `_attack_cooldown_left` with a random fraction of one
  cooldown, so even the **first** attack of a wave arrives staggered. Without it
  the jitter only separates enemies after their first attack, which still goes
  off in unison. (Same trick as the separation timer directly below it, and for
  the same reason.)

The jitter is **centred, not additive**. A `[1.0, 2.0]` band would separate the
phases just as well and halve every archetype's damage per second on the way —
desynchronising should not quietly cost difficulty.
`test_the_cooldown_jitter_does_not_change_how_often_the_archetype_attacks` pins
the average back to the archetype's `attack_cooldown`, which is the property that
makes this a timing change rather than a balance change.

## The leap

The Rusher throws itself at the player instead of punching from where it stands
(`Enemy.start_leap()`, `ActionLeapAttack`, `EnemyData.can_leap` and the `Leap`
subgroup). The arc is solved at take-off — same ballistic solve as
[[#Jump links]] — and **never corrected in flight**, which is the whole point:
moving during the flight is what makes it miss. The melee hit it replaces simply
appeared once the enemy had reached you, with nothing to do about it.

- Damage is **contact, not reach** (`_check_leap_contact()`), and lands once no
  matter how many frames the bodies overlap.
- A miss costs the enemy `leap_recovery` seconds standing still and vulnerable.
  That window is what pays the player for reading the wind-up; without it the
  leap is free and the telegraph means nothing.
- `start_leap()` refuses without floor under it, beyond `leap_range`, or without
  line of sight — otherwise it launches into the wall in between.

`ActionTelegraph` was already the wind-up and is unchanged; only the strike it
leads into is new. The **Elite keeps its slam** — the acid pool is what makes it
area denial rather than a large Rusher.

`ConditionPlayerInRange` gained `use_leap_range` so the tree opens the branch at
the archetype's leap range (7m) rather than its punch range (2.2m). Expressing
that as a hand-computed multiplier over `attack_range` would go silently wrong
the moment either number moved.

## Where each archetype comes from

A horde's problem is not how many there are, it is **where**. With everything
arriving from the front, a wave is solved by turning as little as possible: no
checking your back, no repositioning, and two different archetypes feel the same
because they occupy the same slice of the screen.

`EnemyData` carries a preferred bearing measured **from the player's own
facing**, not from any arena direction: `approach_bearing_degrees` (0 front, 90
flank, 180 behind), `approach_bearing_weight`, `approach_bearing_mirrors`.
`Enemy.get_approach_position()` blends it with the lane offset that was already
there.

| Archetype | Bearing | Weight |
|---|---|---|
| Bomber | 180° (behind, unmirrored) | 0.85 |
| Environmental | ±65° (flank) | 0.6 |
| The original five | 0° | **0.0** |

Weight 0 is the default and reproduces the old behaviour **exactly**, which is
what let this land without touching the five existing archetypes.
`test_an_archetype_without_a_bearing_is_untouched` is the net under that claim.

**It fades up close**, on the same ramp the lane offset already used. An enemy
that insists on your back while you spin orbits forever and never attacks: flank
from far, commit from near. Without the fade the Bomber is a carousel that never
goes off.

The bearing comes from `get_player_facing()`, which reads the target's basis
rather than a `Player` API — so any `Node3D` works, including the bare node the
tests stand up as a fake player.

## The fuse

The Bomber (`EnemyData.has_fuse` and the `Fuse` subgroup, `Enemy.arm_fuse()` /
`_tick_fuse()` / `_detonate()`, `ActionArmFuse`) is a countdown with legs. It has
no attack: it walks at you, arms within `fuse_arm_range`, and `fuse_time` later
it goes off wherever it happens to be standing.

The design rests on one rule — **an armed fuse cannot be put out**:

- Running away does not disarm it. If it did, the answer to a Bomber would be
  "leave", and the archetype would have no question in it.
- Stagger and stun do not pause it. `_tick_fuse()` runs before the movement
  branches in `_physics_process` and outside all of them, so being knocked
  around, mid-air or frozen changes nothing.
- **Killing it detonates it early**, which is what turns the Bomber from a threat
  into a tool: shooting one while it stands in a crowd is a play. Killing one
  that never armed also detonates — a bomb that sometimes isn't reads far worse
  than one that always is, and always-explodes is what makes that play
  deliberate rather than accidental.

So the only question it asks is *where*, and the answer has to be reachable:
`test_the_fuse_outlasts_the_walk_from_where_it_arms` pins `fuse_time` above the
time it takes to cross `fuse_arm_range` at `move_speed`, because those are three
numbers tuned separately in a `.tres` and the relationship between them breaks
silently.

**One detonation, one site.** `_detonate()` does not spawn the blast; it kills
the Bomber, and `_on_died()` is the only place the blast comes from. That is what
makes the bomb that runs out and the bomb that eats a shotgun the exact same
death for the economy, the wave counter and the pool. `_has_detonated` is the
latch that stops the self-inflicted kill from re-entering and exploding twice.

`Explosion` (`scripts/actors/explosion.gd`) is deliberately **not** a
`HazardZone`. A hazard warns for 0.6s and then punishes standing still; an
explosion has already warned — the fuse was the warning, and far longer than
0.6s — and resolves in the instant it arrives. What it does inherit is the law:
the radius that hurts is the radius that was drawn. The `FuseRing` decal on the
enemy is authored from `explosion_radius` and dragged around by the walking bomb,
which is what lets the player pick the spot rather than only the moment. The
blink accelerates from `Tokens.TELL_BOMBER_FUSE_SLOW` to `_FAST`, the same
language the vanishing platform already taught.

The blast damages the player and the horde alike, and **that is the only friendly
fire inside the horde** — a Ranger cannot hit a team-mate with a stray shot. It
line-of-sight checks each victim for the same reason `deal_melee_damage()` does:
a blast that turns a corner is damage with nothing on screen to explain it.

## The flask

The Environmental (`data/enemies/environmental.tres`, `ActionThrowFlask`,
`EnemyFlask`) lobs a flask on an arc at the ground under the player, and where it
lands a pool denies that ground. It does not aim at the player: **missing is the
normal mode of operation**, because the job is to move you off the spot you are
standing on, not to hit you. An Environmental that lands it and one that misses
by a metre both cost you your position, and that is the whole difference between
it and the Ranger.

Almost none of this is new code, which was the point of building it second:

- The arc, the landing and the pooled lifetime are `ThrownUtility` — the same
  base the player's three thrown utilities use. It really is the same object with
  a different payload.
- The pool is a `HazardZone`, unmodified, exactly like the Elite's slam. That
  matters more than it sounds: the pool inherits the 0.6s warning and the
  decal-drawn-at-the-damage-radius law **for free**, so a new archetype cannot
  break the telegraph by accident. A bespoke area could have skipped both and
  nothing would have failed.

Two things had to open up in `ThrownUtility`, both cases where the player's
version was one special case being treated as the only one:

- `launch_with_velocity()` — a fixed force along a direction is one way to get a
  velocity. Anything that has to *arrive* somewhere solves a ballistic arc
  instead, and `ActionThrowFlask._arc_to()` uses the same solve as
  [[#Jump links]] and [[#The leap]]. It reads gravity from
  `ThrownUtility.get_gravity()` rather than writing the constant twice — the
  failure mode of two copies is "flasks land short", which nobody reads as a
  constants bug.
- `hit_mask` — the player's utilities stop on enemies on purpose (a stun grenade
  that sails through the crowd is a wasted charge). The flask needs the opposite:
  it is lobbed *over* the horde, and stopping on the first ally turns area denial
  into a puddle at its own feet. So the payload picks.

The throw lives entirely in the leaf, not on `Enemy`, following `ActionEliteSlam`.
That also avoids a cycle: `EnemyFlask` extends `ThrownUtility`, which names
`Enemy`, so an `enemy.gd` that named the flask would close the loop — see the
note in `Explosion._victims()` for what that failure looks like.

**Not built:** the trapping flask (§4.2 of the plan), the one that immobilises.
It is deliberately last, because taking away movement fights the game's own
movement pillar and the call should be made while playing.

## Flight

Volar no es un número distinto, es un modo de movimiento entero. Todo lo demás
del enemigo —navegación, saltos, `JumpLink`, manejo de obstrucciones, el juicio
del aterrizaje— asume un cuerpo que camina y termina apoyado en algo, y nada de
eso aplica. Por eso `_fly()` es **una rama temprana en `_physics_process`,
hermana de `_is_leaping`**, y no un caso especial embutido en `_steer()`: meterlo
ahí habría sido pedirle a esa función que sepa de dos mundos.

Lo que reemplaza a toda esa maquinaria son dos rayos:

- **Hacia abajo**, para la altura. La altura es sobre el **terreno**, no sobre el
  cero del arena: en una rampa que sube, el volador sube. Sin eso se mete dentro
  de la cuesta, que se ve como un bicho nadando en la geometría. Sin piso abajo
  —un pozo, el borde del arena— mantiene la altura que tiene: bajar a buscar un
  piso que no existe es caerse.
- **Hacia adelante**, para no incrustarse. Al encontrar algo, sube. Es la única
  esquiva garantizada; rodear puede meterlo en un rincón. La subida pisa la
  corrección de altura de ese frame a propósito —la pared es más urgente que la
  altura de crucero— y en cuanto la pasa vuelve sola.

Hay un tercer rayo hacia arriba dentro del control de altura: bajo una galería,
un volador que insiste en su altura de crucero se queda apretado contra el techo
temblando, así que el techo le baja el objetivo mientras dure.

**Aturdirlo lo frena, no lo baja.** Si el stagger le apagara la altura, cada
impacto lo tiraría al piso y el arquetipo dejaría de existir. Y la gravedad no se
le compensa: no la tiene. Un volador que se sostiene peleando contra su propio
peso oscila, y la oscilación se ve.

`EnemyData.can_fly` lo enciende, igual que `has_fuse` enciende la espoleta:
`Enemy` no pregunta por arquetipo en ningún lado.

### Lo que se descubrió construyéndolo

El Flyer tenía que llegar **desde los costados** (§4.1 del plan) y no llegaba, por
un motivo que no tenía nada que ver con volar: `_approach_commit_distance()`
estaba atado a `attack_range`, así que un arquetipo de alcance 20 se comprometía
—dejaba de flanquear y encaraba de frente— a 36m, y después se plantaba a pelear
a 13m. O sea que flanqueaba mientras caminaba y se ponía de frente justo cuando
empezaba el tiroteo. Su requisito entero era falso en silencio.

Ahora, cuando un arquetipo pide rumbo **y** kitea, el commit sale de
`preferred_distance` y no del alcance. Sale con las dos condiciones y no con
`preferred_distance` sola porque el Ranger y el Healer también kitean y no piden
rumbo: para ellos el número de siempre es el correcto.

**Esto además arregla al Environmental**, que tenía el mismo problema (commit a
32.4m, pelea a 12m) y por lo tanto tampoco flanqueaba nunca. Su test no lo
detectó porque pasaba de forma vacía: con el punto de aproximación igual a la
posición del jugador, `normalized()` da el vector nulo, el `dot` da 0 y el ángulo
da 90 grados exactos — o sea que "se sale del frente" se cumplía justamente
cuando el enemigo iba derecho al jugador. El test ahora exige primero que el
punto no sea el jugador mismo.

Tests en `tests/integration/test_flyer.gd`.

## Factions, and who an enemy is actually fighting

`Enemy` no tenía la noción de "mi objetivo": tenía `get_player()`, y de ahí
colgaba todo — el melee, el salto, el disparo, los flancos y tres hojas del árbol
de Beehave. Eso es correcto mientras "hostil" y "el jugador" sean sinónimos, y
deja de serlo con una tercera facción (§2.1 y §5.2 del plan).

**La regla de hostilidad es una sola:** todos son hostiles a todos los que no son
de su facción (`Factions.are_hostile()`). La celda rara de la matriz del plan —
horda contra horda, permitido sólo para la explosión del Bomber — **no** vive en
la matriz: vive en `Explosion`, que es el único que lastima sin preguntar.
Ponerla en la matriz habría hecho que cualquier daño futuro entre miembros de la
horda pareciera autorizado.

`Enemy.get_target()` reemplaza a `get_player()`, que queda como alias. La
resolución es "el hostil más cercano", y para la horda de hoy eso da el jugador
siempre porque no hay nadie más de otra facción en el arena — que es exactamente
lo que permitió cambiarlo sin tocar un solo test de los cinco arquetipos
originales.

**El aggro-lock hace dos trabajos.** Se re-apunta sólo al perder el objetivo,
nunca por distancia. Eso ya evitaba que un bicho oscilara entre dos jugadores que
se cruzan corriendo; ahora además es lo que resuelve gratis las dos advertencias
de §5.3 del plan — la histéresis (no hay ping-pong porque no se vuelve a elegir)
y el costo (la lista se recorre al perder el objetivo, no cada frame).

**La facción es un campo de `EnemyData`, no una clase.** El arquetipo dice *cómo*
pelea y la facción dice *contra quién*, así que un Gladiador va a poder reusar un
arquetipo existente cambiando un `.tres`.

### Lo que la física tiene que saber

Los Gladiadores tienen capa propia (`PhysicsLayers.GLADIATOR`) en vez de compartir
`ENEMY`, y `Enemy._apply_collision()` la asigna desde la facción. No es
decoración: hay consultas que se resuelven en el servidor de física y no pueden
filtrar por bando después. Un proyectil de la horda tiene que **atravesar** a un
compañero y **frenar** contra un Gladiador, y eso es una máscara, no un `if`.

Los dos filtros de §2.2 quedaron abiertos así:

- `EnemyProjectile` enmascara `WORLD | Factions.hostile_mask(tirador)` en vez de
  `WORLD | PLAYER`. Para la horda eso da `PLAYER | GLADIATOR`, y como no hay
  ningún cuerpo en esa capa todavía, la bala vuela exactamente igual que antes.
- El `is_in_group(&"player")` posterior pasó a ser una pregunta de facción. Los
  dos hacían falta: sin el segundo, la máscara deja pasar la bala hasta el cuerpo
  y el daño se cae un metro después.

`HazardZone` también aprendió bandos: un charco con dueño no quema a los del
dueño. Antes sí — el charco del Elite lastimaba a la horda entera, que es el fuego
amigo que el plan reserva sólo para el Bomber. Una trampa del arena no tiene dueño
y sigue quemando a todo el mundo, que es lo correcto para una trampa. Por el mismo
motivo, "ally" pasó a significar algo en `heal_nearby_allies()`: el Healer cura a
los de su facción, no a cualquiera que esté en el grupo `&"enemy"`.

### Lo que quedó igual a propósito

- **Los nombres de las hojas.** `action_chase_player`, `condition_player_in_range`
  y compañía siguen llamándose así aunque llamen a la API de objetivo. Renombrar
  los archivos toca cada `.tscn` de árbol de comportamiento, que es riesgo sin
  ganancia.
- **La separación (`_flock`) no sabe de facciones.** Un Gladiador y un Rusher se
  empujan como si fueran del mismo bando. Puede estar bien —son cuerpos— y sigue
  siendo una decisión abierta del plan (§5.5).

Tests en `tests/integration/test_factions.gd`. La otra mitad de la red es que
`test_enemy_behavior.gd` y `test_enemy_pathing_fixes.gd` pasan **sin modificarse**.

## Whose kill it was

Hasta ahora morirse alcanzaba para que el jugador cobrara: `Enemy._on_died()`
emitía `kill_credited` incondicionalmente. Eso funciona mientras el jugador sea
el único que reparte daño, y deja de funcionar en cuanto hay alguien más — los
Gladiadores (§5 del plan), pero también la explosión del Bomber, que ya existe.

La atribución vive en **un solo lugar**: `HealthComponent.last_attacker`. Es el
embudo por el que ya pasaban todas las fuentes de daño del juego, y anotar al
atacante en cada una por separado era garantizar que la próxima se olvidara.
`apply_damage(amount, attacker)` lo deja registrado; `take_hit()` lo pasa por
arriba para el hitbox.

Tres reglas que no son obvias:

- **Un golpe sin atacante no borra al dueño anterior.** `null` significa "nadie
  se lo atribuye", no "ahora es de nadie". Es el caso de la espoleta del Bomber
  matándose sola: si el jugador lo dejó al borde de la muerte y la cuenta llegó a
  cero un frame antes que la próxima bala, esa muerte sigue siendo suya.
- **La explosión tiene dos nodos distintos y no hay que confundirlos.**
  `Explosion.detonate()` recibe `source` (quién revienta, y queda excluido de sus
  propias víctimas) y `attacker` (de quién es lo que mate). El Bomber es lo
  primero; el que voló al Bomber es lo segundo. Esa distinción **es** la jugada:
  si la cadena se atribuyera a sí misma, elegir dónde matarlo no pagaría nada.
- **El charco es del actor, no del volumen.** `HazardZone.attacker` se setea en
  `setup()`, porque el `HazardZone` vuelve al pool y el próximo lo reusa,
  mientras que el Elite o el Environmental que lo dejó no.

`enemy_killed` y `kill_credited` siguen siendo dos señales porque ahora sí
contestan cosas distintas: la primera es "murió uno" y la cobra el contador de la
oleada pase lo que pase — una ola que no termina porque la última muerte fue
ajena sería un cuelgue, no un balance —, la segunda es "y es tuyo".

Tests en `tests/integration/test_kill_attribution.gd`.

## Enemy meshes

`EnemyData.mesh` is typed `Mesh` (not `PackedScene`) — an imported `.fbx` scene
can't be assigned directly, since Godot's fbx importer produces a full node
hierarchy with a root-level transform (rotation from the Z-up→Y-up conversion,
plus whatever scale the source file's units imply), not a standalone mesh
resource. SpiderBot (Rusher) and UAL1_Standard (Elite) were baked offline:
`SurfaceTool.append_from(mesh, surface, transform)` walks the composed local
transform down to the mesh node and bakes it into a new `ArrayMesh`, then the
result is recentred on its own AABB and rescaled to the archetype's
`collision_height` (this matches how the box/capsule placeholders were already
authored — pivot at the shape's own center). Saved as `.res` files under
`assets/models/meshes/`.

## Beehave

Behavior trees live under `scenes/enemies/ai/`, built from leaves in
`scripts/ai/actions/` and `scripts/ai/conditions/`:

- **Actions**: `action_chase_player`, `action_keep_distance`, `action_melee_attack`,
  `action_leap_attack`, `action_ranged_attack`, `action_telegraph`,
  `action_heal_allies`, `action_summon_adds`, `action_elite_slam`,
  `action_arm_fuse`, `action_throw_flask`.
  `action_melee_attack` is still the standing hit, but no tree uses it since the
  Rusher moved to `action_leap_attack` — it stays as the plain melee an archetype
  without `can_leap` would use.
- **Conditions**: `condition_player_in_range` (`range_multiplier`,
  `absolute_range`, `use_leap_range`, `use_fuse_range`, `invert`),
  `condition_attack_ready`, `condition_not_staggered`.

`tree_bomber` is the smallest tree in the game and half the archetype's
personality: no attack branch, no attack telegraph, no cooldown. It closes, it
arms, and everything after that lives in `Enemy._tick_fuse()` — outside the tree,
because a tree can abandon a branch and a fuse cannot be abandoned.
`ActionArmFuse` returns SUCCESS only on the frame it arms and FAILURE forever
after, so the selector falls through to chasing: an armed bomb that stops walking
hands the player the one decision the archetype exists to ask for.

`BeehaveGlobalMetrics` / `BeehaveGlobalDebugger` are addon autoloads, registered
last in `project.godot` load order.

## Stagger, slow, stun

`Enemy.apply_stun(duration)`, `apply_slow(multiplier)` / `clear_slow()`,
`is_staggered()` — `stagger_resistance` (0–1) on `EnemyData` scales how much a
hit actually staggers a given archetype (Elites resist almost entirely).

## Navmesh baking

Offline only — `tools/bake_navmesh.gd`, run manually, output committed to
`scenes/arena/greybox_arena_navmesh.tres`. `ArenaNavigation`
(`scripts/systems/arena_navigation.gd`, a `NavigationRegion3D` subclass) loads
the committed bake at runtime; `bake_on_ready` is a dev-only escape hatch for
iterating on layout and must stay `false` in anything committed — baking CSG
geometry at runtime pulls meshes back from the GPU, which Godot itself warns is
a real cost. `AGENT_RADIUS = 0.85` in the bake tool is sized for the largest
archetype (Elite, 0.75).
