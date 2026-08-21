class_name HitboxComponent
extends Area3D
## A damageable volume routing hits to a HealthComponent.
## Headshots are just a hitbox with a damage_multiplier - there are no limb zones.

signal hit_taken(amount: float, is_headshot: bool, hit_position: Vector3)

## Body hitboxes leave this at 1.0; head hitboxes override it per enemy.
@export var damage_multiplier: float = 1.0
@export var is_headshot_zone: bool = false
@export var health_component: HealthComponent


func _ready() -> void:
	if health_component == null:
		# Degrade gracefully: a hitbox with no health still absorbs the shot.
		push_warning("HitboxComponent on %s has no HealthComponent" % get_path())
	# Every hitbox is flesh - lets ImpactEffect resolve its material the same
	# way for a hitbox or bare world geometry (SurfaceMaterials.resolve()),
	# with no is_flesh special-case anywhere in the projectile code.
	set_meta(SurfaceMaterials.META_KEY, &"flesh")


# Public API

## Applies `base_damage` scaled by this zone's multiplier.
## Returns the damage actually dealt so the shooter can drive hitmarkers.
##
## `attacker` viaja hasta el HealthComponent y es lo que decide de quién es la
## muerte. Opcional: un hitbox golpeado por algo anónimo sigue sangrando igual.
func take_hit(base_damage: float, hit_position: Vector3, attacker: Node = null) -> float:
	var amount: float = base_damage * damage_multiplier
	var applied: float = 0.0
	if health_component != null:
		applied = health_component.apply_damage(amount, attacker)
	hit_taken.emit(applied, is_headshot_zone, hit_position)
	EventBus.damage_dealt.emit(owner, applied, is_headshot_zone)
	return applied
