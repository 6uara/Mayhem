class_name ImpactEffect
extends Node3D
## Pooled impact feedback: particles, a decal on hard surfaces, and a surface-keyed sound.
## Grey-box first pass - the particle/decal art is replaced in Phase 5.

const LIFETIME: float = 1.2

@export var world_sound: AudioStream
@export var flesh_sound: AudioStream

@onready var _particles: GPUParticles3D = $Particles
@onready var _decal: Decal = $Decal

var _timer: float = 0.0
var _is_playing: bool = false


func _process(delta: float) -> void:
	if not _is_playing:
		return
	_timer -= delta
	if _timer <= 0.0:
		ObjectPool.release(self)


## Places the effect against a surface. `normal` orients both particles and decal.
func play_at(hit_position: Vector3, normal: Vector3, is_flesh: bool) -> void:
	global_position = hit_position
	_orient_to(normal)
	_timer = LIFETIME
	_is_playing = true

	if _decal != null:
		_decal.visible = not is_flesh
	if _particles != null:
		_particles.restart()
	AudioPool.play_3d(flesh_sound if is_flesh else world_sound, hit_position,
		AudioPool.BUS_IMPACTS)


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
