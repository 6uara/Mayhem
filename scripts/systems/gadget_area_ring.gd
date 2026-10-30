extends RefCounted
## El aro que se abre en el piso cuando detona un gadget, hasta el radio de su
## efecto y en su color.
##
## Es la respuesta a "no se que hizo": la granada aturdidora y el campo lento
## afectan a todo lo que esta dentro de un radio que nunca se veia. Con el aro,
## lo que quedo adentro se ve, y en la proxima el jugador ya sabe cuanto abarca.
## Se libera solo al terminar.

const RING_THICKNESS: float = 0.06


## Abre un aro en `at` hasta `radius`, del color `tint`, como hijo de `parent`.
static func spawn(parent: Node, at: Vector3, radius: float, tint: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0 - RING_THICKNESS
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 2.0
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = at + Vector3.UP * 0.05
	ring.scale = Vector3(0.2, 0.2, 0.2)
	var flat := Vector3(radius, 0.2, radius)
	var tween: Tween = ring.create_tween()
	tween.tween_property(ring, "scale", flat, Tokens.GADGET_AREA_FLASH * 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, Tokens.GADGET_AREA_FLASH * 0.5)
	tween.tween_callback(ring.queue_free)
	return ring
