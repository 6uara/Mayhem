class_name StunGrenade
extends ThrownUtility
## Stuns every enemy in radius. The answer to being surrounded, and the reason
## elites are survivable at close range.

@export var stun_duration: float = 2.5
@export var flash_mesh: MeshInstance3D


func _activate() -> void:
	for enemy: Enemy in _enemies_in_radius(data.effect_radius if data != null else 5.0):
		enemy.apply_stun(stun_duration)
	_flash()


func _flash() -> void:
	if flash_mesh == null:
		ObjectPool.release(self)
		return
	# Placeholder pop until the VFX pass.
	flash_mesh.visible = true
	flash_mesh.scale = Vector3.ONE * 0.2
	var tween: Tween = create_tween()
	var radius: float = data.effect_radius if data != null else 5.0
	tween.tween_property(flash_mesh, "scale", Vector3.ONE * radius, 0.18)
	tween.parallel().tween_property(flash_mesh, "transparency", 1.0, 0.25)
	tween.tween_callback(func() -> void:
		flash_mesh.visible = false
		ObjectPool.release(self))
