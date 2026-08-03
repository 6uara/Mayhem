class_name EnemyData
extends Resource
## Static definition of an enemy archetype. One enemy scene is shared by every
## archetype; this resource is what makes a Rusher a Rusher - silhouette, audio,
## stats and behavior tree all come from here.

enum Archetype { RUSHER, RANGER, ELITE, HEALER, SUMMONER }

@export var id: StringName = &""
@export var display_name: String = ""
@export var archetype: Archetype = Archetype.RUSHER
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
## Ranged archetypes only.
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 30.0
## Distance the archetype tries to hold. 0 = close to attack_range and stay.
@export var preferred_distance: float = 0.0

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
@export var body_color: Color = Color(0.6, 0.62, 0.66)
@export var body_scale: float = 1.0
## Capsule collision, kept in sync with the mesh by hand while grey-boxing.
@export var collision_height: float = 1.8
@export var collision_radius: float = 0.4
@export var head_offset: float = 1.62
@export var head_radius: float = 0.25

@export_group("Audio")
## Each archetype must be identifiable by sound alone (CLAUDE.md 6).
@export var spawn_sound: AudioStream
@export var windup_sound: AudioStream
@export var attack_sound: AudioStream
@export var death_sound: AudioStream

@export_group("Economy")
@export var reward_currency: int = 10
