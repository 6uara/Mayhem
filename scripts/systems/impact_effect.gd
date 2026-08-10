class_name ImpactEffect
extends Node3D
## Pooled impact feedback: particles, a decal on hard surfaces, and a sound -
## all keyed to whatever SurfaceMaterialData the hit resolved to
## (SurfaceMaterials.resolve()). Grey-box first pass - the particle/decal art
## is replaced in Phase 5.

const LIFETIME: float = 1.2

## Used only if play_at() is ever called with a null material - should not
## happen in practice, since SurfaceMaterials.resolve() always falls back to
## DEFAULT_ID itself, but a pooled VFX object must never error on bad input.
@export var fallback_material: SurfaceMaterialData

@onready var _particles: GPUParticles3D = $Particles
@onready var _decal: Decal = $Decal

## Per-instance copy of the spark mesh's material, so retinting one impact's
## sparks (accent_color) never bleeds into every other pooled ImpactEffect
## sharing the same source mesh.
var _spark_material: StandardMaterial3D

var _timer: float = 0.0
var _is_playing: bool = false


func _ready() -> void:
	if _particles == null:
		return
	var mesh: QuadMesh = _particles.draw_pass_1.duplicate()
	_spark_material = (mesh.material as StandardMaterial3D).duplicate()
	mesh.material = _spark_material
	_particles.draw_pass_1 = mesh


func _process(delta: float) -> void:
	if not _is_playing:
		return
	_timer -= delta
	if _timer <= 0.0:
		ObjectPool.release(self)


## Places the effect against a surface, styled by `material` - the decal, spark
## colour and sound all come from it. `normal` orients both particles and decal.
func play_at(hit_position: Vector3, normal: Vector3, material: SurfaceMaterialData) -> void:
	var resolved: SurfaceMaterialData = material if material != null else fallback_material
	global_position = hit_position
	_orient_to(normal)
	_timer = LIFETIME
	_is_playing = true

	if resolved == null:
		if _particles != null:
			_particles.restart()
		return

	if _decal != null:
		_decal.visible = resolved.spawns_decal
		_decal.texture_albedo = resolved.decal_texture
		_decal.modulate = resolved.accent_color
	if _spark_material != null:
		_spark_material.albedo_color = resolved.accent_color
	if _particles != null:
		_particles.restart()
	AudioPool.play_3d(resolved.impact_sound, hit_position, AudioPool.BUS_IMPACTS)


func _on_released() -> void:
	_is_playing = false
	if _particles != null:
		_particles.emitting = false


func _orient_to(normal: Vector3) -> void:
	if normal.length_squared() < 0.001:
		return
	# Decals project down their local -Y, so aim that axis into the surface.
	var up: Vector3 = Vector3.FORWARD if absf(normal.dot(Vector3.UP)) > 0.999 else Vector3.UP
	look_at(global_position - normal, up)
