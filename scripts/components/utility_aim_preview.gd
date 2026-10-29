extends Node3D
## La vista previa de un gadget en la mano: puntos por el arco que va a hacer y un
## aro donde va a caer, del tamaño del area que va a abarcar.
##
## Es lo que pidio el playtest: con el gadget equipado se apuntaba a ciegas, y
## recien al detonar se sabia adonde habia ido y a quien habia agarrado. Se ve
## solo en modo equipar (en quick cast el gadget sale en el acto) y en el color
## del gadget.
##
## Vive en el mundo, no en el viewmodel: lo que marca es un lugar de la arena.

const DOT_COUNT: int = 28
const DOT_SIZE: float = 0.05
## Radio del aro para lo que no tiene area (la barrera): la mitad de su ancho.
const FOOTPRINT_WITHOUT_AREA: float = 2.0

var utility: UtilityComponent

var _dots: MultiMeshInstance3D
var _ring: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	top_level = true
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.emission_enabled = true
	_material.emission_energy_multiplier = 1.5

	var dot := SphereMesh.new()
	dot.radius = DOT_SIZE
	dot.height = DOT_SIZE * 2.0
	dot.radial_segments = 6
	dot.rings = 3
	dot.material = _material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = dot
	multimesh.instance_count = DOT_COUNT
	_dots = MultiMeshInstance3D.new()
	_dots.multimesh = multimesh
	_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dots)

	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	torus.material = _material
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	visible = false


func _process(_delta: float) -> void:
	var slot: int = utility.armed_slot if utility != null else -1
	if slot < 0:
		visible = false
		return
	var points: PackedVector3Array = utility.predict_arc(slot)
	if points.size() < 2:
		visible = false
		return
	visible = true
	var data: UtilityData = utility.get_slot_data(slot)
	var tint: Color = data.accent_color if data != null else Tokens.TEXT
	_material.albedo_color = Color(tint, 0.85)
	_material.emission = tint

	# Puntos repartidos a lo largo del arco entero, no uno por paso de fisica: un
	# tiro largo y uno corto se leen igual de punteados.
	var last: int = points.size() - 1
	for index: int in DOT_COUNT:
		var along: float = float(index) / float(DOT_COUNT - 1) * float(last)
		var low: int = floori(along)
		var at: Vector3 = points[low].lerp(points[mini(low + 1, last)], along - float(low))
		_dots.multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, at))

	var radius: float = data.effect_radius if data != null and data.effect_radius > 0.0 \
		else FOOTPRINT_WITHOUT_AREA
	_ring.global_transform = Transform3D(Basis.from_scale(Vector3(radius, 1.0, radius)),
		points[last] + Vector3.UP * 0.05)
