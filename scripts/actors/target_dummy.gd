class_name TargetDummy
extends StaticBody3D
## Static grey-box target for tuning gunplay. Flashes and staggers on hit, respawns
## after death so the range never runs dry.

const FLASH_TIME: float = 0.08
const RESPAWN_DELAY: float = 2.0

@export var health: HealthComponent
@export var mesh: MeshInstance3D
@export var flash_color: Color = Color(1.0, 0.35, 0.25)

## Hitbox children, collected on ready and switched off while the dummy is down.
var _hitboxes: Array[HitboxComponent] = []

var _flash_timer: float = 0.0
var _material: StandardMaterial3D
var _base_color: Color = Color.WHITE


func _ready() -> void:
	for child: Node in get_children():
		var hitbox := child as HitboxComponent
		if hitbox != null:
			_hitboxes.push_back(hitbox)
	if mesh != null:
		_material = mesh.get_active_material(0)
		if _material != null:
			_material = _material.duplicate() as StandardMaterial3D
			mesh.material_override = _material
			_base_color = _material.albedo_color
	if health != null:
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)


func _process(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer -= delta
	if _flash_timer <= 0.0 and _material != null:
		_material.albedo_color = _base_color


# Private

## Hit reaction is a gunplay-feel requirement, not an AI one: every shot must
## visibly and audibly land.
func _on_damaged(_amount: float, _remaining: float) -> void:
	_flash_timer = FLASH_TIME
	if _material != null:
		_material.albedo_color = flash_color


func _on_died() -> void:
	_set_targetable(false)
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_inside_tree():
		return
	health.reset()
	_set_targetable(true)


## Hitboxes are found by the projectile's ray, not by monitoring, so they have to be
## taken off their physics layer rather than just disabled.
func _set_targetable(value: bool) -> void:
	visible = value
	for hitbox: HitboxComponent in _hitboxes:
		if hitbox != null:
			hitbox.collision_layer = PhysicsLayers.HITBOX if value else 0
