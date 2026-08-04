class_name SpawnDoor
extends Node3D
## A fixed, telegraphed spawn point. Doors light up and sound off before anything
## comes out, so the player can pre-position (CLAUDE.md 5.3). Distribution across
## the arena is a level-design job: no camping spot should cover all of them.

const TELEGRAPH_TIME: float = 1.2

@export var door_id: StringName = &"door_01"
@export var light: OmniLight3D
@export var frame_mesh: MeshInstance3D
## The portal quad filling the doorway - a swirling vortex, not a flat panel, so
## the threshold itself reads as "something comes through here" even at rest.
@export var portal_mesh: MeshInstance3D
@export var spawn_point: Node3D
## Magenta is reserved entirely for "enemies come from here", so a door
## lighting up is unambiguous anywhere in the arena.
@export var telegraph_color: Color = Color("#FF3BC1")
@export var open_sound: AudioStream

const PORTAL_IDLE_GLOW: float = 0.3
const PORTAL_TELEGRAPH_GLOW: float = 2.2

var _is_telegraphing: bool = false
var _material: StandardMaterial3D
## Sub-resources in a .tscn are shared across every instance of that scene by
## default - seven doors sharing one portal would mean telegraphing one lights
## every door in the arena. Duplicating on ready is what gives each its own.
var _portal_material: ShaderMaterial


func _ready() -> void:
	add_to_group(&"spawn_door")
	if frame_mesh != null:
		var source: Material = frame_mesh.get_active_material(0)
		if source != null:
			_material = source.duplicate() as StandardMaterial3D
			frame_mesh.material_override = _material
	if portal_mesh != null:
		var source: Material = portal_mesh.get_active_material(0)
		if source != null:
			_portal_material = source.duplicate() as ShaderMaterial
			_portal_material.set_shader_parameter(&"tint", telegraph_color)
			portal_mesh.material_override = _portal_material
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
	if _portal_material != null:
		# Parallel with the step just queued: the vortex spins up alongside the
		# light's first ramp, not after it, so both land together.
		tween.parallel().tween_method(_set_portal_glow,
			PORTAL_IDLE_GLOW, PORTAL_TELEGRAPH_GLOW, TELEGRAPH_TIME * 0.6)
	if light != null:
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
	if _portal_material != null:
		var tween: Tween = create_tween()
		tween.tween_method(_set_portal_glow, PORTAL_TELEGRAPH_GLOW, PORTAL_IDLE_GLOW, 0.4)


func _set_portal_glow(value: float) -> void:
	_portal_material.set_shader_parameter(&"glow_energy", value)
