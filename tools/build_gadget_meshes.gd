extends SceneTree
## Arma las mallas de los gadgets que tira el publico y la del lanzador del
## gancho, a .res.
##
##   godot --headless --path . -s res://tools/build_gadget_meshes.gd
##
## Sale a assets/models/meshes/gadget_<id>.res, que es lo que apunta
## `UtilityData.pickup_mesh`. Se vuelve a correr si cambia un modelo o una forma.
##
## Los cuatro gadgets son modelos de Meshy (assets/models/props/gadget_<id>.glb,
## de tools/blender/build_props.py): se saca su malla, con su textura, al mismo
## .res que ya apuntan los .tres. Una malla sin superficie "accent" conserva su
## material en el pickup (ver CrowdDropPickup._apply_accent()); el color del
## gadget ya viene pintado en sus acentos y lo repite la luz.
##
## El lanzador del gancho sigue siendo de primitivas: cuerpo neutro y acentos
## que se tiñen. Cada malla de primitivas tiene dos superficies con nombre:
## "body" (neutro, mate) y "accent" (lo que se tiñe y brilla), buscadas por
## nombre, asi que el orden no importa.

const OUT_DIR: String = "res://assets/models/meshes/"

var _body := SurfaceTool.new()
var _accent := SurfaceTool.new()


func _initialize() -> void:
	for id: String in ["stun_grenade", "temp_wall", "slow_field", "medkit"]:
		_extract(id)
	_build("grapple_launcher", _grapple_launcher, "grapple_launcher.res")
	quit()


func _build(id: String, shape: Callable, file_name: String = "") -> void:
	_body = SurfaceTool.new()
	_accent = SurfaceTool.new()
	_body.begin(Mesh.PRIMITIVE_TRIANGLES)
	_accent.begin(Mesh.PRIMITIVE_TRIANGLES)
	shape.call()
	var mesh := ArrayMesh.new()
	_body.commit(mesh)
	mesh.surface_set_name(0, "body")
	_accent.commit(mesh)
	mesh.surface_set_name(1, "accent")
	# Materiales por defecto aunque el juego los reemplace: una superficie sin
	# material ensucia el log al liberarse, y en el editor la malla se ve como va.
	var body := StandardMaterial3D.new()
	body.albedo_color = Color("#2C3140")
	body.roughness = 0.7
	mesh.surface_set_material(0, body)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color("#E6E8EF")
	accent.emission_enabled = true
	accent.emission = Color("#E6E8EF")
	mesh.surface_set_material(1, accent)
	var path: String = OUT_DIR + (file_name if file_name != "" else "gadget_%s.res" % id)
	var error: int = ResourceSaver.save(mesh, path)
	print("gadget %s -> %s (%s)" % [id, path, "ok" if error == OK else str(error)])


# Formas. Todas centradas en el origen, unos 60 cm en su eje mas largo: es lo que
# media la esfera que reemplazan, y el halo y la caja de agarre estan hechos a
# esa medida.

## La malla del modelo de un gadget, a su .res.
func _extract(id: String) -> void:
	var scene := load("res://assets/models/props/gadget_%s.glb" % id) as PackedScene
	if scene == null:
		print("gadget %s: falta el .glb" % id)
		return
	var instance: Node = scene.instantiate()
	var mesh: Mesh = null
	for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
		mesh = (node as MeshInstance3D).mesh
		break
	instance.free()
	var path: String = OUT_DIR + "gadget_%s.res" % id
	var error: int = ResourceSaver.save(mesh, path)
	print("gadget %s -> %s (%s)" % [id, path, "ok" if error == OK else str(error)])


## El lanzador del gancho, en la muñeca izquierda del viewmodel. No es un gadget
## del publico pero sale del mismo taller: cuerpo neutro y acentos cuadrados,
## que en el jugador son cian (lo suyo).
##
## En metros del rig de brazos sin escalar, adelante es -Z (hacia la mano) y
## arriba +Y (el dorso del antebrazo). El origen es donde apoya en la manga.
func _grapple_launcher() -> void:
	_add(_body, _box(Vector3(0.07, 0.045, 0.17)), Vector3(0.0, 0.0225, 0.0))
	# El carrete atras, atravesado: es lo que dice "esto tira un cable".
	_add(_body, _cylinder(0.034, 0.034, 0.08, 12), Vector3(0.0, 0.05, 0.05),
		Basis(Vector3.BACK, deg_to_rad(90.0)))
	_add(_body, _cylinder(0.016, 0.02, 0.07, 8), Vector3(0.0, 0.03, -0.115),
		Basis(Vector3.RIGHT, deg_to_rad(90.0)))
	# Tres uñas del gancho asomando de la boca.
	for angle: float in [0.0, 120.0, 240.0]:
		var spin := Basis(Vector3.FORWARD, deg_to_rad(angle))
		_add(_body, _box(Vector3(0.008, 0.03, 0.022)),
			Vector3(0.0, 0.03, -0.152) + spin * Vector3(0.0, 0.016, 0.0), spin)
	# Acentos: dos cuadrados arriba y la tapa del carrete.
	for z: float in [-0.04, 0.0]:
		_add(_accent, _box(Vector3(0.022, 0.006, 0.022)), Vector3(0.0, 0.048, z))
	for x: float in [-0.041, 0.041]:
		_add(_accent, _cylinder(0.02, 0.02, 0.004, 12), Vector3(x, 0.05, 0.05),
			Basis(Vector3.BACK, deg_to_rad(90.0)))


# Primitivas

func _add(tool: SurfaceTool, mesh: PrimitiveMesh, at: Vector3,
		basis: Basis = Basis.IDENTITY) -> void:
	tool.append_from(mesh, 0, Transform3D(basis, at))


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylinder(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh


