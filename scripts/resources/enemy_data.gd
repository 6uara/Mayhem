@tool
class_name EnemyData
extends Resource
## Static definition of an enemy archetype. One enemy scene is shared by every
## archetype; this resource is what makes a Rusher a Rusher - silhouette, audio,
## stats and behavior tree all come from here.

enum Archetype { RUSHER, RANGER, ELITE, HEALER, SUMMONER, BOMBER, ENVIRONMENTAL, FLYER }

@export var id: StringName = &""
@export var display_name: String = ""
@export var archetype: Archetype = Archetype.RUSHER
## De qué bando pelea. Separado de `archetype` a propósito: el arquetipo dice
## **cómo** pelea y la facción dice **contra quién**, y los Gladiadores van a
## reusar arquetipos existentes cambiando sólo esto (ver `Factions`).
@export var faction: Factions.Id = Factions.Id.HORDE
## Behavior tree scene, instantiated under the enemy at spawn.
@export var behavior_tree: PackedScene

@export_group("Stats")
@export var max_health: float = 100.0
@export var move_speed: float = 5.0
@export var damage: float = 10.0
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.5
@export var mass: float = 1.0
## 0 = fully staggered by every hit, 1 = immovable. Elites sit high.
@export var stagger_resistance: float = 0.0

@export_group("Movement")
## Enemies hop obstacles rather than grinding against them.
##
## A navmesh path is a plan, not a guarantee: the lip where a ramp meets the floor,
## a doorway another enemy is filling, geometry the bake smoothed over. All of it
## reads to the player as "the AI is broken" unless the enemy can simply get over
## the thing in its way.
## Ledges up to this tall are simply stepped over, no jump involved.
##
## This number is a contract with the navmesh, not a taste setting. The bake uses
## agent_max_climb to decide which surfaces connect, so it hands out paths that
## cross ledges up to that height - and Godot's CharacterBody3D has no step-up of
## its own, so without this it would be promised a 0.5m step and deliver none.
## Keep it at or above the bake's agent_max_climb.
@export var max_auto_step: float = 0.6

@export var can_jump: bool = true
@export var jump_velocity: float = 8.0
## Tallest obstacle this archetype will attempt; anything higher it walks around.
##
## Must stay under the hop's real apex (jump_velocity^2 / 2g, so 1.33m at the
## defaults) or the enemy commits to jumps it cannot finish and the clearance probe
## measures air it will never reach. A test enforces the relationship.
@export var max_step_height: float = 1.2

@export_group("Attack")
## Wind-up before the attack lands. Telegraphing is mandatory (CLAUDE.md 5.3) and
## this is the timing half of it - scale it with damage.
@export var attack_windup: float = 0.6
## Cuanto se corre al azar cada cooldown, como fraccion. 0.35 = entre el 65% y el
## 135% del valor base.
##
## Existe porque tres enemigos iguales que aparecen juntos comparten periodo, y
## sin esto sus ataques quedan pegados para siempre: los tres rangers disparan en
## la misma decima, el jugador come tres proyectiles o ninguno, y ninguna de las
## dos cosas se puede jugar. Con el jitter las fases se separan solas y no se
## vuelven a juntar.
##
## Va centrado en 1.0 a proposito - un rango tipo [1.0, 2.0] tambien desincroniza,
## pero de paso baja el DPS del arquetipo a la mitad, y desincronizar no deberia
## costar dificultad. Ver tambien el desfase inicial en Enemy.setup().
@export_range(0.0, 0.9, 0.05) var attack_cooldown_jitter: float = 0.35
## Ranged archetypes only.
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 30.0
## Distance the archetype tries to hold. 0 = close to attack_range and stay.
@export var preferred_distance: float = 0.0

@export_subgroup("Leap")
## El melee se tira encima del jugador en vez de golpear parado.
##
## Cambia a que se parece el cuerpo a cuerpo: en vez de un golpe que aparece
## cuando el enemigo ya te alcanzo, es un compromiso que se lee y se esquiva. El
## enemigo apunta a donde estas al despegar y no corrige en el aire, asi que
## moverse durante el vuelo es lo que lo hace fallar.
@export var can_leap: bool = false
## Desde cuan lejos se anima a saltar. El arco se resuelve para llegar exacto, asi
## que esto es alcance de verdad y no una sugerencia.
@export var leap_range: float = 7.0
## Cuanto dura el vuelo. Es la ventana que tiene el jugador para salirse.
@export var leap_flight_time: float = 0.5
## Quieto y vulnerable despues de aterrizar.
##
## Es el premio por esquivar: sin esto el salto le sale gratis al enemigo y
## leer la telegrafia no paga nada.
@export var leap_recovery: float = 0.5

@export_subgroup("Flight")
## Este arquetipo vuela: no pisa el navmesh, no le pega la gravedad y no salta.
##
## Es un modo de movimiento entero, no un numero distinto. Todo lo demas del
## enemigo -navegacion, saltos, links, el juicio del aterrizaje- asume un cuerpo
## que camina y termina apoyado en algo, y nada de eso aplica. Por eso el vuelo es
## una rama temprana en _physics_process y no un caso especial adentro de
## _steer(): un volador no participa de ninguna de esas maquinarias.
@export var can_fly: bool = false
## A que altura sobre el terreno se mantiene, medida con un rayo hacia abajo.
##
## Sobre el terreno y no sobre el cero del arena: una rampa que sube tiene que
## empujarlo hacia arriba, o el volador se mete adentro del piso a mitad de la
## cuesta y el jugador ve un bicho nadando en la geometria.
@export var flight_height: float = 5.0
## Cuan rapido corrige la altura. Aparte de move_speed porque son dos
## sensibilidades distintas: un volador nervioso en vertical se lee como un bug
## aunque su velocidad horizontal este bien.
@export var flight_climb_speed: float = 6.0
## Cuanto adelante mira para no chocarse. Al encontrar algo sube, que es la unica
## esquiva que un volador tiene garantizada - rodear puede meterlo en un rincon.
@export var flight_probe_distance: float = 3.0

@export_subgroup("Fuse")
## El arquetipo es una bomba: se arma cerca del jugador y despues revienta.
##
## No es un ataque, es una cuenta regresiva. Una vez armada no se desarma - huir
## no la apaga, y morir la adelanta en vez de cancelarla - asi que la pregunta
## que le hace al jugador no es "escapo?" sino "donde lo hago explotar?". Eso lo
## convierte en un recurso: matarlo parado al lado de un grupo es una jugada.
##
## Enemy no pregunta por arquetipo en ningun lado; lee esto. Cualquier arquetipo
## futuro que quiera explotar lo consigue prendiendo este flag.
@export var has_fuse: bool = false
## Cuanto tarda la espoleta desde que se arma. Es la ventana entera que tiene el
## jugador para reposicionarse, asi que va larga a proposito.
@export var fuse_time: float = 2.2
## Desde cuan cerca del jugador se arma. 0 = usa attack_range.
##
## Va separado de attack_range porque el Bomber no golpea: su "alcance" es el
## radio de la explosion, y armar la espoleta recien cuando ya esta encima no le
## da tiempo a nadie a leer nada.
@export var fuse_arm_range: float = 0.0
@export var explosion_damage: float = 55.0
## Radio del estallido. Es tambien el radio exacto del anillo de aviso que el
## Bomber arrastra mientras cuenta: el decal es la promesa (ver HazardZone).
@export var explosion_radius: float = 4.5
@export var explosion_scene: PackedScene

@export_group("Approach")
## Donde alrededor del jugador quiere pararse este arquetipo, en grados desde la
## direccion a la que el jugador esta mirando. 0 = de frente, 90 = por el
## costado, 180 = por la espalda.
##
## Existe porque el problema de una horda no es cuantos son sino DONDE estan: si
## todos vienen de frente, el jugador resuelve la ola girando lo menos posible y
## el arena deja de importar. Que cada arquetipo prefiera un sector distinto es
## lo que obliga a chequear atras, y de paso hace que se lean distinto entre
## ellos sin cambiarles ni una estadistica.
@export_range(0.0, 180.0, 5.0) var approach_bearing_degrees: float = 0.0
## Cuanto le importa. 0 = nada, y el arquetipo se comporta exactamente como
## antes de que esto existiera - por eso es el default.
@export_range(0.0, 1.0, 0.05) var approach_bearing_weight: float = 0.0
## Si vale cualquiera de los dos costados (+-grados) o solo uno.
##
## Un angulo de 90 grados espejado son "los flancos"; sin espejar es siempre el
## mismo, que para un grupo entero se ve como una coreografia. La espalda (180)
## no tiene espejo util, pero tampoco molesta.
@export var approach_bearing_mirrors: bool = true

@export_group("Support")
## Healer: health restored per pulse. `attack_cooldown` gates how often it pulses.
@export var heal_amount: float = 12.0
@export var heal_radius: float = 8.0
## Summoner: what it spawns and how often.
@export var summon_data: EnemyData
@export var summon_count: int = 2
@export var summon_interval: float = 6.0

@export_group("Presentation")
## The Healer's floating ring. It is not decoration: Ranger and Healer share body
## proportions, so the halo is what separates their silhouettes at range - and it
## stays visible over cover and through crowds, which is the whole point of a
## priority target (SPEC-VIEWMODELS 2.2).
@export var has_halo: bool = false
@export var halo_radius: float = 0.75
@export var halo_height: float = 2.6
## Draws a beam to whoever this enemy is currently helping.
@export var has_tether: bool = false
## Silhouette must be readable at a glance (CLAUDE.md 5.3).
@export var mesh: Mesh
## A rigged model, shown instead of `mesh` when one is set.
##
## The primitive silhouette stays the fallback rather than being replaced
## outright: grey-boxing an archetype has to keep working with nothing but a
## capsule and a colour, and archetypes get their models one at a time.
##
## Gameplay reads none of this. The capsule, the hitboxes and the head are
## authored below and stay where they are, so dropping a model in cannot quietly
## change what a shot hits or where an enemy fits.
@export var model_scene: PackedScene
## Models arrive in whatever units they were authored in - the spider bot is
## about six units across - so the scale that makes it the right size on screen
## belongs next to the model, not baked into the .fbx import.
@export var model_scale: float = 1.0
## Where the model sits relative to the body's origin, which is on the floor.
## Mostly a vertical nudge to plant the feet.
@export var model_offset: Vector3 = Vector3.ZERO
## Yaw correction, in degrees.
##
## Godot drives a body along its -Z, and a model is only ever pointing that way
## by luck - the spider bot was authored facing +Z, so it walked backwards until
## this was turned around. Belongs to the archetype rather than to the .fbx
## import so it is visible next to the rest of the placement.
@export_range(-180.0, 180.0, 1.0) var model_yaw_degrees: float = 0.0
@export var body_color: Color = Color(0.6, 0.62, 0.66)
@export var body_scale: float = 1.0
## Capsule collision, kept in sync with the mesh by hand while grey-boxing.
@export var collision_height: float = 1.8
@export var collision_radius: float = 0.4
## Radius of the *shootable* volume, when the silhouette is wider than the body.
##
## These are two different jobs and they stopped being the same number the moment
## real meshes arrived. `collision_radius` is a movement contract - it has to stay
## under the navmesh bake's agent radius or the archetype cannot fit through its
## own arena. The hitbox only has to answer "did that shot look like it hit?", and
## the player aims at the silhouette, so a model wider than its capsule is a model
## whose outer half is quietly bulletproof.
##
## 0 means "same as collision_radius", which is right for anything roughly as wide
## as it is deep.
@export var hitbox_radius: float = 0.0
@export var head_offset: float = 1.62
@export var head_radius: float = 0.25

@export_group("Audio")
## Each archetype must be identifiable by sound alone (CLAUDE.md 6).
@export var spawn_sound: AudioStream
@export var windup_sound: AudioStream
@export var attack_sound: AudioStream
@export var death_sound: AudioStream
## Loop de la espoleta armada. Suena una vez al armarse y despues acompaña el
## parpadeo: con tres bombas en pantalla el oido es lo que dice cuantas hay.
@export var fuse_sound: AudioStream
@export var explosion_sound: AudioStream

@export_group("Economy")
@export var reward_currency: int = 10
