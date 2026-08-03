class_name SpawnDoor
extends Node3D
## A fixed, telegraphed spawn point. Doors light up and sound off before anything
## comes out, so the player can pre-position (CLAUDE.md 5.3). Distribution across
## the arena is a level-design job: no camping spot should cover all of them.

const TELEGRAPH_TIME: float = 1.2

@export var door_id: StringName = &"door_01"
@export var light: OmniLight3D
@export var frame_mesh: MeshInstance3D
@export var spawn_point: Node3D
@export var telegraph_color: Color = Color(1.0, 0.35, 0.2)
@export var open_sound: AudioStream

var _is_telegraphing: bool = false
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"spawn_door")
	if frame_mesh != null:
		var source: Material = frame_mesh.get_active_material(0)
		if source != null:
			_material = source.duplicate() as StandardMaterial3D
			frame_mesh.material_override = _material
	if light != null:
		light.light_energy = 0.0


# Public API

func get_spawn_position() -> Vector3:
	return spawn_point.global_position if spawn_point != null else global_position


## Lights up and sounds off, then resolves after TELEGRAPH_TIME. Callers await this
## so the first enemy of a group never appears before its tell.
func telegraph() -> void:
	if _is_telegraphing:
		await get_tree().create_timer(TELEGRAPH_TIME).timeout
		return
	_is_telegraphing = true
	AudioPool.play_3d(open_sound, global_position, AudioPool.BUS_WORLD)

	var tween: Tween = create_tween()
	if light != null:
		light.light_color = telegraph_color
		tween.tween_property(light, "light_energy", 6.0, TELEGRAPH_TIME * 0.6)
		tween.tween_property(light, "light_energy", 2.5, TELEGRAPH_TIME * 0.4)
	if _material != null:
		_material.emission_enabled = true
		_material.emission = telegraph_color
		_material.emission_energy_multiplier = 1.5

	await get_tree().create_timer(TELEGRAPH_TIME).timeout
	_is_telegraphing = false


## Dims the door once its group has finished spawning.
func close() -> void:
	if light != null:
		var tween: Tween = create_tween()
		tween.tween_property(light, "light_energy", 0.0, 0.4)
	if _material != null:
		_material.emission_energy_multiplier = 0.0
